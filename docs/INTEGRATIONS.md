# Lead integrations: Google Ads, IndiaMART, Facebook & Instagram

Leads from Google Ads lead forms, IndiaMART Lead Manager and Meta (Facebook /
Instagram) Lead Ads come into CallPilot by themselves and, with auto-call on,
get an AI call within about a minute, through exactly the same pipeline and
guards as the hosted enquiry form (calling hours, do-not-call, `/stop`, daily
caps, minutes). The owner connects each one in the app: **Customers → Get leads
automatically → Connect a lead source**.

Contract: [`API.md` §10b](../API.md) ("Lead integrations"). Code:
`backend/src/services/lead_integrations.ts`,
`backend/src/routes/lead_integrations_public.ts`,
`lib/features/leads/lead_integrations.dart`.

| | Google Ads | IndiaMART | Facebook & Instagram |
|---|---|---|---|
| How leads arrive | Google POSTs each lead to our webhook | We pull IndiaMART every cron run (≥ 5 min apart), plus optional push | Meta POSTs a `leadgen` event, we fetch the lead from the Graph API |
| What the owner pastes into CallPilot | nothing | CRM (Pull API) key | App Secret + Page access token |
| What CallPilot shows once | webhook URL + key | push URL (optional) | callback URL + verify token |
| Stored | SHA-256 of the key | CRM key encrypted (AES-GCM) + SHA-256 of the push token | App Secret + page token encrypted + SHA-256 of the verify token |
| Test leads | `is_test` leads are acknowledged and ignored | - | Lead Ads Testing Tool leads are real leads (they are called) |
| Consent event source | `google_ads` | `indiamart` | `meta_lead_ads` |

Secrets are shown once and never again. To change a key, tap **Connect** again
(the old connection is turned off when the new one works) or turn it off and
connect a new one.

---

## Google Ads lead forms

Requirements: a Google Ads campaign with a **lead form asset** that asks for
the phone number.

1. In CallPilot tap **Google Ads → Connect**. Copy the **webhook URL** and the
   **key**.
2. In Google Ads open the campaign → *Assets* → the lead form → *Lead delivery
   options* → **Webhook integration**. Paste the webhook URL and the key.
3. Tap **Send test data**. Google sends a test lead (`is_test: true`): we
   check the key and answer `200 {}`, nothing is created and nobody is called.
4. Done. Each real lead is deduplicated by Google's `lead_id` (Google may
   deliver a lead more than once).

Field mapping: `FULL_NAME` (or `FIRST_NAME` + `LAST_NAME`) → name,
`PHONE_NUMBER` (or `WORK_PHONE`) → phone, `EMAIL` / `CITY` / `COMPANY_NAME` →
lead details, any other question (e.g. "Which course are you interested in?")
→ interest. A lead without a phone number gets `400` (Google does not retry
4xx); add a phone question to the form.

Consent: the person submitted the advertiser's lead form asking to be
contacted; recorded as `explicit_opt_in`, source `google_ads`, wording
`google-ads-lead-form-2026-10`. Make sure the form's privacy policy link and
description say that the business may call (possibly with an automated AI
assistant).

---

## IndiaMART Lead Manager

Requirements: a **paid** IndiaMART seller account (the Pull / Push API is an
add-on of paid plans).

1. Log in at [seller.indiamart.com](https://seller.indiamart.com) → **Lead
   Manager** → ⋮ → *Import/Export Leads* → **Pull API** (or
   `https://seller.indiamart.com/leadmanager/crmapi`) and tap **Generate Key**.
   Generating a new key disables the old one.
2. In CallPilot tap **IndiaMART → Connect**, paste the key, tap **Connect**.
3. We pull new enquiries at most once every 5 minutes (IndiaMART's limit; our
   cron runs every 10 minutes, so typically every 10). The screen shows "Last
   checked …".
4. Optional, for instant leads: in Lead Manager → ⋮ → *Import/Export Leads* →
   **Push API**, choose **Other**, and paste the **push URL** CallPilot showed
   (`https://<api>/hooks/indiamart/<slug>?key=<token>`), then confirm with the
   OTP. Pull keeps running as a safety net; the same enquiry is never created
   twice (`UNIQUE_QUERY_ID`).

Notes:
- The Pull API key **expires if unused for 7 days**. As long as the
  connection is on we use it every run, so it stays alive. If it expires or is
  regenerated, the app shows "Your IndiaMART key stopped working" and the owner
  gets one notification; connect again with the new key.
- Rate limits: one hit per 5 minutes per key; more than 5 hits a minute blocks
  the key for 15 minutes (we then wait 15 minutes). Don't use the same key in
  another CRM at the same time.
- Leads mapped: direct enquiries (`W`), buy-leads (`B`), PNS calls (`P`),
  WhatsApp enquiries (`WA`). **Catalog views (`BIZ`) are skipped**: the buyer
  only looked at the catalogue and did not ask to be contacted.
- Mapping: `SENDER_NAME` → name (`IndiaMART Buyer` if missing),
  `SENDER_MOBILE` (or `SENDER_MOBILE_ALT`) → phone, `QUERY_PRODUCT_NAME` (or
  `SUBJECT`) + `QUERY_MESSAGE` → interest, email / city / company → details.

Consent: the buyer sent the seller an enquiry or called them on IndiaMART;
recorded as `explicit_opt_in`, source `indiamart`, wording
`indiamart-enquiry-2026-10`.

---

## Facebook & Instagram Lead Ads (Meta)

Meta only delivers leads to an app the Page has authorised. CallPilot does not
(yet) have its own reviewed Meta app, so each business connects **its own Meta
app**. This needs someone comfortable with the Meta developer console. App
Review is the owner's job.

1. **Create the app.** At [developers.facebook.com](https://developers.facebook.com)
   → *My Apps* → *Create app* (type *Business*), linked to the business
   portfolio that owns the Facebook Page. Add the **Webhooks** product.
2. **App Secret.** *App settings → Basic* → **App Secret** (Show).
3. **Page access token** with `leads_retrieval`, `pages_show_list`,
   `pages_read_engagement`, `pages_manage_metadata` and `ads_management`
   (or use a System User in Business Settings with the Page assigned and
   generate a **non-expiring** token with those permissions; a normal
   user-derived page token expires). The person generating it must have the
   *Leads* access on the Page (*Page settings → Leads access*; give the app /
   system user access there too).
4. **Connect in CallPilot.** Tap **Facebook & Instagram → Connect**, paste the
   App Secret and the page access token, tap **Connect**. Copy the
   **callback URL** and the **verify token**.
5. **Webhook.** In the app → *Webhooks* → choose **Page** → *Subscribe to this
   object* → paste the callback URL and verify token → *Verify and save*
   (Meta calls `GET /hooks/meta/<slug>` with `hub.challenge`; we echo it).
   Then subscribe to the **`leadgen`** field.
6. **Subscribe the Page to the app** (once):
   `POST https://graph.facebook.com/v21.0/<PAGE_ID>/subscribed_apps?subscribed_fields=leadgen&access_token=<PAGE_TOKEN>`
   (needs `pages_manage_metadata`).
7. **Test** with the [Lead Ads Testing Tool](https://developers.facebook.com/tools/lead-ads-testing):
   pick the Page and form, *Create lead*. Note: these are real leads to us and
   **will be called** if auto-call is on; use the owner's own phone number.
8. **Go live.** While the app is in *Development* mode only people with a role
   on the app produce webhooks. Switch it to *Live*; for `leads_retrieval` and
   `pages_manage_metadata` on Pages the business doesn't own, Advanced Access /
   App Review is needed (not for the business's own Page with Standard Access in
   most cases, but Meta's rules change: check *App Review → Permissions*).

What we do: each POST must carry `X-Hub-Signature-256` = HMAC-SHA256 of the raw
body with the App Secret (else `401`). For each `leadgen_id` we fetch
`GET /<version>/<leadgen_id>?fields=id,created_time,field_data` with the page
token and `appsecret_proof`, then map `full_name` (or first/last name),
`phone_number`, `email`, `city`; other questions → interest. Forms must ask for
the phone number. If Graph says the token is invalid, the app shows "Facebook
stopped sharing leads" and the owner gets one notification; connect again with a
new token. Temporary Graph errors return `500` so Meta redelivers.

The Graph API version defaults to `v21.0`; set the Worker variable
`META_GRAPH_API_VERSION` (e.g. `v23.0`) when Meta retires it.

Consent: the person submitted the business's instant form; recorded as
`explicit_opt_in`, source `meta_lead_ads`, wording `meta-lead-ads-2026-10`. The
form's privacy policy and custom disclaimer should say the business may call,
possibly with an automated AI assistant.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Google "Send test data" fails | Key pasted exactly (no spaces)? Connection still on? `401` = wrong key or turned off. |
| Google leads missing | Form must have a phone question (`400` otherwise; see Google Ads → lead form → webhook delivery status). |
| IndiaMART "key stopped working" | Key regenerated or expired (7 days unused). Generate a new key and connect again. |
| IndiaMART slow | Pull runs every cron (10 min). For instant leads set up the push URL. |
| Meta webhook won't verify | Callback URL and verify token from the *same* connection; connection still on (`403` otherwise). |
| Meta leads missing | Page subscribed to the app (`subscribed_apps`), `leadgen` field subscribed, app Live, token has `leads_retrieval`, Leads access given to the app. Look for `meta_token_invalid` in the app. |

Operator queries: see [`RUNBOOK.md`](../RUNBOOK.md) §9.
