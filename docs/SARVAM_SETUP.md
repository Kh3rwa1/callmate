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
SARVAM_AGENT_PHONE_NUMBERS = "+917971442975,+917971443028" # shared: one picked per call
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
  "initial_bot_message": "Hello Asha, I'm calling from Bright Future about your enquiry. This is Arjun, an AI assistant. This call may be recorded for quality. Is this a good time to talk?",
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

## Business numbers (every paid plan): one number for calls out and in

**Your part is two steps:** buy numbers in Sarvam, paste them into one list.
The backend does the rest.

1. Sarvam dashboard → **Deploy → Phone Numbers** → the **Sarvam Vobiz**
   connection (the one in `SARVAM_CONNECTION_ID`) → number catalog → **Buy**.
   ₹59 per number per 30 days. Numbers on that connection make and receive
   calls; there is nothing separate to set up for inbound or outbound.
2. Add them to `SARVAM_BUSINESS_NUMBERS` in `wrangler.toml` and deploy.

**What the business gets** (`backend/src/services/business_numbers.ts`).
Every business on a **paid plan** (Starter or Growth, monthly or yearly) picks
**one number of its own**, once, in **Agent → Your business number**. The
free trial can't; trial calls go out from the shared
`SARVAM_AGENT_PHONE_NUMBERS`, one picked per call. The number never rotates,
and it does both jobs at once:

- **Calls out:** it is the caller ID of every AI call the business makes
  (manual calls and campaigns), so customers always see the same number.
- **Calls in:** when the owner picks it, the backend creates its Sarvam
  inbound deployment, so a customer who calls it reaches the business's AI.

If the plan lapses, the cron **holds** the number for 30 days (deployment
paused, calls go out from the shared pool). Paying again within those days
brings it straight back. After that, or when the account is deleted, the
deployment is deleted and the number goes back to the pool.

Optional, for owners who also want the AI to answer their **own** phone:
**Your business number → Calls to your own phone** (*the AI answers every
call*, *I answer first, the AI takes the ones I miss*, or *only me*). The
phone does the forwarding with the codes the app shows for the owner's
network (`lib/core/utils/call_forwarding.dart`):

| | Jio | Airtel, Vi, BSNL (standard) |
|---|---|---|
| Every call | `*401*<10 digits>#` | `**21*<+91…>#` |
| Missed only | `##002#`, then `*403*`, `*405*`, `*409*` `<10 digits>#` | `##002#`, then `**004*<+91…>#` |
| Only me | `##002#` | `##002#` |

The greeting follows the choice: with every call forwarded it doesn't say
"the team can't come to the phone".

```
caller → business number (called back, or forwarded from the owner's phone)
  → Sarvam on-start hook POST {PUBLIC_API_BASE_URL}/voice/inbound/start
      → business name, AI employee, business_context, greeting, can_talk
  → the receptionist agent talks
  → deployment webhook POST /webhooks/sarvam-inbound?number=…&token=HMAC
      → lead (consent "inquiry", enquiry dated now) + inbound call row
      → same scoring / WhatsApp draft / billing / opt-out as outbound
      → owner notification "Your AI answered <name>"
```

Answered minutes count against the owner's plan; out of minutes or unpaid,
the agent still answers with the disclosure and takes a message
(`can_talk = no`). A held number's deployment is paused, so the app tells the
owner to cancel forwarding (`##002#`); after the hold, the number can go to
another business.

**One-time setup of the AI that answers (Sarvam dashboard, then Worker config):**

1. **Create the agent** "CallPilot - Inbound Receptionist":
   - Input variables: `business_name`, `agent_name`, `agent_role`,
     `business_context`, `call_language`, `caller_name`, `caller_known`,
     `can_talk`, `greeting`. Opening line: `{{greeting}}` (it says it's an AI
     assistant and that the call may be recorded).
   - Prompt: answer as `{{agent_name}}` for `{{business_name}}` using
     `{{business_context}}`; find out what the caller wants, their name, and
     a good time for a call back. If `{{can_talk}}` is `no`, take a short
     message and end the call. If they ask not to be called, apologise, say
     they won't be called, set `intent = "opt_out"` and end the call.
   - Output variables: the outbound set (`lead_score`, `intent`,
     `temperature`, `summary`, `next_action`, `whatsapp_followup_required`,
     `whatsapp_message`, `callback_at`) plus `caller_name`.
   - **On-start hook**: an API tool with *When should this tool run?* =
     `on_start`, `POST {PUBLIC_API_BASE_URL}/voice/inbound/start`, auth
     *bearer token* = the `INBOUND_HOOK_SECRET` value (stored as a Sarvam
     secret), JSON body `{"caller": @User Identifier, "called": <the number
     dialled>, "interaction_id": @Interaction ID}`, and *Save reply into
     variables* for every input variable above.
   - **Verify on the first staging call** that `called` is filled. Sarvam's
     docs list the caller's number for hooks but not the dialled one; without
     it the agent still answers, discloses it's an AI and takes a message, and
     the lead, summary and notification still reach the right business (the
     after-call webhook carries the dialled number), but it can't greet with
     the business name or answer questions from its details.
   - Commit a version.
2. **Worker config** (`wrangler.toml` `[vars]` / `[env.staging.vars]`):
   `SARVAM_INBOUND_APP_ID`, `SARVAM_INBOUND_APP_VERSION`,
   `SARVAM_BUSINESS_NUMBERS = "+91…,+91…"`; secret
   `npx wrangler secret put INBOUND_HOOK_SECRET` (any 32+ random characters,
   the same value as the Sarvam secret). Deploy. Until all are set the app
   says business numbers aren't available yet.

**Adding numbers later**: rent them on the same connection, append them to
`SARVAM_BUSINESS_NUMBERS` and redeploy; the picker shows them from the next
request. Never remove a number that a business has rented (check
`SELECT phone, business_id, status FROM business_numbers`).

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
