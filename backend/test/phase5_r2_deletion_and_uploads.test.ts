import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { deleteR2Prefix, r2KeyFromFileUrl } from '../src/utils/r2';

describe('Phase 5: R2 Data Deletion & Upload Restrictions', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const bizId = 'biz_p5_test';
  const userId = 'usr_p5_test';
  const phone = '919876543222';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Phase 5 Biz', 'retail')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agent_p5', ?, 'Riya', 'Sales', 'active')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_p5', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  describe('Part 1: R2 Utilities', () => {
    it('r2KeyFromFileUrl extracts R2 key correctly', () => {
      expect(r2KeyFromFileUrl('/r2/biz_123/file.pdf')).toBe('biz_123/file.pdf');
      expect(r2KeyFromFileUrl('https://example.com/file.pdf')).toBeNull();
      expect(r2KeyFromFileUrl(null)).toBeNull();
      expect(r2KeyFromFileUrl('')).toBeNull();
    });

    it('deleteR2Prefix deletes all objects under a prefix', async () => {
      const deletedKeys: string[][] = [];
      const mockBucket: any = {
        list: async ({ prefix, cursor }: any) => {
          if (!cursor) {
            return {
              objects: [{ key: `${prefix}doc1.pdf` }, { key: `${prefix}doc2.pdf` }],
              truncated: true,
              cursor: 'cursor_page_2',
            };
          }
          return {
            objects: [{ key: `${prefix}doc3.pdf` }],
            truncated: false,
          };
        },
        delete: async (keys: string[]) => {
          deletedKeys.push(keys);
        },
      };

      const count = await deleteR2Prefix(mockBucket, 'biz_123/');
      expect(count).toBe(3);
      expect(deletedKeys).toEqual([['biz_123/doc1.pdf', 'biz_123/doc2.pdf'], ['biz_123/doc3.pdf']]);

      // Returns 0 if bucket is undefined
      expect(await deleteR2Prefix(undefined, 'biz_123/')).toBe(0);
    });
  });

  describe('Part 2: File Upload Restrictions & Sanitization', () => {
    it('rejects uploads exceeding 10 MB', async () => {
      const boundary = '----WebKitFormBoundaryTest123';
      const body = `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="type"\r\n\r\n` +
        `pdf\r\n` +
        `--${boundary}\r\n` +
        `Content-Disposition: form-data; name="file"; filename="huge.pdf"\r\n` +
        `Content-Type: application/pdf\r\n\r\n` +
        `fake content\r\n` +
        `--${boundary}--\r\n`;

      // We use FormData via browser/standard Request
      const formData = new FormData();
      // Create a mock large file > 10 MB
      const largeBlob = new Blob([new Uint8Array(10 * 1024 * 1024 + 10)], { type: 'application/pdf' });
      formData.append('type', 'pdf');
      formData.append('file', largeBlob, 'huge.pdf');

      const res = await app.fetch(
        new Request('http://localhost/knowledge', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
          },
          body: formData,
        }),
        { ...env, JWT_SIGNING_KEY: secret }
      );

      expect(res.status).toBe(400);
      const data: any = await res.json();
      expect(data.code).toBe('file_too_large');
    });

    it('rejects disallowed MIME types', async () => {
      const formData = new FormData();
      const exeBlob = new Blob(['malicious payload'], { type: 'application/x-msdownload' });
      formData.append('type', 'pdf');
      formData.append('file', exeBlob, 'virus.exe');

      const res = await app.fetch(
        new Request('http://localhost/knowledge', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
          },
          body: formData,
        }),
        { ...env, JWT_SIGNING_KEY: secret }
      );

      expect(res.status).toBe(400);
      const data: any = await res.json();
      expect(data.code).toBe('invalid_file_type');
    });

    it('sanitises filenames and stores valid uploads in R2', async () => {
      const storedObjects: Record<string, any> = {};
      const mockBucket: any = {
        put: async (key: string, body: any, opts: any) => {
          storedObjects[key] = { body, opts };
        },
      };

      const formData = new FormData();
      const validBlob = new Blob(['test content markdown'], { type: 'text/markdown' });
      formData.append('type', 'text');
      formData.append('title', 'My Clean Doc');
      formData.append('file', validBlob, 'test @#$ dangerous name!.md');

      const res = await app.fetch(
        new Request('http://localhost/knowledge', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
          },
          body: formData,
        }),
        { ...env, JWT_SIGNING_KEY: secret, KNOWLEDGE_BUCKET: mockBucket }
      );

      expect(res.status).toBe(200);
      const data: any = await res.json();
      expect(data.title).toBe('My Clean Doc');

      // Check stored key name has sanitized characters
      const keys = Object.keys(storedObjects);
      expect(keys.length).toBe(1);
      const key = keys[0];
      expect(key).toMatch(new RegExp(`^${bizId}/[a-f0-9-]+-test_____dangerous_name_\\.md$`));
    });
  });

  describe('Part 3: DELETE /knowledge/:id Deletes from R2 and DB', () => {
    it('deletes R2 object when deleting knowledge source', async () => {
      const docId = `kn_${crypto.randomUUID().slice(0, 10)}`;
      const r2Key = `${bizId}/doc_to_delete.pdf`;
      const fileUrl = `/r2/${r2Key}`;

      await env.DB.prepare(
        `INSERT INTO knowledge_sources (id, business_id, type, title, status, file_url)
         VALUES (?, ?, 'pdf', 'To Delete', 'ready', ?)`
      ).bind(docId, bizId, fileUrl).run();

      const deletedKeys: string[] = [];
      const mockBucket: any = {
        delete: async (k: string) => {
          deletedKeys.push(k);
        },
      };

      const res = await app.fetch(
        new Request(`http://localhost/knowledge/${docId}`, {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${token}`,
          },
        }),
        { ...env, JWT_SIGNING_KEY: secret, KNOWLEDGE_BUCKET: mockBucket }
      );

      expect(res.status).toBe(200);
      expect(deletedKeys).toContain(r2Key);

      // Verify DB record is deleted
      const check = await env.DB.prepare('SELECT id FROM knowledge_sources WHERE id = ?').bind(docId).first();
      expect(check).toBeNull();
    });
  });

  describe('Part 4: DELETE /auth/account Cleans R2 and Auxiliary Tables', () => {
    it('deletes R2 prefix and deletes from usage_ledger, voice_sessions, rate_limits', async () => {
      const delBiz = `biz_del_${crypto.randomUUID().slice(0, 8)}`;
      const delUser = `usr_del_${crypto.randomUUID().slice(0, 8)}`;
      const delPhone = '919876543333';

      await env.DB.batch([
        env.DB.prepare("INSERT INTO businesses (id, name, category) VALUES (?, 'To Delete', 'retail')").bind(delBiz),
        env.DB.prepare("INSERT INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(delUser, delPhone, delBiz),
        env.DB.prepare("INSERT INTO usage_ledger (call_id, business_id, billable_seconds, billed_minutes) VALUES ('call_del_1', ?, 60, 1)").bind(delBiz),
        env.DB.prepare("INSERT INTO voice_sessions (id, business_id, user_id, status) VALUES ('vs_del_1', ?, ?, 'active')").bind(delBiz, delUser),
        env.DB.prepare("INSERT INTO rate_limits (id, bucket) VALUES ('rl_del_1', ?)").bind(`chat:biz:${delBiz}:daily`),
      ]);

      const delToken = await signJWT({ sub: delUser, phone: delPhone, business_id: delBiz, type: 'access' }, secret, 3600);

      const deletedPrefixes: string[] = [];
      const mockBucket: any = {
        list: async ({ prefix }: any) => {
          deletedPrefixes.push(prefix);
          return { objects: [{ key: `${prefix}file.pdf` }], truncated: false };
        },
        delete: async () => {},
      };

      const res = await app.fetch(
        new Request('http://localhost/auth/account', {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${delToken}`,
          },
        }),
        { ...env, JWT_SIGNING_KEY: secret, KNOWLEDGE_BUCKET: mockBucket }
      );

      expect(res.status).toBe(200);
      expect(deletedPrefixes).toContain(`${delBiz}/`);

      // Verify auxiliary tables cleaned
      const ledgerCheck = await env.DB.prepare('SELECT * FROM usage_ledger WHERE business_id = ?').bind(delBiz).first();
      expect(ledgerCheck).toBeNull();

      const vsCheck = await env.DB.prepare('SELECT * FROM voice_sessions WHERE business_id = ?').bind(delBiz).first();
      expect(vsCheck).toBeNull();

      const rlCheck = await env.DB.prepare("SELECT * FROM rate_limits WHERE bucket LIKE ?").bind(`chat:biz:${delBiz}%`).first();
      expect(rlCheck).toBeNull();

      const bizCheck = await env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(delBiz).first();
      expect(bizCheck).toBeNull();
    });
  });
});
