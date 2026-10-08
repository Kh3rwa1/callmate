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
   `SARVAM_WEBHOOK_SECRET`, `SARVAM_ORG_ID`, `SARVAM_WORKSPACE_ID`,
   `SARVAM_ADMISSIONS_APP_ID`, `FCM_SERVICE_ACCOUNT_JSON`, one SMS provider
   (`MSG91_AUTH_KEY` / `GUPSHUP_API_KEY` / `EXOTEL_SID`+`EXOTEL_TOKEN`) and
   `HEALTH_CHECK_SECRET`. Production refuses to send OTPs without an SMS
   provider.
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
1. Log into Sarvam AI Dashboard and generate a new API key.
2. Update production secret:
```bash
npx wrangler secret put SARVAM_API_KEY
```
3. Test connectivity immediately:
```bash
curl -X POST https://api.callpilot.app/voice/test-session \
  -H "Authorization: Bearer <ADMIN_TEST_TOKEN>"
```
4. Verify voice test session generates successfully, then revoke the old key in the Sarvam dashboard.

### 3.3 Rotating Sarvam Webhook Secret (`SARVAM_WEBHOOK_SECRET`)
1. Generate new webhook secret or retrieve from Sarvam dashboard.
2. Update Cloudflare secret:
```bash
npx wrangler secret put SARVAM_WEBHOOK_SECRET
```
3. Update the webhook configuration in the Sarvam AI portal to match the new secret.
4. Send a test webhook to `/webhooks/sarvam` and confirm HTTP 200 response.

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
curl -X POST https://api.callpilot.app/campaigns/<CAMPAIGN_ID>/stop \
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
