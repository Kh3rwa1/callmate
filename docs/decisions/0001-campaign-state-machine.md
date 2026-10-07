# ADR 0001: Campaign Queue State Machine & Dial Concurrency Architecture

## Status
Accepted

## Context
In early implementations of outbound calling campaigns, lead dial dispatch suffered from critical reliability and concurrency flaws:
1. Leads were marked `calling` before outbound dial dispatch was verified with the Sarvam AI telephony API.
2. If the dial attempt failed or network dropped, leads remained stuck in `calling` indefinitely.
3. Queue worker retries exited prematurely because leads were already marked `calling`.
4. Concurrency limits were not enforced atomically, resulting in dial bursts and rate limit exhaustion.
5. Campaigns resuming from a paused state re-enqueued leads that had already completed or failed.
6. Cloudflare Queues default retry limit (3 retries) dropped messages during concurrency throttling or outside-hours delay windows.

## Decision
We refactored the campaign queue service into a strictly verified, idempotent, and atomic state machine backed by Cloudflare Queues and Cloudflare D1 transactions.

### 1. State Transitions for `campaign_leads.status`
The state machine governs each lead's lifecycle throughout a campaign:

```
               +-------------------------------------------+
               |                                           | (start / resume)
               v                                           |
+---------> pending ---------------------------------> queued
|              ^                                           |
|              | (rescheduled outside hours)               | (worker claims)
|              |                                           v
|       rescheduled <---------------------------------- calling
|                                                      /   \
|                                     (dial 500 / 429)/     \(dial ok / webhook)
|                                                    /       \
+--- (re-queue) <--- retry_pending <----------------+         +---> completed
                            | (attempts >= 3)
                            v
                          failed (terminal)
```

- **`pending`**: Lead is queued to be dialled when the campaign begins.
- **`queued`**: Transitioned atomically upon campaign start or batch enqueue. Only leads in `pending`, `rescheduled`, or `retry_pending` can transition into `queued`.
- **`calling`**: The **ONLY** entry point into `calling` is an atomic SQL update claim in `processCampaignJob`:
  ```sql
  UPDATE campaign_leads
     SET status = 'calling', attempts = attempts + 1, last_attempt_at = datetime('now'), call_id = ?
   WHERE campaign_id = ? AND lead_id = ?
     AND status IN ('pending', 'queued', 'rescheduled', 'retry_pending')
     AND attempts < 3
  ```
  If `changes === 0`, another worker claimed the lead or attempts were exhausted; the worker exits idempotently.
- **`retry_pending`**: Temporary state if the dial encounters a retryable HTTP error (e.g. 500, 502, 503, 504, 429) and `attempts < 3`. An exponential backoff delay is calculated ($60\text{s}, 120\text{s}, 240\text{s}$) and the message is retried via Queue.
- **`rescheduled`**: If the job runs outside permitted calling hours (09:00 - 20:00 IST), the lead is transitioned to `rescheduled` and delayed until the next morning.
- **`completed`**: Lead successfully finished a call and processed by the webhook. Never re-dialled.
- **`failed`**: Lead exceeded `MAX_DIAL_ATTEMPTS` (3) or suffered a non-retryable 4xx dial rejection. Terminal state.
- **`skipped_dnc`**: Lead has `do_not_call = 1` or explicitly opted out. Bypassed before dialing.

### 2. Double Delivery & Concurrency Protection
- **Double Delivery**: Cloudflare Queues guarantees at-least-once delivery. Even if two workers pick up the same job concurrently, the atomic `UPDATE ... WHERE status IN (...)` ensures exactly one worker acquires the row and inserts the call record.
- **Concurrency Cap**: Enforces `MAX_CONCURRENT_CALLS_PER_BUSINESS = 5`. If active calls reach capacity, the job yields and retries with a short backoff (15s) without dropping the lead.
- **Billing Guard**: Before claiming a dial slot, the tenant's remaining balance (`included_minutes - minutes_used`) is verified. If balance $\le 0$, the campaign is paused automatically.
- **Queue Retry Configuration**: `wrangler.toml` sets `max_retries = 100` and `dead_letter_queue = "callpilot-campaign-dlq"` to prevent dropping delayed or throttled messages.

## Consequences
- Guaranteed at-most-once dialling per attempt.
- Resuming campaigns only dials leads that legitimately require calling.
- Full auditable traceability with `calls.campaign_id`, `calls.failure_reason`, and `campaign_leads.attempts`.
- Telephony failures cleanly back off instead of causing infinite loops or wedged workers.
