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
  SARVAM_PROXY_BASE?: string;
  TELEPHONY_PROVIDER?: string;
  FCM_SERVICE_ACCOUNT_JSON?: string;
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
  exp: number; // unix timestamp in seconds
  iat: number;
}
