import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { isAllowedSarvamPath } from '../src/services/sarvam_proxy_guard';

describe('Phase 3 Sarvam Proxy Guard Unit & Integration Tests', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const bizId = 'biz_proxy_test';
  const userId = 'usr_proxy_test';
  const phone = '919830005555';
  let sessionToken: string;

  const validEnv = {
    SARVAM_ORG_ID: 'org_allowed_123',
    SARVAM_WORKSPACE_ID: 'ws_allowed_456',
    SARVAM_ADMISSIONS_APP_ID: 'app_allowed_789',
  };

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Proxy Biz')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
    ]);

    sessionToken = await signJWT({ sub: userId, phone, business_id: bizId, type: 'session' }, secret, 3600);
  });

  describe('isAllowedSarvamPath pure logic', () => {
    it('allows valid paths targeting configured org, workspace, and app', () => {
      const path = 'orgs/org_allowed_123/workspaces/ws_allowed_456/apps/app_allowed_789/url';
      expect(isAllowedSarvamPath(path, validEnv)).toBe(true);
    });

    it('rejects foreign org IDs (tenant isolation)', () => {
      const foreignOrgPath = 'orgs/attacker_org/workspaces/ws_allowed_456/apps/app_allowed_789/url';
      expect(isAllowedSarvamPath(foreignOrgPath, validEnv)).toBe(false);
    });

    it('rejects foreign workspace or app IDs', () => {
      const badWs = 'orgs/org_allowed_123/workspaces/attacker_ws/apps/app_allowed_789/url';
      expect(isAllowedSarvamPath(badWs, validEnv)).toBe(false);

      const badApp = 'orgs/org_allowed_123/workspaces/ws_allowed_456/apps/attacker_app/url';
      expect(isAllowedSarvamPath(badApp, validEnv)).toBe(false);
    });

    it('rejects directory traversal and encoded traversal tricks', () => {
      expect(isAllowedSarvamPath('orgs/org_allowed_123/../../../etc/passwd', validEnv)).toBe(false);
      expect(isAllowedSarvamPath('orgs/org_allowed_123/..\\admin', validEnv)).toBe(false);
      expect(isAllowedSarvamPath('orgs/org_allowed_123/%2e%2e/admin', validEnv)).toBe(false);
      expect(isAllowedSarvamPath('orgs/org_allowed_123/%2fadmin', validEnv)).toBe(false);
    });

    it('refuses to proxy when Sarvam IDs are missing in env', () => {
      const path = 'orgs/org_allowed_123/workspaces/ws_allowed_456/apps/app_allowed_789/url';
      expect(isAllowedSarvamPath(path, { SARVAM_ORG_ID: undefined, SARVAM_WORKSPACE_ID: undefined, SARVAM_ADMISSIONS_APP_ID: undefined })).toBe(false);
      expect(isAllowedSarvamPath(path, { SARVAM_ORG_ID: 'org_allowed_123', SARVAM_WORKSPACE_ID: undefined, SARVAM_ADMISSIONS_APP_ID: undefined })).toBe(false);
    });
  });

  describe('Voice proxy route enforcement with forbidden_upstream', () => {
    it('returns 403 with code forbidden_upstream when foreign org is requested', async () => {
      const testEnv = {
        ...env,
        JWT_SIGNING_KEY: secret,
        ...validEnv,
      };

      const res = await app.fetch(
        new Request('http://localhost/voice/sarvam-proxy/orgs/attacker_org/workspaces/ws_allowed_456/apps/app_allowed_789/url', {
          headers: { Authorization: `Bearer ${sessionToken}` },
        }),
        testEnv
      );

      expect(res.status).toBe(403);
      const data = (await res.json()) as any;
      expect(data.code).toBe('forbidden_upstream');
    });

    it('returns 403 with code forbidden_upstream when traversal path is attempted', async () => {
      const testEnv = {
        ...env,
        JWT_SIGNING_KEY: secret,
        ...validEnv,
      };

      const res = await app.fetch(
        new Request('http://localhost/voice/sarvam-proxy/orgs/org_allowed_123/../admin', {
          headers: { Authorization: `Bearer ${sessionToken}` },
        }),
        testEnv
      );

      expect(res.status).toBe(403);
      const data = (await res.json()) as any;
      expect(data.code).toBe('forbidden_upstream');
    });

    it('refuses to proxy when Sarvam env IDs are not configured', async () => {
      const unconfiguredEnv = {
        ...env,
        JWT_SIGNING_KEY: secret,
        SARVAM_ORG_ID: undefined,
        SARVAM_WORKSPACE_ID: undefined,
        SARVAM_ADMISSIONS_APP_ID: undefined,
      };

      const res = await app.fetch(
        new Request('http://localhost/voice/sarvam-proxy/orgs/org_allowed_123/workspaces/ws_allowed_456/apps/app_allowed_789/url', {
          headers: { Authorization: `Bearer ${sessionToken}` },
        }),
        unconfiguredEnv
      );

      expect(res.status).toBe(403);
      const data = (await res.json()) as any;
      expect(data.code).toBe('forbidden_upstream');
    });
  });
});
