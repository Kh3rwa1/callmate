# CallPilot Telecommunications Compliance & Regulatory Notice

> [!CAUTION]
> **DISCLAIMER**: CallPilot software implements engineering guardrails and tenant controls to assist businesses with telephony rules. CallPilot does **NOT** certify, warrant, or claim legal compliance with Indian telecommunications regulations, TRAI rules, or local carrier laws. All deploying businesses and operators must conduct their own legal and regulatory review before placing commercial outbound voice calls.

---

## 1. Regulatory Context (India Telecommunications & TRAI)

Outbound automated voice calls in India are regulated under:
- **Telecom Commercial Communications Customer Preference Regulations (TCCCPR, 2018)** issued by the Telecom Regulatory Authority of India (TRAI).
- **The Telecommunications Act, 2023**.
- DND (Do Not Disturb) / NDNC (National Do Not Call) Registry directives.

---

## 2. In-Code Guardrails Implemented by CallPilot

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

## 3. Mandatory Compliance Review (TODO for Legal & Operators)

The following items must be verified by legal counsel and telecommunications compliance specialists prior to commercial operation:

- [ ] **TODO (Legal Review)**: Verify Enterprise Entity Registration on the TRAI DLT (Distributed Ledger Technology) portal with licensed telecom service providers (Airtel, Jio, Vi, BSNL).
- [ ] **TODO (Legal Review)**: Ensure all outbound telephony CLI (Caller Line Identification) numbers utilize registered **140-series prefixes** for promotional calls or **160-series prefixes** for transactional / service calls as mandated by TRAI directives.
- [ ] **TODO (Legal Review)**: Establish a periodic batch scrubbing mechanism against the national NDNC / DND database via licensed Telemarketer Aggregators.
- [ ] **TODO (Legal Review)**: Review explicit customer consent capture procedures (PE - Principal Entity consent records) to ensure verifiable opt-in timestamps for promotional campaigns.
- [ ] **TODO (Legal Review)**: Formalize privacy policy disclosures and terms of service regarding AI-generated voice conversations, recording retention periods, and encryption at rest.

---

## 4. Technical Architecture Reference

- Calling compliance evaluator: `backend/src/services/compliance.ts`
- Campaign queue consumer: `backend/src/services/campaign_queue.ts`
- Webhook opt-out detection: `backend/src/routes/voice.ts`
- Database schema: `backend/migrations/0004_compliance_and_billing.sql`
