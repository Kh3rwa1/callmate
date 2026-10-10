# CallPilot

**Your AI Calling Employee**

AI that calls, qualifies, and follows up for your business.

| Entity | Identifier / Value |
|---|---|
| Visible App Name | **CallPilot** |
| Android `applicationId` / `namespace` | `com.echoing.heights` |
| Dart Package (Internal) | `callpilot` |
| Platform | **Android** (minSdk 24, targetSdk 36) |

> CallPilot is the **product**. Owners hire **AI employees** inside it – e.g. *Maya · Sales Assistant*, *Riya · Admissions Assistant*, *Arjun · Appointment Assistant*. The bundled demo data (ABC Coaching Centre + Riya) represents an example coaching vertical tenant.

**Core Loop:** Lead → AI outbound call → conversation → AI analysis → lead score → next action → AI follow-up → notification → WhatsApp opens → **you tap Send**.

---

## Running the Application

### 1. Mock Mode (Fully Offline Demo)
Mock mode works 100% offline without backend dependencies:
```bash
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

### 2. Staging Environment (Cloudflare Worker)
```bash
flutter run --dart-define-from-file=env/staging.json
```

### Real calls (Sarvam)
See [`docs/SARVAM_SETUP.md`](docs/SARVAM_SETUP.md) for where the Sarvam agent,
caller IDs and API key are configured.

### 3. Production Release Build (Play Store App Bundle)
Needs `android/key.properties` (upload key), `android/app/google-services.json`
(Firebase: push + Crashlytics) and the real `API_BASE_URL` in `env/prod.json`.
The build fails closed if any is missing; a misconfigured app shows an error
screen instead of starting. CI builds this for you (see `RUNBOOK.md` §1.3).
```bash
flutter build appbundle --release \
  --dart-define-from-file=env/prod.json \
  --build-number=<increment every upload> \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols
```

---

## Security & Architectural Guarantees

- **Guaranteed No-Auto-Send:** WhatsApp interaction is strictly click-to-chat deep linking (`whatsapp://send`). Nothing is ever sent automatically without human review and tapping Send.
- **Fail-Closed Secrets:** Zero fallback defaults for secrets in code. Missing or short `JWT_SIGNING_KEY` (<32 chars) fails closed with HTTP 500.
- **Tenant Isolation:** Every backend query and Cloudflare R2 object key is strictly scoped by `business_id`.
- **Encrypted at Rest:** Call metadata and transcripts are encrypted at rest using AES-256-GCM via the Web Crypto API.
- **Hardened Webhooks:** Sarvam call webhooks require mandatory HMAC-SHA256 signature verification with constant-time equality and timestamp freshness checks.
- **Real OTP Verification:** OTPs are 6-digit random values with SHA-256 hash storage, 5-minute expiry, max 5 failed attempts lock, and per-phone/IP rate limits.
- **Single-Flight Refresh:** Flutter client coalesces concurrent 401 token refresh requests into a single in-flight refresh operation, and only ends the session when the server rejects the refresh token (never on a flaky network).
- **Crash Reporting:** Uncaught Flutter and platform errors go to Firebase Crashlytics after PII scrubbing (phones, emails, tokens).
- **No Cloud Backup of Sessions:** Android backup and device transfer are disabled for app data.

---

## Testing & Quality Assurance

```bash
# Flutter Suite (Unit, Providers, Repositories, Widget Tests)
flutter test

# Verify Code Formatting
dart format --output=none --set-exit-if-changed .

# Static Analysis
flutter analyze --fatal-infos

# Backend Suite (Vitest Workers Pool with Istanbul Coverage Gate ≥80%)
cd backend
npm run test:coverage
npm run test
```

---

## Directory Structure

```
lib/core       Config (brand, env), theme, routing, network (ApiClient), storage, utils, widgets
lib/data       Models, templates, repositories (interfaces), datasources/{mock,api}
lib/services   Voice (VoiceAgentService ← Sarvam | Mock), WhatsApp, notifications, crash reporting
lib/features   Splash, auth, onboarding, home, leads, calls, followups, agent, knowledge, campaign, callbacks, voice_test, usage
backend/       Cloudflare Worker (Hono), D1 SQLite migrations, R2 storage, Queues, Vitest suites
.github/       CI (lint, tests, coverage gates, release AAB), staging + production deploys
```
