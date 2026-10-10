# CallPilot architecture

A one-page map of the system for new engineers and reviewers. The source of
truth is the code; file paths are given so every claim can be checked.
Related: [`AGENTS.md`](../AGENTS.md) (rules + checks), [`API.md`](../API.md)
(HTTP contract), [`RUNBOOK.md`](../RUNBOOK.md) (deploy/ops),
[`docs/decisions/`](decisions/) (ADRs).

## System overview

```
 ┌──────────────────────────┐        HTTPS + JWT        ┌─────────────────────────────────────────────┐
 │ Flutter app (Android)    │ ────────────────────────▶ │ Cloudflare Worker (Hono)  backend/src/index.ts│
 │ lib/  Riverpod + Dio     │ ◀──────────────────────── │  /auth  /legal  /webhooks/*  protected API   │
 │ secure token storage     │                           └───┬──────────┬───────────┬──────────┬────────┘
 └────────▲────────┬────────┘                               │          │           │          │
          │        │ wa.me deep link                        ▼          ▼           ▼          ▼
          │        ▼ (owner taps; never auto-sent)      ┌──────┐  ┌────────┐  ┌──────────┐ ┌──────────┐
          │   ┌──────────┐                              │  D1  │  │   R2   │  │  Queues  │ │Workers AI│
          │   │ WhatsApp │                              │SQLite│  │knowledge│ │ campaign │ │ (chat)   │
          │   └──────────┘                              └──────┘  │ files  │  │ dispatch │ └──────────┘
          │                                                       └────────┘  │  + DLQ   │
          │ FCM push (HTTP v1)                                                └────┬─────┘
          │                                                                        │ queue consumer
          │                                                                        ▼ dials lead
 ┌────────┴─────────┐    score + follow-up    ┌──────────────────────┐  outbound  ┌───────────────┐
 │ Firebase Cloud   │ ◀────────────────────── │ POST /webhooks/sarvam│ ◀───────── │ Sarvam voice  │
 │ Messaging        │                          │ verify → score →     │  webhook   │ agent (PSTN)  │
 └──────────────────┘                          │ encrypt → persist    │            └───────────────┘
                                               └──────────────────────┘
 Cron (*/10 min): maintenance sweeps, billing renewals, ops alert checks.
```

| Piece | Where | Notes |
|---|---|---|
| App | `lib/` | `features/<feature>/` screens + Riverpod controllers; `core/network/api_client.dart` (Dio: auth header, single-flight token refresh, one retry for idempotent GETs); `useMockProvider` swaps in the offline mock backend (`lib/data/datasources/mock/`). |
| API | `backend/src/index.ts`, `routes/*.ts` | Hono. Public: `/auth`, `/legal`, `/webhooks/sarvam`, `/webhooks/razorpay`, `/voice/sarvam-proxy/*` (own session token), `/health`. Everything else is behind `authMiddleware`. |
| Validation | `backend/src/schemas/validation.ts` | zod schemas for every request body. |
| Database | D1 `DB`, `backend/migrations/` | Applied by `wrangler d1 migrations apply` in CI and on deploy. |
| Files | R2 `KNOWLEDGE_BUCKET` | Uploaded knowledge documents; text is chunked into `knowledge_chunks`. |
| Async dialing | Queue `callpilot-campaign-dispatch` (+ DLQ `callpilot-campaign-dlq`) | `services/campaign_queue.ts`; see [ADR 0001](decisions/0001-campaign-state-machine.md). |
| Voice | Sarvam outbound API | `dialSarvam` in `services/campaign_queue.ts`; per-call agent variables from `services/call_variables.ts`. |
| Push | FCM HTTP v1 | `services/fcm.ts` (service-account OAuth, per-business throttling, dead-token cleanup). |
| Billing | Razorpay payment links + webhook | `routes/billing.ts`, `services/plans.ts`, `services/billing.ts`. |
| Scheduled | `scheduled()` in `index.ts` | `runMaintenance`, `runBillingRenewals`, `runAlertChecks` every 10 min. |

## Lifecycle of a call

1. **Trigger.** Owner taps *Call* on a lead (`POST /leads/:id/call`,
   `routes/calls.ts`) or starts a campaign (`POST /campaigns/:id/start`,
   `routes/campaigns.ts`). Campaigns are capped at 500 leads and skip
   leads whose consent is unknown unless the owner attested.
2. **Dispatch.** Single calls dial Sarvam inline. Campaigns enqueue one
   message per lead on `CAMPAIGN_QUEUE`; the consumer (`queue()` in
   `index.ts` → `handleCampaignQueueBatch`) applies calling-hours,
   do-not-call and concurrency rules, then dials. Retryable failures are
   re-queued with a delay; exhausted messages land in the DLQ and are
   recorded as `ops_events`.
3. **Dial.** `dialSarvam` posts to Sarvam's outbound API with the agent
   variables and a webhook URL of the form
   `/webhooks/sarvam?call_id=<id>&token=HMAC(SARVAM_WEBHOOK_SECRET, call_id)`.
   A `calls` row is created in state `calling`.
4. **Webhook.** Sarvam calls `POST /webhooks/sarvam` when the call ends
   (`handleSarvamWebhook`, `routes/voice.ts`): authenticate (below) →
   claim the event in `webhook_events` (idempotent; duplicates return 200)
   → validate payload (invalid ⇒ score 0, cold, flagged for review).
5. **Score + persist.** The lead score, temperature, intent, summary and
   objections come from the agent's output variables. Transcript and raw
   payload are encrypted at rest, the `calls`, `leads`, `campaign_leads`
   and campaign metrics rows are updated, usage is metered in
   `usage_ledger`, and a WhatsApp follow-up draft is written to `followups`.
6. **Notify.** Hot leads and new follow-ups create `notifications` rows and
   an FCM push (throttled via `push_rate_limits`) that deep-links into the app.
7. **Follow up.** The owner reviews the draft and taps send, which opens a
   `wa.me` deep link (`lib/services/whatsapp/whatsapp_service.dart`).
   Nothing is ever sent automatically.

## Data model (D1)

| Table | Purpose | Migration |
|---|---|---|
| `users` | Account (phone, optional email / `firebase_uid` for Google sign-in) | 0001, 0008 |
| `businesses` | Tenant; every business-owned row carries `business_id` | 0001 |
| `agents` | The AI employee's persona/config per business | 0001 |
| `leads` | Contacts to call; score, temperature, `consent`, `do_not_call`, timezone | 0001, 0004 |
| `calls` | One row per dial; status, encrypted transcript/`raw_metadata`, failure reason | 0001, 0004, 0005 |
| `campaigns`, `campaign_leads` | Batch calling runs and per-lead state (attempts, errors, `call_id`, attestation) | 0001, 0004, 0005, 0007 |
| `followups` | Drafted WhatsApp messages awaiting owner review | 0001 |
| `callbacks` | Scheduled call-backs requested by leads | 0001 |
| `notifications`, `devices` | In-app notifications; FCM tokens per device | 0001 |
| `knowledge_sources`, `knowledge_chunks` | Uploaded docs/URLs (blobs in R2) and their text chunks | 0001, 0006 |
| `chat_messages` | Owner ↔ agent test chat history | 0006 |
| `usage`, `usage_ledger` | Plan, period and minute balance; idempotent per-call usage entries | 0001, 0005, 0010 |
| `payments`, `trial_grants` | Razorpay payments; HMAC'd identity keys preventing repeat free trials | 0010 |
| `refresh_tokens` (legacy), `refresh_tokens_v2` | Hashed refresh tokens with `family_id` + revocation | 0001, 0003 |
| `otp_codes` | Peppered OTP hashes | 0003 |
| `voice_sessions` | Short-lived sessions for the in-app voice test proxy | 0003 |
| `webhook_events` | Webhook idempotency claims | 0005 |
| `rate_limits`, `otp_rate_limits`, `push_rate_limits`, `voice_proxy_rate_limits` | Sliding-window counters (pruned daily by maintenance) | 0003, 0004, 0005 |
| `ops_events`, `alert_state` | Operational signals (webhook auth failures, DLQ) and alert de-duplication | 0009 |

Migration `0002` does not exist (numbering skipped historically); do not
reuse it.

## Security model

- **Authentication.** HS256 JWTs signed with `JWT_SIGNING_KEY`
  (`backend/src/auth.ts`; header `alg` pinned, `type` checked). Access
  tokens live 24 h, refresh tokens 30 days. Sign-in is phone OTP (codes
  stored as `HMAC(OTP_PEPPER, phone:code)`) or Google via Firebase ID token.
- **Refresh-token families.** Each login starts a family in
  `refresh_tokens_v2` (only SHA hashes stored). `POST /auth/refresh` is
  single-use: it conditionally revokes the presented token and issues a new
  one in the same family. Presenting an already-revoked token (or losing a
  concurrent refresh race) is treated as theft and revokes **all** of the
  user's refresh tokens. The app serialises refreshes (`_refreshFlight` in
  `api_client.dart`) and keeps tokens in secure storage
  (`lib/core/storage/secure_store.dart`).
- **Tenant isolation.** Every protected query is scoped by the JWT's
  `business_id`.
- **Encryption at rest.** Call transcripts and raw webhook payloads are
  encrypted with AES-256-GCM (key = SHA-256 of `ENCRYPTION_KEY`, random
  96-bit IV, stored as `enc:v1:<iv>:<ciphertext>`) in
  `backend/src/utils/crypto_data.ts`. Phones are masked in logs (`maskPhone`).
- **Webhooks.** Sarvam does not sign requests, so each dial gets a per-call
  URL token `HMAC-SHA256(SARVAM_WEBHOOK_SECRET, call_id)`, compared in
  constant time (`utils/compare.ts`). A signed body (`X-Sarvam-Signature`,
  with a 5-minute timestamp window) is also accepted. Failures are recorded
  as `ops_events` and alerted on. Razorpay webhooks are verified with
  `X-Razorpay-Signature`.
- **Rate limits.** Atomic sliding windows in D1 (`utils/rate_limit.ts`,
  single INSERT…SELECT so concurrent requests cannot both pass): OTP
  request per phone and per IP, OTP verify per IP, agent chat (20/min per
  user, 300/day per business), knowledge ingest per business per hour,
  checkout (10/h per business), voice proxy per business, push per business.
- **Secrets** are Worker secrets (never in `wrangler.toml`);
  `requireSecret` enforces a 32-char minimum. CI runs gitleaks.
- **Compliance.** Consent + attestation gates, do-not-call, and calling-hour
  clamps (see [`COMPLIANCE.md`](../COMPLIANCE.md)).

## How to…

### Add a D1 migration
1. Create `backend/migrations/NNNN_short_name.sql` with the next unused
   number (currently after `0010`). Never edit a migration that has shipped.
2. Prefer additive changes (`CREATE TABLE IF NOT EXISTS`, `ALTER TABLE …
   ADD COLUMN` with a default); D1 has no transactional DDL rollback.
3. Apply locally: `cd backend && rm -rf .wrangler/state && npx wrangler d1
   migrations apply callpilot-db --local`. CI applies all migrations to a
   fresh DB; staging/prod deploys apply pending ones before `wrangler deploy`.
4. Update the data-model table above and add a test.

### Add an API route
1. Add the handler to the relevant `backend/src/routes/*.ts` app (or a new
   Hono app mounted in `index.ts` — under `protectedApp` unless it must be
   public).
2. Validate the body with a zod schema in `schemas/validation.ts`. Optional
   fields: the app omits `null`s, or use `.nullable().optional()`.
3. Scope every query by `user.business_id`; rate-limit anything costly.
4. Add vitest coverage in `backend/test/` (coverage gate in
   `vitest.config.ts`), and update `API.md` **and** `backend/API.md`.
5. Wire the client in `lib/data/datasources/api/api_repositories.dart` and
   the mock in `lib/data/datasources/mock/`.

### Add a screen
1. Create `lib/features/<feature>/` (screen widget + Riverpod controller);
   register providers in `lib/core/providers.dart`.
2. Add a `GoRoute` in `lib/core/routing/app_router.dart`.
3. All user-visible strings go in `lib/l10n/s_<area>.dart` via
   `pick(en, hi, bn)` — English, Hindi and Bengali are all required.
4. Writes must refresh screens: go through `ApiClient` (which fires
   `onMutation`) or call `api.onMutation` yourself.
5. Add a widget test in `test/` against the mock backend.
