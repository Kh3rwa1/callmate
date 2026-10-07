import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { chunkText, htmlToText, toFtsQuery, indexKnowledgeSource, retrieveKnowledge, ingestKnowledge } from '../src/services/knowledge';
import { buildSystemPrompt, loadHistory, saveTurn } from '../src/services/prompt';

describe('Phase 6: Knowledge Ingestion, FTS Search & Contextual Multi-Turn Chat', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const bizId = 'biz_p6_test';
  const userId = 'usr_p6_test';
  const phone = '919876543111';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Apex Coaching Institute', 'coaching')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agent_p6', ?, 'Maya', 'Counselor', 'active')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_p6', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  describe('Part 1: Text Processing & FTS Queries', () => {
    it('chunkText splits text into overlapping chunks preferring sentence boundaries', () => {
      const text = 'First sentence here. Second sentence follows. Third sentence goes on. ' +
        'Fourth sentence is here. Fifth sentence completes the paragraph.\n\n' +
        'New paragraph starts now. It has important admission details. Fees are Rs 50,000 per year.';
      const chunks = chunkText(text, 100, 20);
      expect(chunks.length).toBeGreaterThan(1);
      expect(chunks[0]).toContain('First sentence');
    });

    it('htmlToText strips HTML tags, scripts, and entities', () => {
      const html = '<html><head><script>alert(1)</script><style>body{color:red}</style></head>' +
        '<body><h1>Welcome to Apex</h1><p>Call us at <b>9876543210</b> &amp; visit our campus.</p></body></html>';
      const clean = htmlToText(html);
      expect(clean).not.toContain('alert');
      expect(clean).not.toContain('<style>');
      expect(clean).toContain('Welcome to Apex');
      expect(clean).toContain('& visit our campus.');
    });

    it('toFtsQuery constructs safe boolean query preventing injection', () => {
      const q = 'What is the "annual" fee for class 11?';
      const fts = toFtsQuery(q);
      expect(fts).toBe('"what" OR "is" OR "the" OR "annual" OR "fee" OR "for" OR "class" OR "11"');
      expect(toFtsQuery('')).toBeNull();
      expect(toFtsQuery('a ! @ #')).toBeNull();
    });
  });

  describe('Part 2: Knowledge Ingestion & FTS Search', () => {
    it('indexes source and retrieves relevant chunks via FTS5 bm25', async () => {
      const sourceId = `kn_${crypto.randomUUID().slice(0, 10)}`;
      await env.DB.prepare(
        "INSERT INTO knowledge_sources (id, business_id, type, title, status, progress) VALUES (?, ?, 'text', 'Science Batch', 'ready', 1.0)"
      ).bind(sourceId, bizId).run();
      const content = 'Class 11 Science batch starts on July 15. The fee is Rs 45,000 per term. ' +
        'Scholarships up to 30 percent are available for top performers. Admissions close on June 30.';

      const n = await indexKnowledgeSource(env, bizId, sourceId, content);
      expect(n).toBeGreaterThan(0);

      const results = await retrieveKnowledge(env, bizId, 'How much is the fee for Class 11?');
      expect(results.length).toBeGreaterThan(0);
      expect(results[0]).toContain('fee is Rs 45,000');
    });

    it('ingestKnowledge sets status to ready on text and failed on invalid url', async () => {
      const validSrcId = `kn_v_${crypto.randomUUID().slice(0, 8)}`;
      await env.DB.prepare(
        "INSERT INTO knowledge_sources (id, business_id, type, title, status, progress) VALUES (?, ?, 'text', 'Fee Structure', 'processing', 0.1)"
      ).bind(validSrcId, bizId).run();

      await ingestKnowledge(env, bizId, {
        id: validSrcId,
        type: 'text',
        content: 'Weekend batch timings are 9 AM to 1 PM every Saturday and Sunday.',
      });

      const updated = await env.DB.prepare("SELECT status, progress, detail FROM knowledge_sources WHERE id = ?").bind(validSrcId).first<any>();
      expect(updated.status).toBe('ready');
      expect(updated.progress).toBe(1.0);
      expect(updated.detail).toContain('sections learned');

      // Invalid scheme
      const badSrcId = `kn_b_${crypto.randomUUID().slice(0, 8)}`;
      await env.DB.prepare(
        "INSERT INTO knowledge_sources (id, business_id, type, title, status, progress) VALUES (?, ?, 'website', 'Bad Scheme', 'processing', 0.1)"
      ).bind(badSrcId, bizId).run();

      await ingestKnowledge(env, bizId, {
        id: badSrcId,
        type: 'website',
        url: 'ftp://malicious.org/doc',
      });

      const failed = await env.DB.prepare("SELECT status, progress FROM knowledge_sources WHERE id = ?").bind(badSrcId).first<any>();
      expect(failed.status).toBe('failed');
      expect(failed.progress).toBe(0);
    });
  });

  describe('Part 3: System Prompt & Conversation Memory', () => {
    it('buildSystemPrompt binds category goal, agent details, and knowledge', () => {
      const prompt = buildSystemPrompt({
        agentName: 'Maya',
        agentRole: 'Counselor',
        businessName: 'Apex Coaching',
        category: 'coaching',
        knowledge: ['Batch fee is Rs 40,000', 'Office hours 10 AM to 7 PM'],
      });

      expect(prompt).toContain('You are Maya, an AI Counselor for Apex Coaching.');
      expect(prompt).toContain('courses, batches and fees');
      expect(prompt).toContain('[1] Batch fee is Rs 40,000');
      expect(prompt).toContain('[2] Office hours 10 AM to 7 PM');
    });

    it('saveTurn and loadHistory persists conversation turns', async () => {
      const convId = `conv_${crypto.randomUUID().slice(0, 8)}`;
      await saveTurn(env.DB, bizId, convId, 'What are your timings?', 'We are open from 10 AM to 7 PM.');
      await saveTurn(env.DB, bizId, convId, 'Can I visit tomorrow?', 'Yes, please feel free to visit us tomorrow.');

      const history = await loadHistory(env.DB, bizId, convId, 10);
      expect(history.length).toBe(4);
      expect(history[0]).toEqual({ role: 'user', content: 'What are your timings?' });
      expect(history[1]).toEqual({ role: 'assistant', content: 'We are open from 10 AM to 7 PM.' });
      expect(history[2]).toEqual({ role: 'user', content: 'Can I visit tomorrow?' });
      expect(history[3]).toEqual({ role: 'assistant', content: 'Yes, please feel free to visit us tomorrow.' });
    });
  });

  describe('Part 4: /voice/chat Multi-Turn & Knowledge Integration', () => {
    it('/voice/chat creates conversation_id, injects knowledge and records turns', async () => {
      // Seed a knowledge source with specific facts
      const docId = `kn_chat_${crypto.randomUUID().slice(0, 8)}`;
      await env.DB.prepare(
        "INSERT INTO knowledge_sources (id, business_id, type, title, status, progress) VALUES (?, ?, 'text', 'NEET Course', 'ready', 1.0)"
      ).bind(docId, bizId).run();
      const docContent = 'Special crash course for NEET 2027 costs exactly Rs 29,999 with 50 mock tests included.';
      await indexKnowledgeSource(env, bizId, docId, docContent);

      // Call /voice/chat without conversation_id
      const res1 = await app.fetch(
        new Request('http://localhost/voice/chat', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ message: 'How much does the NEET crash course cost?' }),
        }),
        { ...env, JWT_SIGNING_KEY: secret }
      );

      expect(res1.status).toBe(200);
      const data1: any = await res1.json();
      expect(data1.conversation_id).toBeDefined();
      expect(data1.conversation_id).toMatch(/^conv_/);
      expect(data1.reply).toBeDefined();

      const convId = data1.conversation_id;

      // Second turn using the returned conversation_id
      const res2 = await app.fetch(
        new Request('http://localhost/voice/chat', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            conversation_id: convId,
            message: 'Does that price include mock tests?',
          }),
        }),
        { ...env, JWT_SIGNING_KEY: secret }
      );

      expect(res2.status).toBe(200);
      const data2: any = await res2.json();
      expect(data2.conversation_id).toBe(convId);

      // Verify chat_messages has both turns recorded
      const history = await loadHistory(env.DB, bizId, convId, 10);
      expect(history.length).toBe(4);
      expect(history[0].content).toBe('How much does the NEET crash course cost?');
      expect(history[2].content).toBe('Does that price include mock tests?');
    });
  });
});
