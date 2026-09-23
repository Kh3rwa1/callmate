# Callmate AI — Flutter client

A native Flutter app for Callmate AI: your AI employee calls customers, follows up
and books appointments. It talks only to the Callmate backend, which holds the
voice provider credentials and receives the provider's webhooks. No provider
secret ever ships inside this app.

## Important: this code is unverified

This Flutter project was generated in an environment without a Flutter/Dart
toolchain, so it has **not** been compiled, analysed, or run. Treat it as a
complete starting codebase: the structure, screens, models and API calls line up
with the backend's REST contract, but expect to fix small compile issues on your
first `flutter analyze`.

## Backend endpoints used

Base URL: `${SUPABASE_URL}/functions/v1/api`, authenticated with the Supabase
**anon** key (a public key — safe to ship in the app).

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `bootstrap` | All app data in one snapshot |
| GET | `phone-numbers` | The business's inbound number |
| GET | `ai-agent` | AI employee configuration |
| PATCH | `ai-agent` | Save AI employee configuration |
| POST | `calls/outbound` | Place a call |
| POST | `calls/complete` | Record a call's outcome |
| GET | `calls/transcript?id=` | Load a transcript on demand |
| POST | `campaigns` | Start a calling round |
| POST | `campaigns/step` | Advance a round by one call |
| POST | `campaigns/stop` | Stop a round |
| POST | `contacts` | Add a customer |
| PATCH | `contacts/detail` | Edit a customer |
| POST | `follow-ups/done` | Close a follow-up |

## Setup

1. Install Flutter (3.19+) and run `flutter pub get`.
2. Run the app, passing your Supabase project values:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Or create a `--dart-define-from-file=env.json` file:

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_ANON_KEY"
}
```

```bash
flutter run --dart-define-from-file=env.json
```

The anon key is public and safe to embed. Never put the voice provider's API key
in this app — it belongs only in the backend's environment.

## Project layout

```
lib/
  config/      environment + app configuration
  theme/       colours, typography and spacing tokens
  models/      data models mirroring the backend payload
  data/        API client and the app repository (state + refresh)
  widgets/     shared UI building blocks
  screens/     one file per screen
```

## Architecture notes

- **One source of truth.** All business data lives on the backend. The repository
  re-reads `bootstrap` after every change instead of patching a local copy, so the
  pipeline, dashboard and call history can never disagree.
- **No local outcome logic.** A call's result is recorded by the backend, which
  also moves the customer and opens any follow-up. The app never invents a result.
- **Transcripts are loaded on demand**, never bundled with the call list.
- **Failures are shown as plain language.** The API client converts every failure
  into a friendly `ApiException` message.
