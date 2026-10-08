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
          CF_AI_API_TOKEN: '',
          CF_ACCOUNT_ID: '',
          OTP_PEPPER: 'test-otp-pepper-secret-32chars-min-length',
          ENCRYPTION_KEY: 'test-encryption-key-32chars-min-length',
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
      thresholds: {
        lines: 80,
        'src/auth.ts': {
          lines: 100,
        },
      },
    },
  },
});
