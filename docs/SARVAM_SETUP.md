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

**Owners never touch Sarvam.** In the app a paying owner picks a free
number, or taps **Request my number** when none is free. Numbers can only be
bought in the Sarvam dashboard, so the operator keeps the pool stocked. A
bought number needs **no code change, deploy or app update**:

1. **Buy** — Sarvam dashboard → **Deploy → Phone Numbers** → the **Sarvam
   Vobiz** connection (the one in `SARVAM_CONNECTION_ID`) → **Buy Number**.
   ₹59 per number per 30 days. A number on that connection makes and receives
   calls; nothing separate to set up for inbound or outbound.
2. **Add it on the ops page.** Open `<PUBLIC_API_BASE_URL>/ops/numbers`,
   type the ops key and the number, tap **Add number**. The backend can't
   find bought numbers by itself: Sarvam has no API that lists a
   connection's numbers, and the dashboard's route
   (`…/connections/<id>/endpoints`) refuses API keys. Sarvam support
   confirmed both on 2026-10-21 and logged a feature request.
3. **That's it.** A business waiting for a number gets it at once (the
   ops page says how many did; otherwise the next cron run) with a
   notification; otherwise it shows in the picker. No agent setup per number:
   when a business takes it, a free agent from the **receptionist pool**
   (below) is claimed for it and its deployment is created with that agent.
   The ops page and the ops alert `receptionist_agents_low` say when the pool
   needs more agents.

While anyone is waiting, the ops alert `business_numbers_requested` repeats
every 12 hours. A number belongs to one inbound deployment, so to one
environment: never list it in both `SARVAM_BUSINESS_NUMBERS` and
`SARVAM_AGENT_PHONE_NUMBERS`, nor in two environments.

**Staging and production share the connection.** A number meant for staging
goes on staging's ops page only; never add one number on both pages.

**The ops page** (`backend/src/routes/ops.ts`) is off (404) until
`OPS_KEY_SHA256` is set for that environment in `wrangler.toml`. Make a key
and its hash, keep the key in a password manager, commit only the hash:

```bash
KEY=$(openssl rand -hex 24); echo "$KEY"
printf %s "$KEY" | shasum -a 256      # → OPS_KEY_SHA256
```

Each action posts the key (10 wrong keys per IP per hour, then 429). With
the key it lists every pool number with its status (free, active, held),
source (`ops`, `config`) and whether an agent answers it, never which
business has it, plus how many receptionist agents are free and how many
businesses are waiting. **Add number** takes an Indian number (+91 and 10
digits) that isn't a shared caller ID or in `SARVAM_BUSINESS_NUMBERS`;
adding it twice changes nothing. **Remove number** takes out a free `ops`
number (do it before you release the number in Sarvam).

**TRAI 140/160 series.** Business numbers are caller IDs, so they are part of
the DLT check (`/health/deep` → `compliance.caller_ids_dlt_series`, and the
production warning `caller_ids_not_dlt_series`; COMPLIANCE.md). A number
outside the series still joins the pool today, as our Vobiz `+9179…` numbers
do: the ops page says so and the log shows `business_number_not_dlt_series`.
With `REQUIRE_DLT_CALLER_IDS = "true"` the ops page refuses such a number.

**A number rented again** never gets its previous business's calls: an
after-call webhook or an analytics record of a call that started before the
current business got the number (`business_numbers.assigned_at`) is
acknowledged and not recorded (`inbound_call_before_assignment`).

**Older option: one agent per number.** `SARVAM_BUSINESS_NUMBERS` entries
`+91…=<agent id>:<version>` still work (staging's `+917971443028` uses it):
clone the receptionist, set its `load_business` hook URL to the output of
`INBOUND_HOOK_SECRET=… node backend/scripts/hook_url.mjs <PUBLIC_API_BASE_URL> +91…`
(the URL names the number), commit a version, add the entry and deploy.

### Receptionist pool

Sarvam's on-start hook can't see which number was dialled, and Sarvam's API
can't create or copy agents. So we keep a stock of identical receptionist
agents whose hook URL names the **agent** (`?agent=<its id>&token=<its
token>`). When a business takes an `ops` number, a free pool agent
is claimed onto that number's row (`business_numbers.agent_app_id`; a unique
index means one agent never answers two numbers) and the deployment routes
the number to it. The hook finds the number, and so the business, by the
agent. The agent stays with the number while it is held and becomes free
again when the number goes back to the pool (hold over, or account deleted
and the deployment removed by the next cron run). If no agent is free, those
numbers aren't offered in the picker and the ops alert
`receptionist_agents_low` fires (once a day while one or none is free).

To make pool agents (a few at a time, e.g. 5–10; Claude Code can do this
through the Sarvam MCP):

1. Clone the current receptionist (e.g. `CallPilot-R-2944da04-d549` on
   staging), one copy per agent.
2. Run `node backend/scripts/hook_url.mjs <PUBLIC_API_BASE_URL> --agent <its agent id> <version it will commit>`.
   It makes a random token and prints the hook URL and the config entry.
3. In the copy, set the `load_business` on-start webhook tool URL to
   `<PUBLIC_API_BASE_URL>/voice/inbound/start?agent=<its agent id>&token=<the token>`
   (no other auth), and commit that version.
4. Add the printed `<agent id>:<version>:<sha256 of the token>` to
   `SARVAM_RECEPTIONIST_AGENTS` for that environment (comma separated) and
   deploy once for the whole batch. Only the hash is in the repo; the token
   lives in the agent's hook URL.

An agent belongs to one environment (its hook URL names that Worker) and is
never also a `SARVAM_BUSINESS_NUMBERS` agent. A changed agent version in
`SARVAM_RECEPTIONIST_AGENTS` applies to numbers rented after the deploy;
numbers already rented keep the version their deployment was made with. Never
take an agent off the list while a number holds it (its hook would be
refused): check that
`SELECT phone FROM business_numbers WHERE agent_app_id = '<agent id>'` returns
nothing.

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

**If the after-call webhook doesn't come.** Sarvam's inbound deliveries can
stall (on staging one stayed "running" indefinitely). Every 10 minutes the cron
also reads the last two hours of inbound conversations of each active business
number's agent (its pool agent or its own agent) from Sarvam's analytics API (`syncInboundCalls`,
`routes/answering.ts`) and records any call the webhook missed through the
same handler, so the owner still gets the lead, summary and notification.

**The receptionist agent** (staging: `CallPilot-R-2944da04-d549`, cloned from
the outbound agent so it keeps the voice, languages and result variables):

- Input variables, filled by the `load_business` on-start hook from
  `POST /voice/inbound/start`: `business_name`, `agent_name`, `agent_role`,
  `business_context`, `call_language`, `caller_name`, `caller_known`,
  `can_talk`, `greeting`, `answer_mode`. Opening line: `{{greeting}}`, which
  always says it is an AI assistant and that the call may be recorded; its
  default value says the same if the hook fails.
- Prompt: answer as `{{agent_name}}` for `{{business_name}}` from
  `{{business_context}}`; find out what the caller wants, their name and a
  good time for a call back; with `{{can_talk}}` = `no` take a short message
  only; an opt-out is confirmed and ends the call.
- Output variables: the outbound set (`lead_score`, `intent`, `temperature`,
  `summary`, `next_action`, `whatsapp_followup_required`, `whatsapp_message`,
  `callback_at`) plus `caller_name`.
- The hook authenticates with the token in its URL; Sarvam only attaches
  stored secrets to allow-listed URLs. A pool agent's token is checked against
  its SHA-256 in `SARVAM_RECEPTIONIST_AGENTS`; a pool agent that holds no
  number gets a neutral greeting that still says it is an AI. An older
  per-number agent's token is the HMAC of the number with the Worker secret
  `INBOUND_HOOK_SECRET`. Sarvam's hook can't send the caller's number, so
  returning customers aren't greeted by name; the after-call webhook still
  carries it and the lead is matched then.

**Worker config** (`wrangler.toml`, per environment): `SARVAM_RECEPTIONIST_AGENTS`
and `OPS_KEY_SHA256` (above). For the older per-number agents:
`npx wrangler secret put INBOUND_HOOK_SECRET [--env staging]` (any 32+ random
characters, used to sign their hook URLs) and the `SARVAM_BUSINESS_NUMBERS`
entries. The deployment's after-call webhook is signed with
`SARVAM_WEBHOOK_SECRET`, which already exists.

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
