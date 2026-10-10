import { defineConfig } from 'vitest/config';
import { cloudflareTest } from '@cloudflare/vitest-pool-workers';

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: './wrangler.toml' },
      // Tests must never call real Cloudflare services (e.g. the AI binding).
      remoteBindings: false,
      miniflare: {
        compatibilityFlags: ['nodejs_compat'],
        bindings: {
          ENVIRONMENT: 'development',
          JWT_SIGNING_KEY: 'test-jwt-signing-secret-key-32chars-min-length',
          SARVAM_WEBHOOK_SECRET: 'test_webhook_secret_12345',
          SARVAM_API_KEY: 'sk_test_mock_key_for_unit_tests',
          SARVAM_APP_VERSION: '1',
          SARVAM_CONNECTION_ID: 'conn_test',
          SARVAM_AGENT_PHONE_NUMBERS: '+910000000001',
          CF_AI_API_TOKEN: '',
          CF_ACCOUNT_ID: '',
          PUBLIC_API_BASE_URL: '',
          OTP_PEPPER: 'test-otp-pepper-secret-32chars-min-length',
          ENCRYPTION_KEY: 'test-encryption-key-32chars-min-length',
          // Tests seed 0-24 calling windows so they pass at any time of day; skips only the TRAI clamp.
          DEV_ALLOW_ANY_CALLING_HOURS: 'true',
        },
      },
    }),
  ],
  test: {
    coverage: {
      provider: 'istanbul',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.ts'],
      exclude: ['src/types.ts'],
      // Ratchet: ~2 points under the measured baseline (2026-10-10:
      // statements 89.18, branches 75.27, functions 92.53, lines 91.33).
      // Raise these when coverage improves; never lower them to land a PR.
      thresholds: {
        statements: 87,
        branches: 73,
        functions: 90,
        lines: 89,
        'src/auth.ts': {
          lines: 100,
        },
      },
    },
  },
});
