# CallPilot Production Operations Runbook

This runbook provides actionable procedures for deploying, managing, operating, and troubleshooting CallPilot in staging and production environments.

---

## 1. Deploying CallPilot

### 1.0 One-time setup (before the first deploy)
1. Create the D1 databases, R2 buckets and queues (including both DLQs) in
   Cloudflare, then replace the placeholder `database_id` values in
   `backend/wrangler.toml` with the real UUIDs from `npx wrangler d1 list`.
2. Set Worker secrets (`npx wrangler secret put <NAME> [--env staging]`):
   `JWT_SIGNING_KEY`, `OTP_PEPPER`, `ENCRYPTION_KEY`, `SARVAM_API_KEY`,
   `SARVAM_WEBHOOK_SECRET` (any random 32+ chars; Sarvam does not sign webhooks,
   so each dial's webhook URL carries `HMAC(secret, call_id)`), `FCM_SERVICE_ACCOUNT_JSON`, one SMS provider
   (`MSG91_AUTH_KEY` / `GUPSHUP_API_KEY` / `EXOTEL_SID`+`EXOTEL_TOKEN`) and
   `HEALTH_CHECK_SECRET`. Production refuses to send OTPs without an SMS
   provider.
   Billing (Razorpay): `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and
   `RAZORPAY_WEBHOOK_SECRET`. In the Razorpay dashboard (Settings → Webhooks)
   add `https://<api domain>/webhooks/razorpay` with the same secret and the
   event `payment_link.paid`. Without the keys, "Upgrade" in the app shows the
   "our team will contact you" message (checkout returns 503
   `billing_not_configured`). Optional plain vars: `TRIAL_MINUTES` (default 30)
   and `BILLING_RETURN_URL`.
   Growth (optional plain vars): `REFERRAL_BONUS_MINUTES` (default 200) and
   `DEMO_AUDIO_URL` (https URL of a demo call recording for the `/get` landing
   page; the player is hidden when unset).
   The Sarvam agent, org, workspace, connection and caller IDs are plain `[vars]`
   in `wrangler.toml`. After committing a new agent version in Sarvam, bump
   `SARVAM_APP_VERSION` and redeploy.
3. Add `PUBLIC_API_BASE_URL = "https://<your api domain>"` to `[vars]` (and
   `[env.staging.vars]`). Campaign retries started by the cron sweeper need it
   to give Sarvam a webhook URL.
4. **Existing databases only** (created before migrations were tracked): tell
   wrangler which files are already applied, or it will try to re-run them:
   ```bash
   npx wrangler d1 execute callpilot-db --remote --command="
     CREATE TABLE IF NOT EXISTS d1_migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP);
     INSERT OR IGNORE INTO d1_migrations (name) VALUES ('0001_initial.sql'), ('0003_otp_and_security.sql'), ('0004_compliance_and_billing.sql');"
   ```
   List only the files that were really applied, then `npm run db:migrate:prod`
   applies the rest.
5. GitHub: create `staging` and `production` environments (add required
   reviewers to `production`), the secrets `CLOUDFLARE_API_TOKEN` and
   `CLOUDFLARE_ACCOUNT_ID`, and the variable `PROD_HEALTH_URL`.

### 1.1 Staging Deployment
Automatic: `.github/workflows/deploy-staging.yml` runs after the **CI**
workflow succeeds on `main`. It applies pending migrations, then deploys the
exact commit CI tested. Manually:
```bash
cd backend
npm run db:migrate:staging
npm run deploy:staging
```

### 1.2 Production Deployment
Run **Deploy Production** (`.github/workflows/deploy-production.yml`) from the
Actions tab with the commit SHA. It refuses commits without a green CI run,
waits for `production` environment approval, applies pending migrations,
deploys and smoke-tests `PROD_HEALTH_URL`. Manual equivalent:
```bash
cd backend
npx wrangler d1 export callpilot-db --remote --output=./backup_$(date +%Y%m%d_%H%M%S).sql
npm run db:migrate:prod
npm run deploy
curl -f https://<your api domain>/health
```

### 1.3 Android Release (Play Store)
The **CI** workflow's `android-release` job builds a signed, obfuscated App
Bundle (`--build-number` = CI run number) and uploads it with its Dart symbols
when these repository secrets exist:

| Secret | Content |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | upload key credentials |
| `GOOGLE_SERVICES_JSON` | `google-services.json` for package `com.callpilot.app` |
| `PROD_ENV_JSON` | contents of `env/prod.json` with the real `API_BASE_URL` |

Without them, the job still builds a throwaway-signed bundle to prove the
release pipeline works, but uploads nothing. Upload the `.aab` to Play Console;
keep the `symbols/` folder to de-obfuscate Crashlytics stack traces
(`firebase crashlytics:symbols:upload --app=<APP_ID> symbols/`).

Local release builds need `android/key.properties`, `android/app/google-services.json`
and a real `env/prod.json`; the Gradle build fails closed if signing or
Firebase config is missing.

---

## 2. Rolling Back a Database Migration

Cloudflare D1 is SQLite at the edge. To roll back an accidental or failing migration:

### 2.1 Export Current Database Backup
Every **Deploy Production** run exports the database before migrating and keeps it
for 30 days as the workflow artifact `d1-backup-<run id>` (`backup-<sha>.sql`).
Always capture an immediate snapshot before any rollback operations:
```bash
npx wrangler d1 export callpilot-db --remote --output=./backup_$(date +%Y%m%d_%H%M%S).sql
```

### 2.2 Reversing Additive Schema Changes
1. Prepare a targeted down migration script (e.g. `migrations/down_0004.sql`):
```sql
-- Example: Reversing 0004 compliance indexes and columns safely
DROP INDEX IF EXISTS idx_calls_interaction_id;
DROP INDEX IF EXISTS idx_followups_biz_status;
DROP INDEX IF EXISTS idx_leads_biz_phone;
```
2. Execute down script:
```bash
npx wrangler d1 execute callpilot-db --remote --file=./migrations/down_0004.sql
```
3. If restoring from a previous full snapshot:
```bash
# In emergency only: restore previous snapshot
npx wrangler d1 execute callpilot-db --remote --file=./backup_previous_stable.sql
```

---

## 3. Secret Rotation Procedures

### 3.1 Rotating JWT Signing Key (`JWT_SIGNING_KEY`)
The JWT key signs user access tokens (24 h expiry) and voice session tokens (30 min expiry).
1. Generate a new cryptographically secure 32+ character key:
```bash
NEW_KEY=$(openssl rand -hex 32)
```
2. Update Cloudflare Secret:
```bash
echo "$NEW_KEY" | npx wrangler secret put JWT_SIGNING_KEY
```
3. **Impact & Recovery:** Existing access tokens will be rejected with 401 on their next request. The Flutter client's `ApiClient` automatically intercepts the 401 and uses the valid refresh token (stored as a SHA-256 hash in D1) to silently obtain a new access token signed with the new key. Users will not be logged out.

### 3.2 Rotating Sarvam AI API Key (`SARVAM_API_KEY`)
See also `docs/SARVAM_SETUP.md`. The API is served on workers.dev:
production `https://callpilot-backend.dulalkisku0.workers.dev`, staging
`https://callpilot-backend-staging.dulalkisku0.workers.dev`.

1. In the Sarvam dashboard (**Settings → API Key**) create a new key. Keep the old one for now.
2. Update the secret in both environments:
```bash
npx wrangler secret put SARVAM_API_KEY                 # production
npx wrangler secret put SARVAM_API_KEY --env staging   # staging
```
3. Confirm it works: on staging, open the app → Agent → talk to your AI employee (or
   `POST /voice/test-session` with an owner's access token), then place one test call to
   **your own number** and check it rings and the result arrives.
```bash
curl -X POST https://callpilot-backend-staging.dulalkisku0.workers.dev/voice/test-session \
  -H "Authorization: Bearer <OWNER_ACCESS_TOKEN>"
```
4. Repeat the check on production, then revoke the old key in the Sarvam dashboard.

### 3.3 Rotating Sarvam Webhook Secret (`SARVAM_WEBHOOK_SECRET`)
Sarvam does **not** sign webhooks and this secret is **not** entered in Sarvam.
Each dial puts a per-call token in its webhook URL:
`{PUBLIC_API_BASE_URL}/webhooks/sarvam?call_id=…&token=HMAC-SHA256(SARVAM_WEBHOOK_SECRET, call_id)`,
and `/webhooks/sarvam` recomputes it. Rotating the secret therefore invalidates the
tokens of calls still in progress: their results are rejected (401) and the
maintenance sweeper later marks those calls failed.

1. Pick a quiet moment: pause running campaigns and check nothing is in progress:
```bash
npx wrangler d1 execute callpilot-db --remote --command="
  SELECT COUNT(*) FROM calls WHERE status = 'calling';
"
```
2. Generate and set a new secret (32+ chars):
```bash
openssl rand -hex 32
npx wrangler secret put SARVAM_WEBHOOK_SECRET                 # production
npx wrangler secret put SARVAM_WEBHOOK_SECRET --env staging   # staging (use a different value)
```
3. Nothing to change in the Sarvam portal: the next dial carries a token made with the new secret.
4. Place one test call to your own number and confirm the call completes in the app
   (`npx wrangler tail` shows the `/webhooks/sarvam` request with status 200). Resume campaigns.

---

## 4. Handling Stuck Campaigns

If a campaign becomes unresponsive, hangs, or experiences queue processing stalls:

### 4.1 Diagnose the Active Campaign
Run query against D1 to check status and progress:
```bash
npx wrangler d1 execute callpilot-db --remote --command="
  SELECT id, business_id, purpose, status, total_leads, completed_calls, created_at 
  FROM campaigns 
  WHERE status = 'running';
"
```

### 4.2 Inspect Stuck Leads
Check how many leads remain in queued state:
```bash
npx wrangler d1 execute callpilot-db --remote --command="
  SELECT status, count(*) 
  FROM campaign_leads 
  WHERE campaign_id = '<CAMPAIGN_ID>' 
  GROUP BY status;
"
```

### 4.3 Force Stop the Campaign
Halting the campaign transitions `campaigns.status` to `stopped`, causing the queue consumer to immediately acknowledge and drop remaining tasks:
```bash
curl -X POST https://callpilot-backend.dulalkisku0.workers.dev/campaigns/<CAMPAIGN_ID>/stop \
  -H "Authorization: Bearer <TOKEN>"
```
Alternatively, update database directly:
```bash
npx wrangler d1 execute callpilot-db --remote --command="
  UPDATE campaigns SET status = 'stopped' WHERE id = '<CAMPAIGN_ID>';
"
```

### 4.4 Dead-Letter Queue (DLQ)
Jobs that exhaust their retries land in `callpilot-campaign-dlq`. The Worker
consumes the DLQ itself: each lead still waiting is marked `failed` and the
campaign is completed once nothing is outstanding, so campaigns no longer stay
"running" forever. Waiting for a free call slot (5 concurrent calls per
business) re-sends a delayed message and does **not** use up retries.
1. Check Cloudflare Dashboard → Queues → `callpilot-campaign-dlq` for volume.
2. Inspect logs for `[Sarvam Queue Outbound Error]`.
3. After a Sarvam outage, start a new campaign for the failed leads.

---

## 5. Monitoring, Health Checks & Log Analysis

- **API Health Endpoint:** `GET /health` → returns `{"status": "ok"}`
- **Live Worker Logs:**
  ```bash
  npx wrangler tail
  ```
- **Error Filtering:** All errors emit structured JSON with request IDs:
  ```bash
  npx wrangler tail --format=json | jq 'select(.level=="error")'
  ```
- **Phone Privacy:** Phone numbers appear only in masked format (`91XXXXXX345`) in compliance with PII privacy rules.

### 5.0 Daily summary push

The same 10-minute cron runs `runDailyDigests` (`backend/src/services/digest.ts`).
Between 19:00 and 22:00 Asia/Kolkata it sends each business one push
("Today: 12 calls, 3 ready to buy — tap to see them"), deduped per local date
in `digest_log`. Skipped when the owner turned it off
(`businesses.digest_enabled = 0`), when no device is registered, and on days
with no enquiries and no calls. Owner test calls never count.

### 5.1 Alerts & monitoring

The 10-minute cron (`scheduled` in `backend/src/index.ts`) runs
`runAlertChecks` (`backend/src/services/alerts.ts`). It looks at the **last
hour** and raises at most **one alert per type per hour** (deduped in the D1
table `alert_state`). Nothing is sent while everything is healthy.

| Alert type | Fires when (last hour) | Source |
|---|---|---|
| `sarvam_dial_failures` | ≥ 3 calls `status='failed'` with `failure_reason LIKE 'sarvam_%'` | `calls` |
| `stuck_calls` | ≥ 3 calls still `calling` after 45 min, or swept to `timed_out` | `calls` |
| `queue_dead_letters` | ≥ 1 campaign job reached the dead-letter queue | `ops_events` (written by the DLQ consumer) |
| `webhook_auth_failures` | ≥ 10 `/webhooks/sarvam` requests rejected with 401 | `ops_events` (written by the webhook route) |

Thresholds live in `ALERT_THRESHOLDS` in `alerts.ts`.

Every alert goes to:
1. **Logs, always:** a `console.error` JSON line with `"msg":"ops_alert"`,
   `type`, `count`, `env` and `text`.
2. **Chat, if configured:** a POST to `ALERT_WEBHOOK_URL`. It is sent as
   `{"text": …}`, which Slack and Google Chat incoming webhooks accept
   (`{"content": …}` for Discord URLs). Set it as a secret:
   ```bash
   cd backend
   env -u CLOUDFLARE_API_TOKEN npx wrangler secret put ALERT_WEBHOOK_URL --env staging
   env -u CLOUDFLARE_API_TOKEN npx wrangler secret put ALERT_WEBHOOK_URL          # production
   ```

**Tail logs:**
```bash
cd backend
env -u CLOUDFLARE_API_TOKEN npx wrangler tail --env staging
env -u CLOUDFLARE_API_TOKEN npx wrangler tail --env staging --format=json | jq 'select(.logs[]?.message[]? | tostring | contains("ops_alert"))'
```

**Deep health check:** `GET /health/deep` with header `x-health-key: $HEALTH_CHECK_SECRET`
returns D1/R2 reachability, `sarvam_config`, a `sarvam` map of which dial
settings are set (true/false, never the values) and the `agent_variables`
names each dial sends.

**What to do per alert**

- `sarvam_dial_failures` — read the reasons; `failure_reason` holds Sarvam's
  HTTP status and error body:
  ```bash
  npx wrangler d1 execute callpilot-db-staging --env staging --remote --command="
    SELECT id, started_at, failure_reason FROM calls
    WHERE status='failed' AND failure_reason LIKE 'sarvam_%' ORDER BY started_at DESC LIMIT 20;"
  ```
  - `sarvam_http_422: … Agent variables … not found` → the backend sent a
    variable the agent version doesn't declare. Remove it from
    `SARVAM_AGENT_VARIABLES` (or declare it in the agent and bump
    `SARVAM_APP_VERSION`); see `docs/SARVAM_SETUP.md` → Agent variables.
  - `sarvam_http_422/404` otherwise → agent version not committed or caller
    ID not onboarded on the connection.
  - `sarvam_http_401/403` → API key wrong or revoked (§3.2).
  - `sarvam_http_429/5xx`, `sarvam_network` → Sarvam outage/rate limit; campaign
    dials retry on their own. Check Sarvam status.
  - `sarvam_not_configured` → a `[vars]` value or `SARVAM_API_KEY` is missing
    (`/health/deep` shows which).
- `stuck_calls` — Sarvam isn't reaching `/webhooks/sarvam`. Check
  `PUBLIC_API_BASE_URL`, the Sarvam webhook delivery log, and look for
  `webhook_auth_failures` at the same time (a rotated `SARVAM_WEBHOOK_SECRET`
  invalidates tokens of calls already in flight).
- `queue_dead_letters` — see §4.4. The `ops_events.detail` column has the
  job's `campaign:lead` key; correlate with `sarvam_dial_failures`.
- `webhook_auth_failures` — after a secret rotation a burst is expected for
  in-flight calls. A sustained stream from unknown sources is probing; no
  action needed beyond watching, since bad tokens are rejected.
---

## 6. Billing, Plans & Trials

- **Plans** (`backend/src/services/plans.ts`): `trial` (`TRIAL_MINUTES`, default
  30, no expiry date) and `starter` (₹4999 / month, 1000 minutes).
- **Trial abuse guard:** every signup records HMAC(`OTP_PEPPER`) hashes of its
  phone and email in `trial_grants`. A phone/email seen before (including after
  account deletion) gets a 0-minute trial.
- **Payment:** the app calls `POST /billing/checkout` → Razorpay Payment Link →
  `payment_link.paid` webhook → plan `active`, `minutes_used = 0`,
  `current_period_end` +1 month. Each Razorpay payment id is applied once.
- **Renewal:** the 10-minute cron marks `active` plans whose
  `current_period_end` has passed as `past_due`; calls and campaigns then return
  `402 plan_inactive` until the owner pays again (the same checkout renews).
- **Accounts that existed before migration 0010** are `starter`/`active` with
  their current minutes and `current_period_end = NULL`, so they never expire
  via the cron; their first payment starts a normal monthly period.
- **Manual adjustments** (e.g. paid by bank transfer):
  ```bash
  npx wrangler d1 execute callpilot-db --remote --command="
    UPDATE usage SET plan_id='starter', plan_name='Starter', plan_status='active',
      included_minutes=1000, minutes_used=0, price_inr=4999,
      current_period_end=datetime('now','+1 month') WHERE business_id='biz_xxx';"
  ```
- **Account deletion** keeps `payments` and `usage_ledger` rows for invoices/GST,
  with PII nulled and `business_id` replaced by a stable `anon_…` pseudonym.

## 7. Referrals & landing page

- **Referral codes** live in `businesses.referral_code` (created on the first
  `GET /referrals`). New signups may send `referral_code`; it is recorded in
  `referrals` (status `signed_up`).
- **Reward:** on the referred business's first applied Razorpay payment, both
  businesses get `REFERRAL_BONUS_MINUTES` (default 200) added to
  `usage.included_minutes`, once (`referrals.status = 'rewarded'`, one
  `referral_credits` row per business). Change the amount with a plain var:
  `REFERRAL_BONUS_MINUTES = "300"` in `[vars]` / `[env.staging.vars]`, redeploy.
  Bonus minutes count toward the current period; a renewal resets
  `included_minutes` to the plan amount.
- **Abuse guards:** own code, the referrer's phone/email, and a phone that was
  ever referred before are ignored (rows survive account deletion with
  `anon_…` ids). Rewards need a verified payment.
- **Check a referral:**
  ```bash
  npx wrangler d1 execute callpilot-db --remote --command="
    SELECT r.code, r.status, r.created_at, r.rewarded_at FROM referrals r
    WHERE r.referrer_business_id='biz_xxx';"
  ```
- **Landing page:** `https://<api domain>/get` (`?ref=CODE` carries the code to
  the Play install referrer). Set `DEMO_AUDIO_URL` to an https recording (the
  page's CSP allows only that origin for media). Use a recording made with
  consent and without customer personal data.
