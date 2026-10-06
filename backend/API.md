# Riya AI – Backend API contract (v1)

The mobile app talks **only** to this backend. The backend owns Sarvam Voice
Agents, telephony, webhooks, secrets, scoring normalisation and push.

```
Flutter app ──(JWT)──► Our backend ──(X-API-Key)──► Sarvam Voice Agents ──► Telephony ──► Lead phone
                              ▲                                   │
                              └──── completed-call webhook ◄──────┘
```

All responses are JSON, snake_case. Lists: `{ "items": [...], "has_more": bool, "next_cursor": "..." }`.
Errors: `{ "message": "User-presentable text", "code": "..." }`.

## Auth
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/auth/register` | `{phone, business_name}` | `{access_token, refresh_token}` |
| POST | `/auth/login` | `{phone, otp}` | `{access_token, refresh_token}` |
| POST | `/auth/refresh` | `{refresh_token}` | `{access_token, refresh_token}` |

## Business & agent
| GET/PATCH | `/business` | `Business` |
| GET/PATCH | `/agent` | `Agent` (name, role, languages, formality, calling hours, transfer_number, status) |

## Knowledge
| POST | `/knowledge` | multipart: `type, title, content?, url?, file?` → `KnowledgeSource` (status `processing`) |
| GET | `/knowledge` · `/knowledge/:id` | poll until `ready` / `failed` |
| DELETE | `/knowledge/:id` | |

Backend extracts text and syncs it into the Sarvam agent knowledge base.

## Leads
| GET | `/leads?filter=all|new|called|hot|warm|callback&q=&cursor=&limit=20` | paginated `Lead` |
| POST | `/leads` | `{name, phone, course_interest?, source}` |
| POST | `/leads/import` | `{leads:[...]}` → `{imported, skipped, errors[]}` (server re-validates + dedupes phones) |
| GET/PATCH | `/leads/:id` | |

## Calls (normalised – UI never sees raw webhook payloads)
| GET | `/calls?filter=all|connected|noAnswer|hot&lead_id=&cursor=` | paginated `Call` |
| GET | `/calls/:id` | `Call` incl. `transcript`, `lead_score`, `next_action`, `interaction_id` |

## Campaigns
| POST | `/campaigns` | `CampaignDraft` → `Campaign` (draft) |
| GET | `/campaigns/:id` · `/campaigns?status=running` | |
| POST | `/campaigns/:id/start` · `/campaigns/:id/stop` | |

Backend creates the Sarvam outbound campaign, passing per-lead **agent variables**
(see `templates/coaching_admissions_v1.json → agent_variables_in`).

## Follow-ups & callbacks
| GET | `/followups?status=ready&call_id=` | |
| GET/PATCH | `/followups/:id` | PATCH `{message?, status: opened|done|dismissed, opened_at?}` |
| GET/POST | `/callbacks` | POST `{lead_id, scheduled_at, note?}` |
| PATCH | `/callbacks/:id` | `{status: done}` |

`status=opened` means **WhatsApp was opened**. Nothing is ever sent automatically.

## Voice test (in-app "Talk to Riya")
| POST | `/voice/test-session` | → `{session_token, org_id, workspace_id, app_id, version?, proxy_base_url, agent_variables, user_identifier}` |
| * | `/voice/sarvam-proxy/*` | Proxies to `https://apps.sarvam.ai/api/app-runtime/*`, validates `Authorization: Bearer <session_token>`, injects `X-API-Key`. Allow-list paths, rate-limit per business. |

This follows Sarvam's documented proxy pattern for `SamvaadAgent(baseUrl:, headers:)`.

## Dashboard, usage, notifications
| GET | `/dashboard/today` | `{leads, connected, interested, hot, calls_today, followups_ready, callbacks_today, new_leads_ready, activity[]}` |
| GET | `/usage` | `{subscription:{plan_name, included_minutes, renews_at, price_inr}, minutes_used, calls_made, rate_per_minute_inr}` |
| GET | `/notifications` · PATCH `/notifications/:id` | |

## Webhook: Sarvam completed call → normalise
1. Verify signature (`SARVAM_WEBHOOK_SECRET`), idempotency on `interaction_id`.
2. Map connectivity/outcome → `Call.status` (`completed | no_answer | busy | failed`).
3. Validate agent output variables against `schemas/call_output.schema.json`.
   Invalid / missing → score 0, `temperature=cold`, flag for review (never crash).
4. Upsert `Call`, update `Lead` (score, summary, objections, next_action, callback_at).
5. If `whatsapp_followup_required` → create `FollowUp(status=ready)`.
6. If `callback_at` → create `Callback`.
7. Push (FCM data message `{title, body, route}`) **only** for: hot lead, campaign finished,
   callback reminder. Batch follow-up-ready pushes (max 1 per 10 min) to avoid over-notifying.
8. Store raw payload in `raw_metadata` (encrypted at rest). Never log transcripts.

## Push routes (deep links)
`/followups/:id` · `/calls/:id/result` · `/leads/:id` · `/leads?filter=hot` · `/campaigns/:id` · `/callbacks`
