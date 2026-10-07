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

Migrations live in `backend/migrations/`:
- `0001_initial.sql`: Core schema (users, businesses, agents, leads, calls, campaigns, followups, callbacks, notifications, usage).
- `0002_seed.sql`: Development seed data.
- `0003_otp_and_security.sql`: `otp_codes`, `refresh_tokens`, `device_tokens`, and foreign key constraints.
- `0004_compliance_and_billing.sql`: Compliance flags (`do_not_call`, `consent`, `call_attempts`), indexes on `calls(interaction_id)`, `followups(business_id, status)`, and `usage.minutes_used` triggers.

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
| `DATA_ENCRYPTION_KEY` | AES-256 key for metadata encryption | Recommended (32-byte hex/base64 string) |
| `MSG91_AUTH_KEY` | MSG91 SMS gateway auth key | Required for production SMS |
| `GUPSHUP_API_KEY` | Gupshup SMS gateway API key | Alternative SMS provider |
| `EXOTEL_SID` / `EXOTEL_TOKEN` | Exotel SMS credentials | Alternative SMS provider |
| `FCM_SERVICE_ACCOUNT` | Firebase service account JSON | Required for live FCM data pushes |

---

## Deployment

```bash
# Staging Deployment (migrations run first)
npm run db:migrate:staging
npm run deploy:staging

# Production Deployment
npx wrangler d1 execute callpilot-db --remote --file=./migrations/0001_initial.sql
npx wrangler d1 execute callpilot-db --remote --file=./migrations/0003_otp_and_security.sql
npx wrangler d1 execute callpilot-db --remote --file=./migrations/0004_compliance_and_billing.sql
npm run deploy
```
