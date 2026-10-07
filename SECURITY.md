# CallPilot Security Policy

## 1. Overview & Threat Model Summary

CallPilot is a multi-tenant AI calling workforce platform serving commercial business tenants. Our defense-in-depth model addresses the following core threat surfaces:

```
┌─────────────────┐      ┌───────────────────────────────┐      ┌─────────────────────┐
│  Mobile Client  │ ───► │  Cloudflare Worker API Gateway │ ───► │ Telephony & AI Pods │
│ (No Raw Secrets)│      │    (Strict Scoping & Crypto)  │      │     (Sarvam AI)     │
└─────────────────┘      └───────────────────────────────┘      └─────────────────────┘
```

### 1.1 Multi-Tenant Data Isolation
- **Strict Query Scoping:** Every SQL `SELECT`, `INSERT`, `UPDATE`, and `DELETE` query across all domain routes (`business`, `agent`, `leads`, `calls`, `campaigns`, `followups`, `callbacks`, `knowledge`, `notifications`, `usage`) explicitly scopes data by `business_id = ?` derived directly from the verified JWT.
- **Object Storage Isolation:** In Cloudflare R2 (`KNOWLEDGE_BUCKET`), object storage keys are strictly partitioned with a tenant prefix (`${business_id}/${doc_id}`). Document deletion and retrieval verify business ownership before issuing R2 operations.
- **Tenant Spoofing Defense:** Webhooks from telephony providers never trust tenant or business identifiers inside the inbound payload. The backend resolves the call row by `interaction_id` against our database, deriving `business_id` and `lead_id` exclusively from internal trusted state.

### 1.2 Authentication & Token Hardening
- **Real OTP Verification:** OTPs are generated using `crypto.getRandomValues`, hashed via SHA-256 before storage in `otp_codes`, and expire after 5 minutes.
- **Lockout & Rate Limiting:** Exceeding 5 failed OTP attempts permanently locks the OTP. Requesting OTPs is rate-limited to 3 requests per 10 minutes per phone and per client IP.
- **HS256 JWT Enforcement:** The JWT validator enforces `alg === 'HS256'`, requires minimum 32-character keys, checks `iss` (`callpilot-backend`) and `aud` (`callpilot-client`), and enforces token claim types (`access` vs `session`).
- **Refresh Token Rotation & Family Revocation:** Refresh tokens rotate on every single use. If an already-rotated/revoked refresh token is presented, the system detects token theft and immediately revokes all tokens for that user family.

### 1.3 Sarvam AI Voice Proxy Hardening
- **Session Token Separation:** The `/voice/sarvam-proxy/*` endpoint strictly rejects access tokens and only accepts scoped JWTs with `type === 'session'`.
- **Strict Path Allow-List:** Only approved runtime paths required by the Sarvam SDK (`/orgs/:org/workspaces/:ws/apps/:app/stream`, `/transcribe`, `/text-to-speech`, etc.) are permitted. All arbitrary or administrative paths receive an immediate `403 Forbidden`.
- **Header Sanitization & Injection:** Client headers are never forwarded blindly. The gateway creates a sanitized header set and injects the high-privilege `X-API-Key` server-side.
- **Concurrency & Rate Controls:** Enforces per-tenant active session caps and rate limits to prevent resource exhaustion.

### 1.4 Webhook Hardening
- **Cryptographic Signature Verification:** Telephony webhooks require an HMAC-SHA256 signature calculated with `SARVAM_WEBHOOK_SECRET`. Missing signatures or secrets immediately return `401 Unauthorized` using constant-time comparison via `crypto.subtle.verify`.
- **Replay Protection:** Incoming webhooks are validated for replay freshness and deduplicated against `calls.interaction_id`.
- **Schema Validation & Fault Tolerance:** Inbound output variables are validated against `backend/schemas/call_output.schema.json`. Malformed payloads are assigned score 0, flagged for review, and acknowledged with `200 OK` to prevent retry storms and cascading failures.

### 1.5 Data Protection & PII Masking
- **Encryption at Rest:** Raw metadata and call transcripts are encrypted at rest using AES-256-GCM authenticated encryption.
- **PII Scrubbing in Logs:** Phone numbers are never logged in plain text and are systematically masked (e.g. `91XXXXXX345`). OTPs and full transcripts are strictly prohibited from logs.
- **Structured JSON Logging:** Server logs output structured JSON with unique `requestId` tracking for rapid auditability without leaking customer data.

---

## 2. Secret Management & Fail-Closed Guarantee

1. **No Hardcoded Defaults:** The codebase contains zero fallback secrets. If `JWT_SIGNING_KEY`, `SARVAM_API_KEY`, or `SARVAM_WEBHOOK_SECRET` are missing or invalid, the backend immediately fails closed and aborts execution.
2. **Environment Isolation:** Secrets are injected via Cloudflare Secrets (`wrangler secret put <KEY>`) in production/staging and `.dev.vars` during local development (which is excluded from Git via `.gitignore`).
3. **Automated Secret Scanning:** CI runs Gitleaks on every commit and pull request to detect accidental secret leakage.

---

## 3. Reporting a Vulnerability

If you discover a security vulnerability in CallPilot:
1. **Do not create a public GitHub issue.**
2. Send an email to the security team at: **security@callpilot.app** (or contact the repository owner directly).
3. Include:
   - Description of the vulnerability and attack vector.
   - Proof-of-concept steps or reproduction script.
   - Potential impact assessment.
4. **SLA:** We acknowledge vulnerability reports within **24 hours** and provide remediation patches within **72 hours** for high-severity findings.
