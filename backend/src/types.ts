export interface Env {
  DB: D1Database;
  KNOWLEDGE_BUCKET?: R2Bucket;
  ENVIRONMENT?: string;
  JWT_SIGNING_KEY?: string;
  SARVAM_API_KEY?: string;
  SARVAM_ORG_ID?: string;
  SARVAM_WORKSPACE_ID?: string;
  SARVAM_ADMISSIONS_APP_ID?: string;
  SARVAM_WEBHOOK_SECRET?: string;
  /** Committed version of the Sarvam agent to dial with. */
  SARVAM_APP_VERSION?: string;
  /** Sarvam telephony connection that owns the caller IDs. */
  SARVAM_CONNECTION_ID?: string;
  /** Comma-separated caller IDs (E.164, as onboarded in Sarvam); one is picked per dial. */
  SARVAM_AGENT_PHONE_NUMBERS?: string;
  /**
   * Comma-separated agent_variables to send on outbound dials (see services/call_variables.ts).
   * Unset = the 8 the Sarvam agent declares. Every name must be declared in the agent version.
   */
  SARVAM_AGENT_VARIABLES?: string;
  /**
   * 'true' = every dial sends app_overrides.initial_bot_message with the AI + recording disclosure
   * (services/disclosure.ts). Unset/anything else = off.
   */
  SARVAM_DISCLOSURE_OVERRIDE?: string;
  /** Days to keep call transcripts, recordings and summaries (default 180). */
  RETENTION_DAYS?: string;
  /** Secret: incoming-webhook URL (Slack/Discord/Google Chat) for ops alerts. */
  ALERT_WEBHOOK_URL?: string;
  SARVAM_PROXY_BASE?: string;
  TELEPHONY_PROVIDER?: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
  AI?: any;
  CF_ACCOUNT_ID?: string;
  CF_AI_API_TOKEN?: string;
  CAMPAIGN_QUEUE?: Queue<any>;
  ENCRYPTION_KEY?: string;
  OTP_PEPPER?: string;
  ALLOWED_ORIGINS?: string;
  /** Secret: comma-separated account emails exempt from the voice test-session cap (QA). */
  VOICE_UNLIMITED_EMAILS?: string;
  HEALTH_CHECK_SECRET?: string;
  /** Firebase project whose Auth ID tokens /auth/google accepts. */
  FIREBASE_PROJECT_ID?: string;
  /** Public origin of this worker (e.g. https://api.example.com), used for Sarvam webhook_config on queued dials. */
  PUBLIC_API_BASE_URL?: string;
  /** Free-trial minutes for a first-time signup (default 30). */
  TRIAL_MINUTES?: string;
  /** Razorpay API key id/secret (secrets). Missing = checkout returns 503 billing_not_configured. */
  RAZORPAY_KEY_ID?: string;
  RAZORPAY_KEY_SECRET?: string;
  /** Secret configured on the Razorpay dashboard webhook; verifies X-Razorpay-Signature. */
  RAZORPAY_WEBHOOK_SECRET?: string;
  /** Optional URL Razorpay redirects to after payment. */
  BILLING_RETURN_URL?: string;
  /** Dev/test only: 'true' skips the TRAI 09:00-21:00 clamp so tests can dial at any time of day. */
  DEV_ALLOW_ANY_CALLING_HOURS?: string;
  /** Contact address shown on the public legal pages. */
  SUPPORT_EMAIL?: string;
  /** Legal entity named on the public legal pages. */
  LEGAL_ENTITY_NAME?: string;
}

export interface AuthUser {
  id: string;
  phone: string;
  business_id: string;
}

export interface JWTPayload {
  sub: string; // user id
  phone: string;
  business_id: string;
  type: 'access' | 'refresh' | 'session';
  iss?: string;
  aud?: string;
  jti?: string;
  exp: number; // unix timestamp in seconds
  iat: number;
}
