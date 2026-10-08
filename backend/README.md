# CallPilot Backend

Production serverless backend built on **Cloudflare Workers**, **Cloudflare D1** (SQLite), **Cloudflare R2** (Object Storage), and **Cloudflare Queues**, orchestrating telephony and conversational AI via **Sarvam AI Voice Agents**.

---

## Architecture Overview

```
Flutter App ──(Bearer JWT)──► Cloudflare Worker (Hono) ──(D1 SQL)──► Cloudflare D1
     │                                     │
     │ (Voice Test Session)                ├─► Cloudflare R2 (Encrypted Knowledge)
     ▼                                     │
Sarvam SamvaadAgent ──► /voice/sarvam-proxy/* ──► Sarvam App Runtime
                            ▲              │
                            │              └─► Cloudflare Queues (Campaign Dispatch)
                            │
              Sarvam Completed Call Webhook
                 (POST /webhooks/sarvam)
```

### Core Components

1. **Cloudflare Workers & Hono:** Fast edge REST APIs, secure reverse proxy with WebSocket support, and background queue consumer handlers.
2. **Cloudflare D1:** Serverless SQLite database with tenant-isolated tables (`users`, `businesses`, `agents`, `leads`, `calls`, `campaigns`, `campaign_leads`, `followups`, `callbacks`, `notifications`, `usage`, `otp_codes`, `refresh_tokens`, `device_tokens`).
3. **Cloudflare R2:** Tenant-scoped object storage for knowledge documents (`${business_id}/${doc_id}`).
4. **Cloudflare Queues:** Reliable campaign dispatch (`callpilot-campaign-dispatch`) with concurrency throttling, retries, dead-letter queues (`callpilot-campaign-dlq`), and idempotency keys.
5. **Web Crypto API:** Native HS256 JWT validation and AES-256-GCM data encryption at rest.

---

## Quick Start (Local Development)

```bash
cd backend

# 1. Install dependencies
npm install

# 2. Run local database migrations
npm run db:migrate
npm run db:seed

# 3. Type check & run full test suite with coverage
npm run typecheck
npm run test:coverage

# 4. Start local development server
npm run dev
# Server listening on http://localhost:8787
```

---

## Database Migrations

Schema migrations live in `backend/migrations/` and are applied with
`wrangler d1 migrations apply`, which records each applied file in the
`d1_migrations` table, so re-running is safe and only new files are applied:

```bash
npm run db:migrate          # local
npm run db:migrate:staging  # staging (remote)
npm run db:migrate:prod     # production (remote)
```

Demo data is **not** a migration: it lives in `backend/seeds/0001_demo_seed.sql`
and is only loaded locally with `npm run db:seed`. Never apply it remotely.

To change the schema, add the next numbered file (e.g. `0008_<name>.sql`).
Never edit a migration that has already been applied anywhere.

---

## Production Secrets & Environment Variables

Configure with `wrangler secret put <KEY>`:

| Variable | Description | Requirement |
|---|---|---|
| `JWT_SIGNING_KEY` | HS256 secret key | **Mandatory** (≥ 32 characters, fail-closed) |
| `OTP_PEPPER` | HMAC-SHA256 secret pepper for OTP hashing | **Mandatory** (≥ 32 characters, fail-closed) |
| `ENCRYPTION_KEY` | AES-256 key for data encryption at rest | **Mandatory** (≥ 32 characters) |
| `SARVAM_API_KEY` | Sarvam AI API secret | **Mandatory** for outbound calls & proxy |
| `SARVAM_WEBHOOK_SECRET`| HMAC-SHA256 signature secret | **Mandatory** for `/webhooks/sarvam` |
| `MSG91_AUTH_KEY` | MSG91 SMS gateway auth key | Required for production SMS |
| `GUPSHUP_API_KEY` | Gupshup SMS gateway API key | Alternative SMS provider |
| `EXOTEL_SID` / `EXOTEL_TOKEN` | Exotel SMS credentials | Alternative SMS provider |
| `FCM_SERVICE_ACCOUNT_JSON` | Firebase service account JSON (needs `project_id`, `client_email`, `private_key`) | Required for push notifications (FCM HTTP v1) |
| `PUBLIC_API_BASE_URL` | Public https origin of this Worker, e.g. `https://api.yourdomain.com` (a `[vars]` entry, not a secret) | Required: Sarvam webhooks for queued/retried campaign calls use it |
| `HEALTH_CHECK_SECRET` | Token for `GET /health/deep` | Recommended |
| `ALLOWED_ORIGINS` | Comma-separated CORS origins | Optional (Android app needs none) |

---

## Deployment

Both environments deploy from CI (see `RUNBOOK.md`). Manually:

```bash
npm run db:migrate:staging && npm run deploy:staging   # staging
npm run db:migrate:prod && npm run deploy              # production
```

Before the first deploy, replace the placeholder `database_id` values in
`wrangler.toml` with the real UUIDs from `npx wrangler d1 list`.
