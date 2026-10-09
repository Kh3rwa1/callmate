# CallPilot – agent context

Read this before changing anything. It is the shared context for any AI coding
agent (Antigravity, Claude Code, Cursor, …). Human docs: `README.md`,
`API.md` (backend contract), `RUNBOOK.md` (deploy/ops), `docs/SARVAM_SETUP.md`.

## What it is
Flutter app (`com.callpilot.app`, Dart package `callpilot`) where a business
"hires" an AI employee that calls leads, scores them, and drafts WhatsApp
follow-ups the owner reviews and sends. Backend: Cloudflare Worker (Hono) +
D1 + R2 + Queues in `backend/`, calling Sarvam AI voice agents.

**Android only.** Do not build, fix or verify iOS; leave `ios/` alone.

## Layout
- `lib/features/<feature>/` – screens + controllers (Riverpod).
- `lib/core/providers.dart` – all providers; `useMockProvider` picks mock vs API repos.
- `lib/core/network/api_client.dart` – Dio client (auth, refresh, retries).
- `lib/data/datasources/api/api_repositories.dart` – real backend calls.
- `lib/data/datasources/mock/` – offline mock backend (demo + tests).
- `lib/data/models/` – models; `json.dart` has the JSON helpers.
- `backend/src/routes/*.ts` – API routes; `backend/src/schemas/validation.ts` – zod schemas.
- `backend/migrations/` – D1 migrations (applied automatically on deploy).
- `test/` – Flutter tests; `backend/test` + `backend/scripts/test_e2e.mjs` – backend tests.

## Run
```bash
flutter run --dart-define-from-file=env/dev.json       # mock, fully offline
flutter run --dart-define-from-file=env/staging.json   # real staging backend
# add --dart-define=PHONE_OTP_LOGIN=true to show phone login (staging OTP: 123456)
```
Staging API: https://callpilot-backend-staging.dulalkisku0.workers.dev

## Checks (all must pass; CI enforces them)
```bash
flutter analyze
flutter test
"$(flutter --version --machine | python3 -c 'import sys,json;print(json.load(sys.stdin)["flutterRoot"])')/bin/cache/dart-sdk/bin/dart" format lib test
cd backend && npx vitest run && npx tsc --noEmit && npm test   # npm test = E2E on local wrangler
```
- **Format with Flutter's bundled Dart**, not the `dart` on PATH (Homebrew
  3.9.x formats differently and fails CI).
- Local E2E needs migrated local D1 once: `cd backend && npx wrangler d1 migrations apply callpilot-db --local`.

## Deploy
- Merge to `main` → CI → **Deploy Staging** workflow deploys automatically
  (GitHub secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`).
- Manual staging deploy: `cd backend && npx wrangler deploy --env staging`.
- Production: **Deploy Production** workflow (manual, by commit SHA). Never
  deploy prod without the owner asking.

## Rules learned the hard way
1. **Never send `null` for optional fields** the backend schema marks
   `.optional()` – zod rejects it (“expected string, received null”). Omit the
   key (`'note': ?note` / `if (x != null) 'x': x`) or make the schema
   `.nullable().optional()`. Check both sides when adding a field.
2. **Writes must refresh screens.** `ApiClient` reports every successful
   POST/PATCH/DELETE through `onMutation` → `DataChangedEvent` → `dataVersionProvider`.
   If you call `api.dio` directly (e.g. uploads), call `api.onMutation` yourself.
3. **Server timestamps are UTC without a zone** (`2026-10-09 01:29:20`).
   Always parse with `jDate` (it adds `Z`); send dates with `dateOut` (UTC ISO).
4. **Errors in a bottom sheet** must render inside the sheet – a snackbar shows
   behind the modal.
5. **Consent:** leads default to `consent: 'unknown'`; campaigns skip them
   unless the owner ticks the attestation. UI counts must reflect that.
6. Campaigns take at most 500 leads (`MAX_CAMPAIGN_LEADS`).
7. Never auto-send WhatsApp; only deep links the owner taps.

## Testing on a real phone
Real calls dial real numbers and cost minutes – never start a staging campaign
or AI call to made-up numbers; use the owner's own number. Mock build
(`env/dev.json`) has Demo controls to simulate calls, campaigns and pushes.
