# Riya AI – Admissions AI employee for coaching centres

> Your AI employee calls every lead, qualifies them, and prepares the perfect WhatsApp follow-up.

**Core loop:** Lead → AI call → AI understands → Lead score → Follow-up draft → Notification → WhatsApp opens → **you tap Send**.

## Run

```bash
flutter pub get
# Demo / mock mode (no backend needed – full journey works)
flutter run --dart-define-from-file=env/dev.json
# Staging / prod (real backend)
flutter run --dart-define-from-file=env/staging.json
flutter build apk --release --dart-define-from-file=env/prod.json
```

Mock mode activates automatically whenever `API_BASE_URL` is empty.

## Architecture

```
lib/
  core/        config (flavors), theme, routing (GoRouter), network (Dio), storage, utils, widgets (Mascot, cards, states)
  data/
    models/        normalised entities (Lead, Call, FollowUp, Campaign, Agent, Business, KnowledgeSource, Usage, Callback…)
    templates/     BusinessTemplate / AgentTemplate / WorkflowTemplate (Coaching = full V1)
    repositories/  interfaces (UI depends only on these)
    datasources/
      mock/        in-memory backend + simulated Sarvam webhook pipeline + seed data
      api/         Dio implementations of backend/API.md
  services/
    voice/       VoiceAgentService ← SarvamVoiceAgentService (sarvamconv_ai_sdk) | MockVoiceAgentService
    whatsapp/    WhatsAppService ← WhatsAppDeepLinkService (wa.me click-to-chat, no Business API)
    notifications/ NotificationService + PushProvider abstraction (FCM plugs in here)
    analytics/   PII-free analytics facade
  features/    onboarding, home, leads, calls, followups, agent, knowledge, campaign, callbacks, voice_test, notifications, usage, demo
backend/       API contract, agent template, structured-output JSON schema, .env.example
```

State: Riverpod 3. Navigation: GoRouter `StatefulShellRoute` with **exactly 5 tabs**: Home · Leads · Calls · Follow-ups · AI Employee.

## Security
- No Sarvam keys in the app. In-app voice uses `SamvaadAgent(baseUrl: <our proxy>, headers: {Authorization})` per Sarvam's proxy guidance.
- Outbound calls are placed by the backend, never from the phone.
- Only our own JWTs are stored (flutter_secure_storage). API logs print method/path/status only.
- Phone numbers normalised/validated (Indian defaults); CSV import sanitised (formula-injection, control chars, length caps, dedupe).
- Analytics strips name/phone/message/transcript keys.

## Mascot
Drop replacement art into `assets/mascot/` keeping file names:
`welcome, speaking, listening, thinking, calling, success, hot_lead, whatsapp, error` (.png, transparent, square).
The `Mascot` widget falls back to a vector silhouette if a file is missing.

## Demo tools
Home → 🧪 icon (or AI Employee → Demo controls): simulate hot lead, completed call, WhatsApp follow-up, campaign progress, notifications, replay onboarding.
