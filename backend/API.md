# CallPilot – Backend API Contract (v1)

> **Product:** CallPilot (`com.callpilot.app`).  
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
| `POST` | `/leads/:id/call` | - | Initiates outbound call to lead via Sarvam, with the same guardrails as campaigns: agent calling hours, DNC/opt-out, max 3 calls per lead per day, concurrent-call cap and remaining minutes. Errors: `409` `outside_hours` / `do_not_call` / `max_daily_attempts`, `429` `concurrency_limit`, `402` `exhausted_minutes`, `502`/`503` `dial_failed` (503 = retryable). Returns `{ call, sarvam_dispatched }`. |

---

## 5. Calls & AI Analysis

| Method | Path | Response |
|---|---|---|
| `GET` | `/calls?filter=all|connected|noAnswer|hot&lead_id=&cursor=&limit=20` | Paginated `Call` items. Scoped by `business_id`. |
| `GET` | `/calls/:id` | Full `Call` detail. `raw_metadata` and `transcript` are decrypted on retrieval using AES-256-GCM. |

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
5. **Data Protection:** Encrypts `raw_metadata` and transcripts at rest using AES-256-GCM. Never logs transcripts or plain phone numbers.
6. **Billing & FCM Push:** Atomically increments `minutes_used` based on duration. Dispatches FCM data messages for hot leads, campaign completion, and callback reminders (rate limited to 1 per 10 min for follow-ups).

---

## 10. Dashboard, Usage & Notifications

| Method | Path | Response |
|---|---|---|
| `GET` | `/dashboard/today` | `DailySummary`: leads count, connected calls, hot leads, follow-ups ready, callbacks scheduled, recent activity feed. |
| `GET` | `/usage` | `Usage`: subscription (`plan_name`, `plan_id` `trial`/`starter`, `plan_status` `trial`/`active`/`past_due`/`cancelled`, `current_period_end` UTC or null, included minutes, price), minutes used, calls made, `checkout_plan`. |
| `GET` | `/billing` | `{plan_id, plan_name, plan_status, current_period_end, price_inr, included_minutes, minutes_used, minutes_left, checkout_plan}`. |
| `POST` | `/billing/checkout` | Body `{"plan_id": "starter"}` (optional). Creates a Razorpay Payment Link and returns `{url, id}`. `503 billing_not_configured` when Razorpay keys are not set; `502 billing_unavailable` if Razorpay fails. |
| `POST` | `/webhooks/razorpay` | Public. Razorpay `payment_link.paid` webhook, verified with `X-Razorpay-Signature` = hex HMAC-SHA256(raw body, `RAZORPAY_WEBHOOK_SECRET`). Idempotent per Razorpay payment id: activates the paid plan, resets `minutes_used`, extends `current_period_end` by one month. |
| `GET` | `/referrals` | `{code, link, bonus_minutes, signed_up, rewarded, minutes_earned}`. `code` is the business's referral code (6 chars from `23456789ABCDEFGHJKMNPQRSTUVWXYZ`, created on first call); `link` is `<PUBLIC_API_BASE_URL>/get?ref=<code>`. |
| `GET` | `/notifications` | List of in-app notifications. |
| `PATCH` | `/notifications/:id` | `{"read": true}` |
| `POST` | `/notifications/device` | `{"token": "...", "platform": "android"}` registers FCM push token for business. |

### Referral program

- `referral_code` (optional; omit or `null`) on `POST /auth/register` and new-account `POST /auth/google`. Case, spaces and dashes are ignored. An unknown/malformed code, self-referral (the referrer's own phone or email) or a phone that was already referred once (even before an account deletion) is silently ignored: signup never fails because of a code.
- Reward: when the referred business's first Razorpay payment is applied (`payment_link.paid`), both businesses get `REFERRAL_BONUS_MINUTES` (default 200) added to `included_minutes`, once, with a `referral_credits` ledger row each. Webhook redeliveries and later payments don't credit again.
- Bonus minutes are added to the current period's `included_minutes`; a later renewal resets `included_minutes` to the plan amount.

---

## 11. Public pages

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | JSON service info (unchanged). `/health` stays `{"status":"ok"}`. |
| `GET` | `/get?ref=<code>` | Mobile-first landing page (HTML, no scripts, strict CSP). Pricing is read from the plan catalogue. The Play Store CTA is `https://play.google.com/store/apps/details?id=com.callpilot.app&referrer=<urlencoded utm_source=landing&utm_campaign=<code or none>>`; the app reads it with the Play Install Referrer API and prefills the signup referral code. Invalid `ref` values are dropped. Shows an `<audio>` demo when `DEMO_AUDIO_URL` (https) is set. |
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
