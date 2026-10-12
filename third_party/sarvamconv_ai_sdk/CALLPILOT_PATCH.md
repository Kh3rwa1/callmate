# Vendored sarvamconv_ai_sdk 1.0.2 (MIT)

Copied from pub.dev 1.0.2 (latest as of 2026-10-12) with one patch:

- `parseServerMessage` no longer throws on message types it doesn't parse.
  They come through as `ServerRawEvent` (raw JSON + type string), so newer
  server events such as `server.event.transcription` reach the app instead
  of being logged as "Unknown server message type" and dropped.

Drop this copy and go back to the pub.dev package once Sarvam ships a
version that understands transcription events.
