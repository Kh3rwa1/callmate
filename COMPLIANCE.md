# CallPilot Telecommunications Compliance & Regulatory Notice

> [!CAUTION]
> **DISCLAIMER**: CallPilot software implements engineering guardrails and tenant controls to assist businesses with telephony rules. CallPilot does **NOT** certify, warrant, or claim legal compliance with Indian telecommunications regulations, TRAI rules, or local carrier laws. All deploying businesses and operators must conduct their own legal and regulatory review before placing commercial outbound voice calls.

---

## 1. Regulatory Context (India Telecommunications & TRAI)

Outbound automated voice calls in India are regulated under:
- **Telecom Commercial Communications Customer Preference Regulations (TCCCPR, 2018)** issued by the Telecom Regulatory Authority of India (TRAI), including the 2024/2025 amendments (140/160 number series, stricter penalties for unregistered telemarketers).
- **The Telecommunications Act, 2023**.
- DND (Do Not Disturb) / NCPR (National Customer Preference Register) directives.
- **The Digital Personal Data Protection Act, 2023 (DPDP)**: notice, consent evidence, purpose limitation, erasure.

---

## 2. What the code enforces

| # | Guardrail | Where |
|---|---|---|
| 1 | **Calling hours.** Never before 09:00 or from 21:00 in the lead's timezone (TRAI), narrowed further by the owner's window (default 10:00-19:00 IST). Leads outside the window are rescheduled, never dropped or force-dialled. | `services/compliance.ts` `checkCallCompliance` |
| 2 | **Per-business DNC / opt-out.** `do_not_call = 1` or `consent = 'opt_out'` leads are never dialled (`skipped_dnc`). | `checkCallCompliance` |
| 3 | **In-call opt-out.** The webhook inspects what the *customer* said (English, Hinglish, Hindi) and the agent's `intent`/`next_action`. A match sets `do_not_call = 1`, `consent = 'opt_out'` and records a `consent_events` row (`in_call_opt_out`). **This is per business** (only that business's lead): a sentence like "don't call me" can't reliably be read as "stop every company", so platform-wide opt-out is the explicit `/stop` page. | `routes/voice.ts`, `isOptOutRequest` |
| 4 | **Platform-wide opt-out (`/stop`).** A public, script-free page where anyone enters their number to stop calls from **every** business. Stored only as HMAC(`OTP_PEPPER`, digits) in `global_dnc`; every dial path checks it and fails closed if the hashing key is missing. Rate limited to 10 submissions per IP per hour. Linked from the privacy policy. | `routes/stop.ts`, `services/global_dnc.ts` |
| 5 | **Per-lead caps.** Max 3 calls per lead per 24h; max 3 attempts per campaign. Provider-rejected dials (`failed` with no `interaction_id`) don't count. | `checkCallCompliance` |
| 6 | **Platform frequency cap.** A phone number can be rung by at most **3 distinct businesses per rolling 24h** (`platform_frequency_cap`), and campaigns ring a number at most **once per business per 24h** (no-answer retries wait for the next day). | `checkCallCompliance`, index `idx_calls_lead_phone_started` |
| 7 | **AI + recording disclosure.** With `SARVAM_DISCLOSURE_OVERRIDE = "true"`, every dial (manual and campaign) overrides the agent's first sentence with ours, in the employee's first language (English / Hindi / Bengali): who is calling, that it is an AI assistant, for which business, and that the call may be recorded. Off by default until verified on staging (see `docs/SARVAM_SETUP.md`). | `services/disclosure.ts`, `dialSarvam` |
| 8 | **Consent evidence trail.** Every consent change is written to `consent_events` (value, source, wording version, hashed IP): lead create / edit (`manual`), import (`import_attestation`), campaign start with the owner's attestation (`import_attestation`, `owner_attested`), in-call opt-out. Lead-capture forms and lead-source webhooks use `recordConsentEvent` with `form` / `webhook`. Visible to the owner on the lead screen (`GET /leads/:id/consent-history`). | `services/consent.ts` |
| 9 | **Unknown consent is not called by campaigns** unless the owner ticks the attestation when starting the campaign. | `routes/campaigns.ts` |
| 10 | **Retention.** Transcripts, recording links, summaries and the raw webhook payload are cleared `RETENTION_DAYS` (default 180) after the call, 500 calls per cron run. Metadata and scores stay. | `services/retention.ts` |
| 11 | **Encryption at rest.** Transcripts, raw webhook payloads and recording links are AES-256-GCM encrypted (legacy plaintext rows still read). | `utils/crypto_data.ts`, `routes/voice.ts` |
| 12 | **DLT caller-ID check.** `/health/deep` reports `compliance.caller_ids_dlt_series` (true only if every `SARVAM_AGENT_PHONE_NUMBERS` entry is `+91140…` or `+91160…`); production logs `caller_ids_not_dlt_series` once per cron run until fixed. | `callerIdsAreDltSeries` |
| 13 | **Zero automated messaging.** WhatsApp follow-ups are only deep links the owner taps. | app |
The CallPilot platform enforces the following operational guardrails at runtime:

1. **Calling Hours Enforcement**:
   - Calling windows are strictly enforced against the lead's timezone (default `Asia/Kolkata`).
   - Default calling hours are restricted between **10:00 AM and 7:00 PM IST** (more restrictive than the TRAI maximum allowed window of 9:00 AM to 9:00 PM IST).
   - Leads outside the active window are automatically **rescheduled**, never dropped or forcefully dialed.

2. **Tenant Do Not Call (DNC) Registry & Instant Opt-Out**:
   - Every lead contains a `do_not_call` binary flag and a `consent` provenance state.
   - Any lead marked `do_not_call = 1` is immediately skipped during campaign queue dispatch (`skipped_dnc`).
   - **Automated Opt-Out**: The webhook processing pipeline inspects transcripts and caller intent for explicit opt-out phrases (e.g., *"don't call me"*, *"stop calling"*, *"remove my number"*, *"unsubscribe"*). If detected, the lead is immediately transitioned to `do_not_call = 1` and `consent = 'opt_out'`.

3. **Per-Lead Daily and Campaign Attempt Caps**:
   - Outbound attempts are limited to a maximum of **3 calls per lead per 24-hour period**.
   - Outbound campaign retries are capped at **3 total attempts per campaign**.

4. **Speed-to-lead consent**:
   - Leads from the hosted enquiry form (`/f/:slug`) are only created when the person ticks a consent box naming the business and saying the call may be an automated AI call; webhook senders must send `consent: true`. Such leads get `consent = 'explicit_opt_in'` with the enquiry time in `last_enquiry_at`.
   - Their instant AI call runs the same guards as any manual call (calling hours, DNC/opt-out, daily cap, minutes). A repeat enquiry never overrides an opt-out or do-not-call flag.

5. **Zero Automated Messaging**:
   - CallPilot guarantees that **no automated messages are sent via WhatsApp or external channels**. WhatsApp follow-up messages require explicit human initiation (`status = 'ready' -> opened`).

---

## 3. What the owner / operator must do (code can't)

- [ ] **DLT registration.** Register the Principal Entity (and the telemarketer, if any) on an operator's DLT portal (Jio, Airtel, Vi, BSNL), including headers/templates/consent templates where the operator requires them for voice.
- [ ] **140 / 160 series caller IDs.** Promotional calls must come from a **140-series** number and service / transactional calls from a **160-series** number. Today's Vobiz numbers (`+9179…`) are not; `/health/deep` shows `caller_ids_dlt_series: false` and production logs a warning every cron run. Onboard compliant numbers in Sarvam, then update `SARVAM_AGENT_PHONE_NUMBERS`.
- [ ] **NCPR / DND scrubbing.** CallPilot cannot query the national DND register. Promotional calls must be scrubbed against NCPR through the DLT operator / telemarketer (or limited to leads with explicit consent, which DLT consent templates record). Our `/stop` list is in addition to NCPR, not a replacement.
- [ ] **Sarvam agent opt-out handling.** The agent prompt must, when the person says they don't want calls, apologise, confirm they won't be called again, end the call, and set output `intent = "opt_out"` (the webhook also reads the transcript). Re-test after every agent version.
- [ ] **Turn on the disclosure override** after one staging test call (`SARVAM_DISCLOSURE_OVERRIDE = "true"`), or make sure the agent's own first sentence discloses AI + recording.
- [ ] **Consent capture.** Only upload leads who enquired / opted in; keep the original enquiry evidence (forms, ads) as the Principal Entity.
- [ ] **Legal review.** Have counsel review the privacy policy (`/legal/privacy`), terms, retention period and this list; name the Grievance Officer.

---

## 4. Technical Architecture Reference

- Calling compliance evaluator: `backend/src/services/compliance.ts`
- Disclosure: `backend/src/services/disclosure.ts`
- Platform-wide DNC: `backend/src/services/global_dnc.ts`, page `backend/src/routes/stop.ts`
- Consent evidence: `backend/src/services/consent.ts`, `GET /leads/:id/consent-history` in `backend/src/routes/consent.ts`
- Retention + DLT warning cron: `backend/src/services/retention.ts`
- Campaign queue consumer: `backend/src/services/campaign_queue.ts`
- Webhook opt-out detection: `backend/src/routes/voice.ts`
- Database schema: `backend/migrations/0004_compliance_and_billing.sql`, `backend/migrations/0013_regulatory_hardening.sql`
