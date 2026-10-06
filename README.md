# CallPilot

**Your AI Calling Employee**

AI that calls, qualifies, and follows up for your business.

| | |
|---|---|
| Visible app name | **CallPilot** |
| Android `applicationId` / `namespace` | `com.lexi.light` |
| iOS bundle identifier | `com.lexi.light` |
| Dart package (internal) | `callpilot` |

> CallPilot is the **product**. Owners hire **AI employees** inside it – e.g. *Maya · Sales Assistant*, *Riya · Admissions Assistant*, *Arjun · Appointment Assistant*.
> The bundled demo data (ABC Coaching Centre + Riya) is just one example tenant.

**Core loop:** Lead → AI call → conversation → AI analysis → lead score → next action → AI follow-up → notification → WhatsApp opens → **you tap Send**.

## Run

```bash
flutter pub get
flutter run --dart-define-from-file=env/dev.json        # mock mode – full journey works offline
flutter run --dart-define-from-file=env/staging.json    # real backend
flutter build apk --release --dart-define-from-file=env/prod.json
```

## Brand & configuration
- `lib/core/config/brand.dart` – `APP_NAME = "CallPilot"`, `APP_TAGLINE`, `APP_DESCRIPTION`. All visible branding reads from here.
- Employee name/role/voice/goal/skills come from the `Agent` – never hardcoded in UI (`employeeNameProvider`).
- Business vocabulary (interest label, human closer, custom lead fields, test-call hints) comes from the active template (`workflowProvider`).

## Templates (`lib/data/templates/templates.dart`)
`BusinessTemplate` → `AgentTemplate` + `WorkflowTemplate` for: Coaching Centre (tuned V1), Real Estate, Clinic, Diagnostic Centre, Automobile, Salon, Restaurant, Retail, Local Services, Other.
Leads are generic (`interest` + custom `attributes`); coaching's batch/budget are template attributes, not global fields.

## Mascot
`Mascot` = the CallPilot AI-workforce character (states: welcome, calling, speaking, listening, thinking, success, hot lead, WhatsApp, error).
`EmployeeMascot` adds a role badge from the employee's role (💼 sales, 📅 appointments, 💬 support, 📚 admissions, 🛎️ reception).
Assets: `assets/mascot/*.png`. App icon / splash use the CallPilot mark (`assets/icon/`), never a named employee.

## Architecture
```
lib/core       config (brand, flavors), theme, routing, network, storage, utils, widgets
lib/data       models, templates, repositories (interfaces), datasources/{mock,api}
lib/services   voice (VoiceAgentService ← Sarvam | Mock), whatsapp (deep link), notifications, analytics
lib/features   splash, onboarding, home, leads, calls, followups, agent, knowledge, campaign, callbacks, voice_test, notifications, usage, demo
backend/       API contract, templates, structured-output schema
```

## Guarantees
- WhatsApp V1 = click-to-chat deep link only. Nothing is sent automatically; UI says "WhatsApp opened" / "Ready to send".
- Sarvam lives behind `VoiceAgentService` + our backend proxy. No secrets in the app.
- Outbound calls: App → Backend → Sarvam Voice Agents → Telephony → Customer.
