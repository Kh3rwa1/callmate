# CallPilot – Backend API Contract (v1)

> **Product:** CallPilot (`com.echoing.heights`).  
> **Backend Architecture:** Cloudflare Workers (Hono) + Cloudflare D1 (SQLite) + Cloudflare R2 + Cloudflare Queues + Sarvam AI Voice Agents.

The mobile app communicates **only** with this backend. The backend manages authentication, telephony orchestration via Sarvam AI, webhook validation, tenant data isolation, encryption at rest, and FCM push notifications.

```
Flutter App ──(JWT)──► CallPilot Backend ──(X-API-Key)──► Sarvam Voice Agents ──► Telephony ──► Lead
                            ▲                                          │
                            └───────── completed-call webhook ─────────┘
```

---

## 1. Authentication & Session Management

All auth endpoints run under `/auth`. Real OTP verification is enforced; default bypasses are prohibited.

| Method | Path | Request Body | Response (200 / 201) | Description |
|---|---|---|---|---|
| `POST` | `/auth/otp/request` | `{"phone": "+919830012345"}` | `{"success": true, "message": "OTP sent successfully"}` | Sends 6-digit OTP via SMS (MSG91/Gupshup/Exotel or Mock in non-prod). Rate limited to 3 reqs per 10 min per phone and per IP. |
| `POST` | `/auth/login` | `{"phone": "+919830012345", "otp": "123456"}` | `{"access_token": "...", "refresh_token": "...", "token_type": "bearer", "expires_in": 3600, "business": {...}, "agent": {...}}` | Verifies SHA-256 OTP hash. Max 5 failed attempts before lock. Issues HS256 JWT (1 hr) & Refresh Token (30 days). |
| `POST` | `/auth/register` | `{"phone": "+919830012345", "otp": "123456", "business_name": "ABC Coaching", "referral_code"?: "ABC234"}` | `{"access_token": "...", "refresh_token": "...", "token_type": "bearer", "expires_in": 3600, "business": {...}, "agent": {...}}` | Requires verified OTP. Returns 400 if phone already registered. |
| `POST` | `/auth/google` | `{"id_token": "<Firebase ID token>", "business_name"?: "...", "phone"?: "...", "referral_code"?: "ABC234"}` | `{"access_token": "...", "refresh_token": "..."}` | Google sign-in. A new account needs `business_name` + `phone` (else `404 registration_required`). |
| `POST` | `/auth/refresh` | `{"refresh_token": "..."}` | `{"access_token": "...", "refresh_token": "...", "token_type": "bearer", "expires_in": 3600}` | Rotates refresh token on each use. If an old/revoked token is presented, revokes all tokens for that user family. |
| `POST` | `/auth/logout` | `{"refresh_token": "..."}` | `{"success": true}` | Revokes the refresh token and clears active session. |
| `DELETE` | `/auth/account` | *(Bearer token required)* | `{"success": true}` | Soft-deletes user account and associated business data. |

### JWT Specification:
- **Algorithm:** `HS256` (enforced, rejects `none` or other algorithms).
- **Signing Key:** `JWT_SIGNING_KEY` (minimum 32 characters, fails closed if missing or short).
- **Claims:** `sub` (user ID), `business_id`, `type` (`access` or `session`), `iss` (`callpilot-backend`), `aud` (`callpilot-client`), `exp`, `iat`.

---

## 2. Business & AI Employee Profile

All requests require `Authorization: Bearer <access_token>` and are scoped strictly to `user.business_id`.

| Method | Path | Request Body | Response |
|---|---|---|---|
| `GET` | `/business` | - | `Business` object |
| `PATCH` | `/business` | `{"name"?, "category"?, "address"?, "offerings"?, "pricing"?, "opening_hours"?, "location"?, "whatsapp_number"?, "human_number"?, "owner_name"?}` | Updated `Business` object |
| `GET` | `/agent` | - | `Agent` object (name, role, role_kind, skills, voice, goal, languages, formality, calling_hours_start, calling_hours_end, transfer_number, status, template_id) |
| `PATCH` | `/agent` | Partial `Agent` updates | Updated `Agent` object |

---

## 3. Knowledge Base

Tenant-isolated documents stored in Cloudflare R2 and indexed into Sarvam AI.

| Method | Path | Request Body | Response |
|---|---|---|---|
| `POST` | `/knowledge` | Multipart or JSON `{"title": "...", "type": "text"|"faq"|"url"|"file", "content"?: "..."}` | `KnowledgeSource` (`status`: `processing` or `ready`). R2 object keys are prefixed with `${business_id}/`. |
| `GET` | `/knowledge` | - | `{"items": [KnowledgeSource, ...]}` |
| `GET` | `/knowledge/:id` | - | `KnowledgeSource` |
| `DELETE` | `/knowledge/:id` | - | `{"success": true}` (scoped to `business_id`) |

---

## 4. Leads Management

| Method | Path | Request Body | Response |
|---|---|---|---|
| `GET` | `/leads?filter=all|new|called|hot|warm|callback&search=&cursor=&limit=20` | - | `{"items": [...], "has_more": bool, "next_cursor": "..."}` (Keyset pagination on `created_at:id`, max limit 100). |
| `POST` | `/leads` | `{"name": "...", "phone": "...", "course_interest"?: "...", "source"?: "..."}` | Created `Lead` |
| `POST` | `/leads/import` | `{"leads": [{"name": "...", "phone": "..."}, ...]}` | `{"imported": number, "skipped": number, "errors": [...]}`. Max 1000 per batch. Unique constraint on `(business_id, phone)` prevents duplicates. |
| `GET` | `/leads/:id` | - | `Lead` object |
| `PATCH` | `/leads/:id` | Partial `Lead` updates (`name`, `status`, `interest`, `do_not_call`, `consent`, etc.) | Updated `Lead` |
| `GET` | `/leads/:id/consent-history` | - | `{"items": [{"id", "consent_value", "source", "text_version", "created_at"}]}` newest first (max 100). `source` is `form` / `webhook` / `import_attestation` / `manual` / `in_call_opt_out`. `404` if the lead is not in your business. |
| `POST` | `/leads/:id/call` | - | Initiates outbound call to lead via Sarvam, with the same guardrails as campaigns: agent calling hours, DNC/opt-out (per business and the platform-wide `/stop` list), max 3 calls per lead per day, at most 3 different businesses per phone number per 24h, concurrent-call cap and remaining minutes. Errors: `409` `outside_hours` / `do_not_call` / `max_daily_attempts` / `platform_frequency_cap`, `429` `concurrency_limit`, `402` `exhausted_minutes`, `502`/`503` `dial_failed` (503 = retryable). Returns `{ call, sarvam_dispatched }`. |

---

## 5. Calls & AI Analysis

| Method | Path | Response |
|---|---|---|
| `GET` | `/calls?filter=all|connected|noAnswer|hot&lead_id=&cursor=&limit=20` | Paginated `Call` items. Scoped by `business_id`. |
| `GET` | `/calls/:id` | Full `Call` detail. `transcript` and `recording_url` are stored encrypted (AES-256-GCM) and decrypted on retrieval (legacy plaintext rows are returned as-is). After `RETENTION_DAYS` (default 180) `transcript`, `recording_url` and `summary` are cleared (null / empty). |

---

## 6. Campaigns & Cloudflare Queues Dispatch

| Method | Path | Request Body | Response |
|---|---|---|---|
| `POST` | `/campaigns` | `{"purpose": "...", "lead_ids": ["...", ...]}` | Created `Campaign` (draft status). Validates that every `lead_id` belongs to `user.business_id`. |
| `GET` | `/campaigns/:id` | - | `Campaign` detail with lead progress summary. |
| `GET` | `/campaigns?status=running` | - | Active campaigns for business. |
| `POST` | `/campaigns/:id/start` | - | Enqueues leads into Cloudflare Queue (`CAMPAIGN_QUEUE`) with idempotency keys. Validates available minutes quota before starting. |
| `POST` | `/campaigns/:id/stop` | - | Sets campaign status to `stopped` and halts queue dequeuing. |

---

## 7. Follow-ups & Callbacks

| Method | Path | Request Body | Response |
|---|---|---|---|
| `GET` | `/followups?status=ready&call_id=` | - | `{"items": [FollowUp, ...]}` |
| `GET` | `/followups/:id` | - | `FollowUp` object |
| `PATCH` | `/followups/:id` | `{"message"?: "...", "status"?: "opened"|"done"|"dismissed"}` | Updated `FollowUp`. `status=opened` signifies WhatsApp deep link was launched by the user. **Nothing is ever sent automatically on WhatsApp.** |
| `GET` | `/callbacks` | - | `{"items": [Callback, ...]}` |
| `POST` | `/callbacks` | `{"lead_id": "...", "scheduled_at": "...", "note"?: "..."}` | Created `Callback` |
| `PATCH` | `/callbacks/:id` | `{"status": "done"|"cancelled"}` | Updated `Callback` |

---

## 8. Voice Test & Proxy (`SamvaadAgent`)

| Method | Path | Headers | Description |
|---|---|---|---|
| `POST` | `/voice/test-session` | `Bearer <access_token>` | Issues a scoped JWT (`type: "session"`, 30 min expiry), Sarvam app credentials, and runtime parameters. |
| `ANY` | `/voice/sarvam-proxy/*` | `Bearer <session_token>` | Reverse proxy to Sarvam App Runtime (`https://apps.sarvam.ai/api/app-runtime/*`). Enforces strict path allow-list, scrubs client headers, injects `X-API-Key`, and applies concurrency and rate caps per business. |

---

## 9. Webhook (`POST /webhooks/sarvam`)

Receives post-call telemetry from Sarvam telephony.

1. **Signature Verification:** Computes HMAC-SHA256 using `SARVAM_WEBHOOK_SECRET` with constant-time equality check (`crypto.subtle.verify`). Missing signature or secret returns `401`.
2. **Replay Protection & Idempotency:** Deduplicates requests via unique `interaction_id` / `call_id`. Replayed webhooks return `200` without duplicate processing.
3. **Tenant Resolution:** Derives `business_id` and `lead_id` strictly from our database row associated with `interaction_id`. Never trusts tenant claims from the webhook payload.
4. **Structured Output Validation:** Validates output variables against `backend/schemas/call_output.schema.json`. If schema validation fails, assigns score 0, temperature `cold`, flags for manual review, and returns `200` to prevent retry storms.
5. **WhatsApp draft:** after a connected call, the agent's `whatsapp_message` becomes a `ready` follow-up. If the agent sent none but `whatsapp_followup_required` is true, the draft is the business's playbook template for the outcome (`hot` / `warm` / `callback` / `not_interested`) in the call's `language` (else the employee's first language), with the lead's first name and the business name filled in. No default draft for an opt-out. Drafts are never sent automatically.
6. **Data Protection:** Encrypts `raw_metadata` and transcripts at rest using AES-256-GCM. Never logs transcripts or plain phone numbers.
7. **Billing & FCM Push:** Bills each call once (idempotent ledger): connected calls of **10 s or more** pay `ceil(seconds / 60)` minutes (every started minute); connected calls under 10 s and `no_answer` / `busy` / `failed` / `voicemail` / invalid-number outcomes bill **0** minutes. Every call also records our cost (`calls.billed_minutes`, `calls.cost_inr`, `usage_ledger.cost_inr`) at `COST_PER_MIN_SARVAM_INR + COST_PER_MIN_TELEPHONY_INR` per started minute of the real duration. Dispatches FCM data messages for hot leads, campaign completion, and callback reminders (rate limited to 1 per 10 min for follow-ups).
8. **Waste control:** campaign leads are re-dialled only after `busy` / `no_answer`, at most 3 dials in total (1 + 2 retries), each retry ≥ 3 h later. An invalid / unreachable number (status `invalid_number` / `not_reachable` / `unreachable`, or a `failure_reason` such as "Invalid phone number" / "not in service") sets `leads.phone_invalid = 1`; campaigns then mark the lead `skipped_invalid` until the owner edits its phone (`phone_invalid` is returned on leads).

---

## 10. Dashboard, Usage & Notifications

| Method | Path | Response |
|---|---|---|
| `GET` | `/dashboard/today` | `DailySummary`: leads count, connected calls, hot leads, follow-ups ready, callbacks scheduled, recent activity feed. |
| `GET` | `/usage` | `Usage`: `subscription` (`plan_name`, `plan_id` `trial`/`starter`/`growth`, `plan_status` `trial`/`active`/`past_due`/`cancelled`, `current_period_end` UTC or null, `billing_cycle` `monthly`/`annual`, `annual_until`, `included_minutes` (plan grant this period), `topup_minutes`, `bonus_minutes`, price), `minutes_used`, `minutes_remaining` (= plan + top-up + bonus − used), calls made, `checkout_plan`, `plans`, `topups`, `can_buy_topup`, `gst_rate`. |
| `GET` | `/billing` | `{plan_id, plan_name, plan_status, billing_cycle, current_period_end, annual_until, price_inr, included_minutes, topup_minutes, bonus_minutes, minutes_used, minutes_left, gst_rate, checkout_plan, plans, topups, can_buy_topup}`. Catalogue items: `{plan_id, kind: plan/annual/topup, name, price_inr (before GST), gst_inr, total_inr, included_minutes, months}`. |
| `POST` | `/billing/checkout` | Body `{"plan_id": "<catalogue id>"}` (optional/null = `starter`). Ids: `starter` (₹4,999 / 1,000 min a month), `growth` (₹11,999 / 3,000 min), `starter_annual` / `growth_annual` (10 × monthly price, 12 monthly grants), `topup_250` (₹1,499 → +250 min), `topup_1000` (₹5,499 → +1,000 min). Prices exclude GST; the payment link charges `total_inr` = round(price × (1 + `GST_RATE`)). Returns `{url, id, plan_id, base_inr, gst_inr, total_inr}`. `400 invalid_plan` for unknown ids; `409 plan_not_active` for a top-up without an active plan; `503 billing_not_configured` when Razorpay keys are not set; `502 billing_unavailable` if Razorpay fails. |
| `POST` | `/webhooks/razorpay` | Public. Razorpay `payment_link.paid` webhook, verified with `X-Razorpay-Signature` = hex HMAC-SHA256(raw body, `RAZORPAY_WEBHOOK_SECRET`). Idempotent per Razorpay payment id. The amount must cover the base + GST stored in the link notes (links from before GST: the base price). Monthly plan: activates it, resets `minutes_used`, extends `current_period_end` by a month. Annual: same for month 1 and sets `annual_until` +12 months; the 10-minute cron re-grants the plan's minutes each month until then without a payment. Top-up: adds `topup_minutes` (active plans only; otherwise recorded as `needs_review`). Payments store `kind`, `base_paise`, `gst_paise`. |
| `GET` | `/admin/economics?days=30` | Ops only: header `x-health-key: <HEALTH_CHECK_SECRET>` (or `Authorization: Bearer …`), like `/health/deep`. `days` 1–366. Returns `{days, revenue_basis: "cash_ex_gst", cost_per_min_inr, total, by_plan[], by_product[]}`; `total`/`by_plan` lines have `revenue_inr` (ex-GST), `minutes_billed`, `cost_inr`, `gross_margin_inr`, `gross_margin_pct`, `wasted_minutes` (minutes we paid for but did not bill), `wasted_cost_inr`, `calls`; `total` adds `gst_collected_inr`, `payments`. |
| `GET` | `/referrals` | `{code, link, bonus_minutes, signed_up, rewarded, minutes_earned}`. `code` is the business's referral code (6 chars from `23456789ABCDEFGHJKMNPQRSTUVWXYZ`, created on first call); `link` is `<PUBLIC_API_BASE_URL>/get?ref=<code>`. |
| `GET` | `/playbooks/current?lang=en\|hi\|bn` | The business's call playbook, chosen from `businesses.category` (`coaching`→`education`, `clinic`/`diagnostic`→`healthcare`, `real_estate`, `salon`/`spa`→`salon`, `gym`/`fitness`→`fitness`, anything else→`general`; `backend/src/services/playbooks.ts`). Language: `lang`, else the employee's first language, else English. `{id, category, language, name, business_name, qualifying_questions: string[3-5], ready_to_buy: {description, temperature: "hot", intents: ["interested"], min_score}, objections: [{objection, hint}], followup_templates: {hot, warm, callback, not_interested}, callback_timing: {hint, start_hour, end_hour}}`. Templates keep the `{name}` and `{business}` placeholders. Read-only. |
| `GET` | `/notifications` | List of in-app notifications. |
| `PATCH` | `/notifications/:id` | `{"read": true}` |
| `POST` | `/notifications/device` | `{"token": "...", "platform": "android"}` registers FCM push token for business. |

### Referral program

- `referral_code` (optional; omit or `null`) on `POST /auth/register` and new-account `POST /auth/google`. Case, spaces and dashes are ignored. An unknown/malformed code, self-referral (the referrer's own phone or email) or a phone that was already referred once (even before an account deletion) is silently ignored: signup never fails because of a code.
- Reward: when the referred business's first Razorpay payment is applied (`payment_link.paid`), both businesses get `REFERRAL_BONUS_MINUTES` (default 200) added to `included_minutes`, once, with a `referral_credits` ledger row each. Webhook redeliveries and later payments don't credit again.
- Bonus minutes are added to the current period's `included_minutes`; a later renewal resets `included_minutes` to the plan amount.

---

## 10b. Public opt-out page (`/stop`)

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/stop?lang=en\|hi\|bn` | - | HTML form (no scripts, strict CSP) in English, Hindi or Bengali: `lang`, else `Accept-Language`, else English; small language links on the page. The form posts back to `/stop?lang=<same>`. |
| `POST` | `/stop` | form field `phone` (`application/x-www-form-urlencoded`) | HTML. `200` number added to the platform-wide do-not-call list (`global_dnc`, HMAC only), `400` invalid number, `429` more than 10 submissions per IP per hour, `503` hashing key not configured. |

Campaign dispatch additionally allows one call per business per number per 24h; a lead that hits it (or the cross-business cap) is `rescheduled`.
## 10b. Speed-to-lead: lead capture & instant AI call

Every new enquiry from a business's hosted form or webhook becomes a lead (`consent: "explicit_opt_in"`, `source: "form"` / `"webhook"`) and, with `auto_call` on, gets an AI call within about a minute. The call goes through a queue message (`kind: "instant_call"` on the campaign dispatch queue) and the **same guards and dial as `POST /leads/:id/call`** (`backend/src/services/dial.ts`): calling hours clamped to TRAI 09:00–21:00 in the lead's timezone, do-not-call/opt-out, max 3 calls per lead per day, concurrency cap, plan status and minutes headroom. Outside calling hours the call is delayed until the window opens (re-queued in hops of at most 12 h). The owner gets a `new_lead` notification + push ("New enquiry from Ravi" / "Your AI employee is calling them now.", or why it was not called).

Dedupe: one lead per phone per business. The same phone again within 24 h of its last enquiry (or creation) changes nothing and is not called again. After 24 h it is a new enquiry: the lead's interest and consent are refreshed (an opt-out or do-not-call is never overridden) and it is called again.

**Owner APIs** (Bearer access token, scoped to the caller's business):

| Method | Path | Request Body | Response |
|---|---|---|---|
| `GET` | `/lead-sources` | - | `{"items": [LeadSource]}` (active only). `LeadSource` = `{id, kind: "form"\|"webhook"\|"google_ads"\|"indiamart"\|"meta", slug, url, auto_call, leads_count, created_at, last_error, last_synced_at?}` (integrations: see below) |
| `POST` | `/lead-sources` | `{"kind": "form"\|"webhook"\|"google_ads"\|"indiamart"\|"meta", "auto_call"?: bool, …integration secrets}` | Form: the business's active form (`200`) or a new one (`201`). Webhook: `201` `LeadSource` **plus `token`, shown only once** (only its SHA-256 is stored). Max 5 active webhooks (`409 too_many_sources`). |
| `PATCH` | `/lead-sources/:id` | `{"auto_call": bool}` | Updated `LeadSource`. Turning it off also cancels instant calls still waiting for calling hours. |
| `POST` | `/lead-sources/:id/revoke` | - | `{"success": true}`. The form link then 404s and the webhook token 401s. |

**Public endpoints** (no owner auth):

| Method | Path | Notes |
|---|---|---|
| `GET` | `/f/:slug` | Mobile-first enquiry form branded with the business name: name, mobile (`+91` prefilled), interest (optional) and a required consent box *"I agree to receive a call from &lt;business&gt; about my enquiry (may be an automated AI call)."* No scripts, strict CSP. In English, Hindi or Bengali (`?lang=en\|hi\|bn`, else the employee's first language, else `Accept-Language`, else English) with language links; `<html lang>` and `Content-Language` are set. The form posts to `/f/:slug?lang=<same>`. |
| `POST` | `/f/:slug` | `application/x-www-form-urlencoded`: `name`, `phone`, `interest?`, `consent=yes`. Thank-you page (also for duplicates and honeypot hits), in the page language. The consent event's `text_version` names the wording shown: `enquiry-form-2026-10` (English), `enquiry-form-2026-10-hi`, `enquiry-form-2026-10-bn`. `400` re-renders the form with the error (localized); `429` after 5 submissions / 10 min per IP per form (300 / h per form). |
| `POST` | `/hooks/leads/:slug` | `Authorization: Bearer <token>`, JSON `{"name", "phone", "interest"?, "consent": true}`. `201 {"lead_id", "status": "created", "auto_call"}`; `200` with `status` `duplicate` (not called) or `updated` (repeat enquiry after 24 h). `401` wrong/revoked token or unknown slug, `400` `validation_error` (e.g. `consent` not `true`) / `invalid_phone`, `429` `rate_limited`. |

```bash
curl -X POST https://callpilot-backend.dulalkisku0.workers.dev/hooks/leads/<slug> \
  -H "Authorization: Bearer cplh_<token>" -H "Content-Type: application/json" \
  -d '{"name":"Ravi Kumar","phone":"+91 98300 12345","interest":"NEET coaching","consent":true}'
```

Google Forms (Extensions → Apps Script, trigger *On form submit*; the form must ask for consent):

```js
function onFormSubmit(e) {
  const a = e.namedValues; // question title -> answers
  UrlFetchApp.fetch('https://callpilot-backend.dulalkisku0.workers.dev/hooks/leads/<slug>', {
    method: 'post', contentType: 'application/json',
    headers: { Authorization: 'Bearer cplh_<token>' },
    payload: JSON.stringify({ name: a['Name'][0], phone: a['Phone'][0], interest: (a['Interest'] || [''])[0], consent: true }),
    muteHttpExceptions: true,
  });
}
```

Website: post from **your server** (never put the token in browser JavaScript), or link to / embed the hosted form `https://…/f/<slug>`.

### Lead integrations: Google Ads, IndiaMART, Meta Lead Ads

Three more `lead_sources` kinds feed the **same** pipeline (`captureLead` → consent event → instant call through `services/dial.ts` with every guard; `backend/src/services/lead_integrations.ts`). Leads get `source` = the kind (`google_ads`, `indiamart`, `meta`), `consent: "explicit_opt_in"`, and a consent event with source `google_ads` / `indiamart` / `meta_lead_ads` (text versions `google-ads-lead-form-2026-10`, `indiamart-enquiry-2026-10`, `meta-lead-ads-2026-10`). Each provider lead id (Google `lead_id`, IndiaMART `UNIQUE_QUERY_ID`, Meta `leadgen_id`) becomes a lead at most once per business (`lead_external_ids`), on top of the 24 h phone dedupe. Extra form answers go into `interest`; email / city / company into the lead's `attributes`. Owner setup: [`docs/INTEGRATIONS.md`](../docs/INTEGRATIONS.md).

**Owner APIs** (same endpoints as above):

| Body of `POST /lead-sources` | `201` response (`LeadSource` plus, **once**) |
|---|---|
| `{"kind": "google_ads", "auto_call"?}` | `token` = `google_key`: paste into the Google Ads lead form's webhook *Key*; `url` = `…/hooks/google-ads/<slug>` is the webhook URL. |
| `{"kind": "indiamart", "crm_key": "<IndiaMART CRM / Pull API key>", "auto_call"?}` | `token` and `push_url` = `…/hooks/indiamart/<slug>?key=<token>` (optional IndiaMART Push API listener). The CRM key is stored AES-GCM encrypted. |
| `{"kind": "meta", "app_secret": "<Meta app secret>", "page_access_token": "<page token with leads_retrieval>", "auto_call"?}` | `token` = `verify_token` for the Meta webhook; `url` = `…/hooks/meta/<slug>` is the callback URL. App secret and page token are stored AES-GCM encrypted. |

- Secrets (`token`, `google_key`, `verify_token`, `push_url`) are never returned again; `crm_key`, `app_secret` and `page_access_token` are never returned at all. Missing / malformed secrets: `400 validation_error` (never send `null`). `503 not_configured` if the server has no `ENCRYPTION_KEY`. At most 5 active sources per kind (`409 too_many_sources`).
- `LeadSource` gains `last_error` (null, or `invalid_key`, `rate_limited`, `bad_request`, `upstream_error`, `config_unreadable`, `meta_token_invalid`) and, for IndiaMART, `last_synced_at` (UTC, end of the last successful pull). The first time a source hits `invalid_key` / `meta_token_invalid` / `config_unreadable` the owner gets a `lead_source_error` notification (route `/leads/auto`).
- `PATCH /lead-sources/:id` (`auto_call`) and `POST /lead-sources/:id/revoke` work for every kind; a revoked source's endpoints answer `401` / `403` and IndiaMART stops being pulled.

**Provider endpoints** (public; rate limited 600 / h per IP and per source):

| Method | Path | Notes |
|---|---|---|
| `POST` | `/hooks/google-ads/:slug` | Google Ads lead form webhook JSON (`lead_id`, `user_column_data[{column_id, string_value}]`, `google_key`, `is_test`, `campaign_id`, …). `google_key` checked against the stored SHA-256 in constant time (`401` otherwise). `is_test: true` → `200 {}` and nothing is created or called. Success and duplicates → `200 {}`. No `PHONE_NUMBER` / invalid phone → `400 {"message"}` (permanent for Google). |
| `POST` | `/hooks/indiamart/:slug?key=<token>` | IndiaMART Push API body (`{"CODE":200,"STATUS":"SUCCESS","RESPONSE":{…lead…}}`). Wrong key → `401`; verified pushes always `200 {"CODE":200,"STATUS":"SUCCESS","captured","skipped"}` (IndiaMART deactivates failing listeners). |
| `GET` | `/hooks/meta/:slug?hub.mode=subscribe&hub.verify_token=…&hub.challenge=…` | Meta webhook verification: echoes `hub.challenge` (`200 text/plain`) when the verify token matches, else `403`. |
| `POST` | `/hooks/meta/:slug` | Page `leadgen` events. `X-Hub-Signature-256: sha256=HMAC-SHA256(app secret, raw body)` required (`401`). For each `leadgen_id` the lead is fetched from `https://graph.facebook.com/<META_GRAPH_API_VERSION, default v21.0>/<leadgen_id>?fields=id,created_time,field_data&access_token=<page token>&appsecret_proof=…` and `full_name` / `first_name`+`last_name`, `phone_number`, `email` are mapped. Transient Graph errors → `500` (Meta redelivers; the id is not consumed). A rejected token → `200`, `last_error: meta_token_invalid`. |

**IndiaMART pull (cron).** Every cron run (`*/10`) pulls each active IndiaMART source that is due: at most once per 5 minutes per source (claimed atomically via `last_pulled_at`), `GET https://mapi.indiamart.com/wservce/crm/crmListing/v2/?glusr_crm_key=…&start_time=…&end_time=…` in IST `DD-Mon-YYYYHH:MM:SS`, window = 5 minutes before the previous end (or the source's creation) → now, capped at 7 days. `CODE 200` → leads captured (catalog views `QUERY_TYPE: "BIZ"` and records without a mobile are skipped), `last_cursor` advanced. `204` → no leads, cursor advanced. `429` → `rate_limited` (key blocked: wait 15 min). `401` → `invalid_key`, retried hourly. `400` → cursor reset to now. `5xx` / network → `upstream_error`, retried next run.

---

## 11. Public pages

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | JSON service info (unchanged). `/health` stays `{"status":"ok"}`. |
| `GET` | `/get?ref=<code>` | Mobile-first landing page (HTML, no scripts, strict CSP). Pricing is read from the plan catalogue. The Play Store CTA is `https://play.google.com/store/apps/details?id=com.echoing.heights&referrer=<urlencoded utm_source=landing&utm_campaign=<code or none>>`; the app reads it with the Play Install Referrer API and prefills the signup referral code. Invalid `ref` values are dropped. Shows an `<audio>` demo when `DEMO_AUDIO_URL` (https) is set. |
| `GET` | `/legal/privacy`, `/legal/terms`, `/legal/delete-account` | Legal pages. |

`poweredByFooterHtml(code)` in `backend/src/services/referrals.ts` returns a small "Powered by CallPilot" link to `/get?ref=<code>` for public pages a business shares (e.g. the lead form).

---

## 12. Error Responses & Status Codes

All errors return a consistent JSON schema:
```json
{
  "message": "Human-readable description of error",
  "code": "error_code_identifier",
  "request_id": "uuid-v4-string"
}
```

| HTTP Status | Code | Meaning |
|---|---|---|
| `400` | `validation_error` | Request payload failed schema validation (Zod). Details provided in `errors`. |
| `400` | `phone_registered` | Phone number is already registered in `users` table. |
| `400` | `insufficient_minutes` | Business minute quota is insufficient to start campaign. |
| `402` | `plan_inactive` | Plan is `past_due`/`cancelled`; calls and campaigns are blocked until a payment is received. |
| `401` | `missing_auth` | Authorization header or Bearer token is missing. |
| `401` | `invalid_token` | JWT token expired, malformed, or wrong claim type. |
| `401` | `invalid_otp` | Submitted OTP does not match SHA-256 hash or is expired (>5 min). |
| `401` | `otp_locked` | OTP exceeded maximum 5 failed attempts. |
| `401` | `invalid_signature` | Webhook HMAC signature missing, invalid, or timestamp expired. |
| `403` | `forbidden_path` | Disallowed path requested on `/voice/sarvam-proxy/*`. |
| `403` | `concurrency_limit_exceeded` | Business exceeded concurrent active call or voice session cap. |
| `404` | `not_found` | Resource does not exist or does not belong to user's `business_id`. |
| `429` | `rate_limited` | Rate limit exceeded (OTP requests: 3 / 10 min per phone and per IP). |
| `500` | `server_error` | Internal server exception. Details logged server-side with `request_id`. |
