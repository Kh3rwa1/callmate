import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { secureHeaders } from 'hono/secure-headers';
import { Env, AuthUser } from './types';
import { authMiddleware } from './auth';
import { requestLogger } from './utils/logger';
import { jsonErrorHandler } from './utils/errors';
import { timingSafeEqual } from './utils/compare';
import { isDevEnv } from './utils/secrets';
import { runMaintenance } from './services/maintenance';

import { authApp } from './routes/auth';
import { businessApp } from './routes/business';
import { leadsApp } from './routes/leads';
import { callsApp } from './routes/calls';
import { campaignsApp } from './routes/campaigns';
import { fcApp } from './routes/followups_callbacks';
import { knowledgeApp } from './routes/knowledge';
import { dashApp } from './routes/dashboard';
import { voiceApp, handleSarvamWebhook } from './routes/voice';
import { billingApp, handleRazorpayWebhook } from './routes/billing';
import { runBillingRenewals } from './services/plans';

const app = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// Enable CORS for mobile app & web clients
app.use('*', cors({
  origin: (origin, c) => {
    if (isDevEnv(c.env)) return '*';
    if (!origin) return null;
    const allowed = (c.env.ALLOWED_ORIGINS || '')
      .split(',')
      .map((s: string) => s.trim())
      .filter(Boolean);
    return allowed.includes(origin) ? origin : null;
  },
  allowHeaders: ['Authorization', 'Content-Type', 'X-App-Flavor', 'X-API-Key'],
  allowMethods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
  exposeHeaders: ['Content-Length', 'X-App-Flavor'],
  maxAge: 86400,
}));

app.use('*', async (c, next) => {
  const reqId = c.req.header('X-Request-Id') || crypto.randomUUID();
  c.set('requestId' as any, reqId);
  c.header('X-Request-Id', reqId);
  await next();
});

// Never log query strings (they can carry phone numbers, e.g. /leads?q=98...)
app.use('*', requestLogger);

// Security headers on everything except the voice proxy, which streams the upstream Response as-is
// (including WebSocket upgrades whose headers are immutable).
const secure = secureHeaders();
app.use('*', async (c, next) => {
  if (c.req.path.startsWith('/voice/sarvam-proxy/')) return next();
  return secure(c, next);
});

// Health check
app.get('/', (c) => c.json({
  service: 'CallPilot API',
  platform: 'Cloudflare Workers + D1',
  version: '1.0.0',
  status: 'healthy',
  time: new Date().toISOString(),
}));

app.get('/health', (c) => c.json({ status: 'ok' }));

app.get('/health/deep', async (c) => {
  const secret = c.env.HEALTH_CHECK_SECRET;
  if (!secret) {
    return c.json({ error: 'HEALTH_CHECK_SECRET is required on server' }, 500);
  }

  const key =
    c.req.header('x-health-key') ||
    c.req.header('authorization')?.replace(/^Bearer\s+/i, '');
  if (!key || !timingSafeEqual(key, secret)) {
    return c.json({ error: 'Unauthorized deep health check probe' }, 401);
  }

  const checks = {
    d1: false,
    r2: false,
    sarvam_config: false,
  };

  try {
    const d1Res = await c.env.DB.prepare('SELECT 1 as alive').first<{ alive: number }>();
    if (d1Res?.alive === 1) checks.d1 = true;
  } catch (err: any) {
    console.error('[Health Check] D1 check failed:', err?.message);
  }

  try {
    if (c.env.KNOWLEDGE_BUCKET) {
      await c.env.KNOWLEDGE_BUCKET.list({ limit: 1 });
      checks.r2 = true;
    } else {
      checks.r2 = true;
    }
  } catch (err: any) {
    console.error('[Health Check] R2 check failed:', err?.message);
  }

  checks.sarvam_config = Boolean(
    c.env.SARVAM_API_KEY &&
    c.env.SARVAM_ORG_ID &&
    c.env.SARVAM_WORKSPACE_ID &&
    c.env.SARVAM_ADMISSIONS_APP_ID
  );

  const healthy = checks.d1 && checks.r2 && checks.sarvam_config;
  const status = healthy ? 'healthy' : 'unhealthy';
  const statusCode = healthy ? 200 : 503;

  return c.json(
    {
      status,
      checks,
      time: new Date().toISOString(),
    },
    statusCode
  );
});

// ------------------------------------------------------------- Public Routes
app.route('/auth', authApp);

// Public Sarvam completed call webhook
app.post('/webhooks/sarvam', handleSarvamWebhook);

// Public Razorpay webhook (verified by X-Razorpay-Signature)
app.post('/webhooks/razorpay', handleRazorpayWebhook);

// Voice proxy (has its own session token verification in route)
app.all('/voice/sarvam-proxy/*', (c) => {
  let ctx: any;
  try {
    ctx = c.executionCtx;
  } catch {}
  return voiceApp.fetch(c.req.raw, c.env, ctx);
});

// ------------------------------------------------------------- Protected Routes
const protectedApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();
protectedApp.use('*', authMiddleware);

// Mount all protected resource routes
protectedApp.route('/', businessApp);
protectedApp.route('/', leadsApp);
protectedApp.route('/', callsApp);
protectedApp.route('/', campaignsApp);
protectedApp.route('/', fcApp);
protectedApp.route('/', knowledgeApp);
protectedApp.route('/', dashApp);
protectedApp.route('/', billingApp);
protectedApp.route('/voice', voiceApp);

app.route('/', protectedApp);

// Global Error Handler - 1.6 & 5: Generic message with request ID, structured JSON log
app.onError(jsonErrorHandler);

import { handleCampaignQueueBatch, handleCampaignDlqBatch, isDeadLetterQueue } from './services/campaign_queue';

// 404 Handler
app.notFound((c) => {
  return c.json({
    message: `Endpoint ${c.req.path} not found.`,
    code: 'not_found',
  }, 404);
});

export default {
  fetch: app.fetch,
  async queue(batch: MessageBatch<any>, env: Env): Promise<void> {
    if (isDeadLetterQueue(batch.queue)) {
      await handleCampaignDlqBatch(batch, env);
      return;
    }
    await handleCampaignQueueBatch(batch, env);
  },
  async scheduled(_ctrl: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(runMaintenance(env));
    ctx.waitUntil(runBillingRenewals(env));
  },
};

