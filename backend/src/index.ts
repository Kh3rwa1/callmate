import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { Env, AuthUser } from './types';
import { authMiddleware } from './auth';

import { authApp } from './routes/auth';
import { businessApp } from './routes/business';
import { leadsApp } from './routes/leads';
import { callsApp } from './routes/calls';
import { campaignsApp } from './routes/campaigns';
import { fcApp } from './routes/followups_callbacks';
import { knowledgeApp } from './routes/knowledge';
import { dashApp } from './routes/dashboard';
import { voiceApp } from './routes/voice';

const app = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// Enable CORS for mobile app & web clients
app.use('*', cors({
  origin: '*',
  allowHeaders: ['Authorization', 'Content-Type', 'X-App-Flavor', 'X-API-Key'],
  allowMethods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
  exposeHeaders: ['Content-Length', 'X-App-Flavor'],
  maxAge: 86400,
}));

app.use('*', logger());

// Health check
app.get('/', (c) => c.json({
  service: 'CallPilot API',
  platform: 'Cloudflare Workers + D1',
  version: '1.0.0',
  status: 'healthy',
  time: new Date().toISOString(),
}));

app.get('/health', (c) => c.json({ status: 'ok' }));

// ------------------------------------------------------------- Public Routes
app.route('/auth', authApp);

// Public Sarvam completed call webhook
app.post('/webhooks/sarvam', (c) => voiceApp.fetch(c.req.raw, c.env, c.executionCtx));

// Voice proxy (has its own session token verification in route)
app.all('/voice/sarvam-proxy/*', (c) => voiceApp.fetch(c.req.raw, c.env, c.executionCtx));

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
protectedApp.route('/voice', voiceApp);

app.route('/', protectedApp);

// Global Error Handler
app.onError((err, c) => {
  console.error('[Unhandled Server Error]:', err);
  return c.json({
    message: err.message || 'Internal Server Error',
    code: 'server_error',
  }, 500);
});

// 404 Handler
app.notFound((c) => {
  return c.json({
    message: `Endpoint ${c.req.path} not found.`,
    code: 'not_found',
  }, 404);
});

export default app;
