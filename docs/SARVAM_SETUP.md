# Sarvam Voice Agent Setup

How CallPilot places real AI phone calls through Sarvam, and where every piece
of configuration lives. Secrets are **never** committed; this file only says
where they go.

## How a call flows

```
App (tap "Call" / start campaign)
  → Worker POST /leads/:id/call  or  campaign queue
  → Sarvam POST /api/outbounds/v1/orgs/{org}/workspaces/{ws}/outbounds
      app_config: agent id + version, connection + caller ID, agent_variables
      user_config: lead phone (E.164)
      webhook_config: {PUBLIC_API_BASE_URL}/webhooks/sarvam?call_id=…&token=HMAC(secret, call_id)
  → Sarvam rings the lead from one of our Vobiz numbers, the agent talks
  → Sarvam POSTs the result to /webhooks/sarvam
  → Worker verifies the token, scores the lead, creates the WhatsApp follow-up
```

Sarvam does **not** sign webhooks, so the per-call token in the URL is what
authenticates them. Code: `backend/src/services/campaign_queue.ts`
(`dialSarvam`, `sarvamWebhookConfig`) and `backend/src/routes/voice.ts`
(`handleSarvamWebhook`).

API reference: [create outbound call](https://docs.sarvam.ai/conversations/api/instant-outbound/create),
[webhook payload](https://docs.sarvam.ai/conversations/api/instant-outbound/webhook-payload).

## Where each setting lives

### 1. Sarvam dashboard (https://apps.sarvam.ai)

| What | Current value | Where in the dashboard |
|---|---|---|
| Org ID | `019fae1b-3a58-7997-a365-1ba8adec01b3` | dashboard URL / Settings |
| Workspace ID | `019fae1b-3a5c-7830-94dc-9660d32abbf6` | dashboard URL / Settings |
| Agent | **CallPilot - Outbound Lead Qualifier** (`CallPilot---cb13b1d8-b8da`) | Agents |
| Agent version in use | `2` | Agents → the agent → versions |
| Telephony connection | Vobiz, `0da745db-ed-2dd19091-839b` | Telephony → Connections |
| Caller IDs | `+917971442975`, `+917971443028` | Telephony → the connection → numbers |
| API key | *(secret)* | **Settings → API Key** |

### 2. `backend/wrangler.toml` — plain `[vars]` (committed, not secret)

Set for both production (`[vars]`) and staging (`[env.staging.vars]`):

```toml
SARVAM_ORG_ID = "…"
SARVAM_WORKSPACE_ID = "…"
SARVAM_ADMISSIONS_APP_ID = "CallPilot---cb13b1d8-b8da"   # the agent
SARVAM_APP_VERSION = "2"                                  # committed agent version
SARVAM_CONNECTION_ID = "0da745db-ed-2dd19091-839b"
SARVAM_AGENT_PHONE_NUMBERS = "+917971442975,+917971443028" # one picked per call
PUBLIC_API_BASE_URL = "https://callpilot-backend.dulalkisku0.workers.dev"
```

Caller IDs must be spelled exactly as Sarvam stores them (with `+`).
Changing any of these = edit the file and redeploy (`npm run deploy` /
`npm run deploy:staging` in `backend/`).

### 3. Cloudflare Worker secrets (never committed)

| Secret | What it is |
|---|---|
| `SARVAM_API_KEY` | from Sarvam **Settings → API Key**. Without it, real calls fail with `sarvam_not_configured`. |
| `SARVAM_WEBHOOK_SECRET` | any random 32+ char string (`openssl rand -hex 32`). Signs the per-call webhook token; not entered in Sarvam. |

Set or rotate one:

```bash
cd backend
npx wrangler secret put SARVAM_API_KEY                 # production
npx wrangler secret put SARVAM_API_KEY --env staging   # staging
```

> If wrangler says "You are logged in with an API Token", prefix commands with
> `env -u CLOUDFLARE_API_TOKEN` or run `npx wrangler login`.

Do **not** also create secrets named `SARVAM_ORG_ID` etc.; they are `[vars]`
and a secret with the same name clashes.

## Common changes

**Edit what the agent says** — change the prompt in the Sarvam dashboard,
**commit a new version**, then bump `SARVAM_APP_VERSION` in `wrangler.toml`
and redeploy. Calls keep using the old version until you bump it.

**Add or remove a caller number** — onboard it on the connection in Sarvam
Telephony, then edit `SARVAM_AGENT_PHONE_NUMBERS` and redeploy.

**Rotate the API key** — create a new key in Sarvam, `wrangler secret put
SARVAM_API_KEY` (both envs), confirm a test call, revoke the old key.

## Agent variables

> **Sarvam rejects the whole dial** (HTTP 422 `Agent variables … not found in
> agent variables of app`) if the backend sends a variable the agent version
> does not declare. That is why every variable beyond the default set is
> **opt-in** through the Worker var `SARVAM_AGENT_VARIABLES`.

**In (sent per call).** Built in `backend/src/services/call_variables.ts`
(`buildCallAgentVariables`) for both manual calls and campaigns, then filtered
to `SARVAM_AGENT_VARIABLES` (comma separated). Unset = the default 8 below.
Unknown names are ignored with a `unknown_agent_variables_ignored` warning.
`GET /health/deep` lists the names currently sent.

Default (declared in the agent today; keep them):

| Variable | Meaning |
|---|---|
| `call_id` | our call id (also in the webhook URL) |
| `campaign_id` | campaign id; empty string for a manual call |
| `lead_id`, `lead_name` | the lead |
| `business_name` | business display name |
| `agent_name`, `agent_role` | the AI employee's name and role |
| `interest` | what the lead asked about (may be empty) |

Optional (only sent once listed in `SARVAM_AGENT_VARIABLES`):

| Variable | Meaning / example |
|---|---|
| `business_context` | plain-text summary (≤ 1500 chars) of the business profile — name, category, offerings, pricing, hours, location, goal — the vertical playbook's qualifying questions and "ready to buy" definition (`backend/src/services/playbooks.ts`, picked from the business category), plus the top knowledge-base snippets (matched to the lead's interest; cut first when over the limit). Use it in the prompt as `{{business_context}}` so the agent can answer questions about the business. |
| `call_language` | the employee's first language as the owner named it, e.g. `Hindi`, `English` |
| `gender`, `voice` | `female` / `male`, from the employee's voice |
| `speaker` | Bulbul v4 speaker id, e.g. `ishita_enhi_customer`, `shubh_hi_customer` |
| `language_code` | `en-IN`, `hi-IN` or `bn-IN` |
| `tts_model` | `bulbul:v4-flash` |

**To turn on an optional variable** (in this order, or real calls break):

1. Sarvam dashboard → Agents → **CallPilot - Outbound Lead Qualifier** →
   add the variable(s) under the agent's variables with exactly the names
   above (and use them in the prompt, e.g. `{{business_context}}`).
2. **Commit a new version** of the agent and note its number.
3. Set `SARVAM_APP_VERSION` to that number in `backend/wrangler.toml`
   (`[vars]` and/or `[env.staging.vars]`).
4. In the same block, set `SARVAM_AGENT_VARIABLES` to the default 8 **plus**
   the new names, e.g.
   `SARVAM_AGENT_VARIABLES = "call_id,campaign_id,lead_id,lead_name,business_name,agent_name,agent_role,interest,business_context,call_language"`.
5. Deploy staging, place one test call to your own number, check
   `calls.failure_reason` is empty, then do the same for production.

To roll back, remove the names from `SARVAM_AGENT_VARIABLES` (or unset it) and
redeploy; the older agent version keeps working.

**Out (filled after the call, read by the webhook):** `lead_score` (0–100),
`intent`, `temperature`, `summary`, `next_action`,
`whatsapp_followup_required`, `whatsapp_message`, `callback_at`.
Allowed values: `backend/schemas/call_output.schema.json`.

## Disclosure override

Every call should open by saying it is an AI assistant, for which business,
and that it may be recorded (`COMPLIANCE.md`). With the Worker var
`SARVAM_DISCLOSURE_OVERRIDE = "true"` the backend sends, on every dial,

```json
"app_overrides": {
  "initial_bot_message": "Hello Asha, this is Arjun, an AI assistant calling from Bright Future about your enquiry. This call may be recorded for quality. Is this a good time to talk?",
  "initial_language_name": "English"
}
```

in the employee's first language (English / Hindi / Bengali; text in
`backend/src/services/disclosure.ts`). Names are cleaned and cut to 40
characters; only the lead's first name is spoken. Unset (default) = no
`app_overrides` key at all.

**To turn it on:** set `SARVAM_DISCLOSURE_OVERRIDE = "true"` in
`[env.staging.vars]`, deploy staging, call your own number and check the
greeting, that the agent carries on naturally after it, and that
`calls.failure_reason` is empty. Then do the same in `[vars]` for production.
`GET /health/deep` shows `compliance.disclosure_override`. To roll back, remove
the line and redeploy.

## Checking it works

```bash
curl https://callpilot-backend.dulalkisku0.workers.dev/health   # {"status":"ok"}
npx wrangler tail --format=json | jq 'select(.level=="error")'   # live errors
```

| Symptom | Cause |
|---|---|
| `sarvam_not_configured` | API key, a `[vars]` value or the caller IDs missing |
| `sarvam_http_401/403` | wrong or revoked `SARVAM_API_KEY` |
| `sarvam_http_422: … app_overrides …` | the agent version rejects the disclosure override: unset `SARVAM_DISCLOSURE_OVERRIDE` |
| `sarvam_http_422: … Agent variables … not found` | `SARVAM_AGENT_VARIABLES` lists a name the agent version doesn't declare (see Agent variables) |
| `sarvam_http_404/422` | agent version not committed, or caller ID not onboarded on the connection |
| Call rings but lead stays "calling" | webhook not reaching the Worker: check `PUBLIC_API_BASE_URL` and the Sarvam webhook delivery log |
| Call `flagged_for_review`, score 0 | the agent's output variables don't match the schema above |
