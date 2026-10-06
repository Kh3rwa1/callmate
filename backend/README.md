# CallPilot Cloudflare Backend

Serverless backend built entirely on **Cloudflare Workers**, **Cloudflare D1**, and **Cloudflare R2**, integrating with **Sarvam AI Voice Agents**.

## Architecture

```
Flutter Mobile App ──(Bearer JWT)──► Cloudflare Worker (Hono) ──(D1 SQL)──► Cloudflare D1
         │                                       │
         │ (Voice Test Session)                  ├─► Cloudflare R2 (Knowledge docs)
         ▼                                       │
  Sarvam SamvaadAgent ──► /voice/sarvam-proxy/* ──(X-API-Key)──► Sarvam AI App Runtime
                                                 ▲
                                                 │
                                     Sarvam Completed Call Webhook
                                        (/webhooks/sarvam)
```

## Cloudflare Infrastructure Units

- **Cloudflare Workers**: Handles all REST APIs, authentication, and the secure Sarvam reverse proxy with WebSocket support.
- **Cloudflare D1 (Serverless SQLite)**: Stores users, businesses, agents, leads, calls, campaigns, follow-ups, callbacks, notifications, and usage.
- **Cloudflare R2**: Object storage for knowledge base uploads (PDFs, course brochures, audio files).
- **Web Crypto API**: Native HS256 JWT generation and validation without heavy external libraries.

## Quick Start (Local Development)

```bash
cd backend

# 1. Install dependencies
npm install

# 2. Run local D1 database migration & seed
npm run db:migrate
npm run db:seed

# 3. Start local development server
npm run dev
# Server runs on http://localhost:8787
```

## Cloudflare Deployment

```bash
# 1. Create remote D1 database
npx wrangler d1 create callpilot-db
# Copy database_id into wrangler.toml

# 2. Create remote R2 bucket
npx wrangler r2 bucket create callpilot-knowledge

# 3. Set production secrets
npx wrangler secret put JWT_SIGNING_KEY
npx wrangler secret put SARVAM_API_KEY
npx wrangler secret put SARVAM_WEBHOOK_SECRET
npx wrangler secret put SARVAM_ORG_ID
npx wrangler secret put SARVAM_WORKSPACE_ID
npx wrangler secret put SARVAM_ADMISSIONS_APP_ID

# 4. Run remote migrations
npm run db:migrate:prod

# 5. Deploy to Cloudflare Workers
npm run deploy
```
