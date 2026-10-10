## What and why
<!-- One or two sentences. Link the issue if there is one. -->

## How it was tested
<!-- Commands run, device/emulator used, staging checks. -->

## Checklist
- [ ] Tests added/updated (Flutter `test/` and/or `backend/test/`); coverage gates still pass
- [ ] `flutter analyze`, `flutter test`, bundled-Dart `dart format`, backend `vitest` / `tsc` / `npm test` pass locally (see `AGENTS.md`)
- [ ] New user-visible strings added in `lib/l10n/` for **en / hi / bn**
- [ ] API contract changed → `API.md` and `backend/API.md` updated
- [ ] Schema changed → new numbered migration in `backend/migrations/` (no edits to shipped ones)
- [ ] Optional fields: no `null` sent for `.optional()` schema keys
- [ ] UI change → screenshots / screen recording attached below
- [ ] No secrets, real phone numbers or customer data in code, tests or screenshots
- [ ] Android only — nothing added for iOS

## Screenshots
<!-- Before / after, if UI changed. -->
