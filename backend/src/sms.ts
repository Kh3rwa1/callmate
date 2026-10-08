import { Env } from './types';
import { maskPhone, logInfo } from './utils/logger';

/** Upper bound for any SMS provider call so a hung provider cannot hold the request open. */
export const SMS_TIMEOUT_MS = 8000;

export interface SmsProvider {
  sendOtp(phone: string, otp: string): Promise<boolean>;
}

export class MockSmsProvider implements SmsProvider {
  constructor(private environment?: string) {}

  async sendOtp(phone: string, otp: string): Promise<boolean> {
    if (this.environment === 'production') {
      throw new Error('Security violation: MockSmsProvider cannot be used in production environment.');
    }
    logInfo('Mock SMS verification code dispatched', {
      phone: maskPhone(phone),
      event: 'mock_sms_dispatched',
    });
    return true;
  }
}

export class Msg91SmsProvider implements SmsProvider {
  constructor(private authKey: string, private templateId?: string) {}

  async sendOtp(phone: string, otp: string): Promise<boolean> {
    const digitsOnly = phone.replace(/\D/g, '');
    const res = await fetch('https://api.msg91.com/api/v5/otp', {
      method: 'POST',
      headers: {
        authkey: this.authKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        template_id: this.templateId || 'callpilot_otp',
        mobile: digitsOnly,
        otp: otp,
      }),
      signal: AbortSignal.timeout(SMS_TIMEOUT_MS),
    });
    return res.ok;
  }
}

export class GupshupSmsProvider implements SmsProvider {
  constructor(private apiKey: string, private appName?: string) {}

  async sendOtp(phone: string, otp: string): Promise<boolean> {
    const res = await fetch('https://api.gupshup.io/sm/api/v1/msg', {
      method: 'POST',
      headers: {
        apikey: this.apiKey,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        channel: 'sms',
        source: this.appName || 'CallPilot',
        destination: phone,
        message: `Your CallPilot verification code is: ${otp}`,
      }).toString(),
      signal: AbortSignal.timeout(SMS_TIMEOUT_MS),
    });
    return res.ok;
  }
}

export class ExotelSmsProvider implements SmsProvider {
  constructor(private sid: string, private token: string, private subdomain = 'api') {}

  async sendOtp(phone: string, otp: string): Promise<boolean> {
    const authHeader = btoa(`${this.sid}:${this.token}`);
    const res = await fetch(`https://${this.subdomain}.exotel.com/v1/Accounts/${this.sid}/Sms/send.json`, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${authHeader}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        From: 'CALLPT',
        To: phone,
        Body: `Your CallPilot verification code is: ${otp}`,
      }).toString(),
      signal: AbortSignal.timeout(SMS_TIMEOUT_MS),
    });
    return res.ok;
  }
}

export function getSmsProvider(env: Env): SmsProvider {
  const isProd = env.ENVIRONMENT === 'production';
  // Check for live providers in production or when configured
  const msg91Key = (env as any).MSG91_AUTH_KEY;
  if (msg91Key) {
    return new Msg91SmsProvider(msg91Key, (env as any).MSG91_TEMPLATE_ID);
  }

  const gupshupKey = (env as any).GUPSHUP_API_KEY;
  if (gupshupKey) {
    return new GupshupSmsProvider(gupshupKey, (env as any).GUPSHUP_APP_NAME);
  }

  const exotelSid = (env as any).EXOTEL_SID;
  const exotelToken = (env as any).EXOTEL_TOKEN;
  if (exotelSid && exotelToken) {
    return new ExotelSmsProvider(exotelSid, exotelToken);
  }

  if (isProd) {
    throw new Error('Production SMS provider is not configured. Set MSG91_AUTH_KEY, GUPSHUP_API_KEY, or EXOTEL credentials.');
  }

  return new MockSmsProvider(env.ENVIRONMENT);
}
