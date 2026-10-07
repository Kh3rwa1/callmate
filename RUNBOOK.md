# CallPilot Production Operations Runbook

This runbook provides actionable procedures for deploying, managing, operating, and troubleshooting CallPilot in staging and production environments.

---

## 1. Deploying CallPilot

### 1.1 Staging Deployment
Automated via `.github/workflows/deploy-staging.yml` on push to `main`, or manually via:
```bash
cd backend

# 1. Apply D1 migrations to staging database first
npx wrangler d1 execute callpilot-db-staging --env staging --file=./migrations/0001_initial.sql --remote
npx wrangler d1 execute callpilot-db-staging --env staging --file=./migrations/0003_otp_and_security.sql --remote
npx wrangler d1 execute callpilot-db-staging --env staging --file=./migrations/0004_compliance_and_billing.sql --remote

# 2. Deploy Worker to staging
npm run deploy:staging
```

### 1.2 Production Deployment
```bash
cd backend

# 1. Pre-flight verification
npm run typecheck
npm run test:coverage
npm audit --audit-level=high --omit=dev

# 2. Apply remote D1 migrations (idempotent / additive)
npx wrangler d1 execute callpilot-db --remote --file=./migrations/0001_initial.sql
npx wrangler d1 execute callpilot-db --remote --file=./migrations/0003_otp_and_security.sql
npx wrangler d1 execute callpilot-db --remote --file=./migrations/0004_compliance_and_billing.sql

# 3. Deploy Worker
npm run deploy

# 4. Post-deploy health check
curl -f https://api.callpilot.app/health
```

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
The JWT key signs user access tokens (1 hr expiry) and voice session tokens (30 min expiry).
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

### 4.4 Inspect & Drain the Dead-Letter Queue (DLQ)
Messages that failed 3 consecutive delivery attempts are routed to `callpilot-campaign-dlq`:
1. Check Cloudflare Queue metrics in Cloudflare Dashboard → Queues → `callpilot-campaign-dlq`.
2. Inspect log errors filtered by `[Sarvam Queue Outbound Error]`.
3. If failures were due to transient Sarvam outages or rate limits, re-trigger campaign start once connectivity is restored.

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
