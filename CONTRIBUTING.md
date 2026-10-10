# Contributing to CallPilot

Read [`AGENTS.md`](AGENTS.md) first: it holds the project rules, layout and
the exact check commands (humans and AI agents follow the same file). System
overview: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Workflow
1. Branch from `main`: `feat/…`, `fix/…`, `chore/…`, `docs/…`.
2. Keep PRs focused; fill in the PR template checklist.
3. CI must be green before merge (`CI` workflow): secret scan, Flutter
   format/analyze/test + coverage gate, backend typecheck/vitest + coverage
   gate/E2E, dependency audit, Android release build.
4. Merging to `main` deploys **staging** automatically. Production is a
   manual workflow run by the owner. Never deploy from a PR.

## Rules that bite
- **Formatting:** use Flutter's bundled Dart, not the `dart` on `PATH`
  (see the format command in `AGENTS.md`). CI runs
  `dart format --set-exit-if-changed .`.
- **Android only.** Don't build, fix or verify iOS.
- **Never send `null` for optional fields**; omit the key or make the zod
  schema `.nullable().optional()`. Check client and server together.
- **Strings:** every user-visible string goes in `lib/l10n/` with English,
  Hindi and Bengali.
- **API changes:** update `API.md` and `backend/API.md` in the same PR.
- **Migrations:** add `backend/migrations/NNNN_name.sql` with the next unused
  number (four digits, never reuse or edit a shipped one; `0002` is
  intentionally absent). Prefer additive DDL.
- **WhatsApp** follow-ups are deep links the owner taps, never auto-sent.

## Coverage ratchets
Thresholds live in `backend/vitest.config.ts` and `tool/check_coverage.dart`,
set ~2 points under the measured baseline. If your PR raises coverage, bump
them; never lower them to get a PR through.

## Security
Report vulnerabilities privately as described in [`SECURITY.md`](SECURITY.md).
