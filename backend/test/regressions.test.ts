// backend/test/regressions.test.ts (pure-function tests; no harness needed)
import { describe, it, expect } from 'vitest';
import { billableMinutes } from '../src/services/billing';
import { isOptOutRequest } from '../src/services/compliance';
import { isAllowedSarvamPath } from '../src/services/sarvam_proxy_guard';
import { clampDelay, retryDelaySeconds } from '../src/services/campaign_queue';
import { toFtsQuery, chunkText } from '../src/services/knowledge';
import { isDevEnv } from '../src/utils/secrets';

const env = { SARVAM_ORG_ID: 'org_a', SARVAM_WORKSPACE_ID: 'ws_a', SARVAM_ADMISSIONS_APP_ID: 'app_a' } as any;

describe('billing', () => {
  it('never bills unanswered calls', () => {
    for (const s of ['no_answer', 'busy', 'failed', 'rejected']) expect(billableMinutes(s, 45).minutes).toBe(0);
  });
  it('never guesses a duration', () => {
    expect(billableMinutes('completed', undefined)).toEqual({ minutes: 0, seconds: 0, flagged: true });
  });
  it('rounds up connected calls', () => {
    expect(billableMinutes('completed', 61).minutes).toBe(2);
    expect(billableMinutes('completed', 0).minutes).toBe(0);
  });
});

describe('opt-out', () => {
  const said = (text: string) => ({ transcript: [{ role: 'user', text }] });
  it.each(['Please stop calling', "don't call me again", 'call mat karo', 'mujhe phone mat karna',
           'dobara call mat karna', 'कॉल मत करो', 'number hata do'])('detects "%s"', (t) => {
    expect(isOptOutRequest(said(t))).toBe(true);
  });
  it('ignores the agent saying the phrase', () => {
    expect(isOptOutRequest({ transcript: [{ role: 'agent', text: 'say stop calling anytime' }] })).toBe(false);
  });
  it('does not flag normal interest', () => {
    expect(isOptOutRequest(said('haan call karo kal subah'))).toBe(false);
  });
});

describe('sarvam proxy guard', () => {
  it('allows our app', () => expect(isAllowedSarvamPath('orgs/org_a/workspaces/ws_a/apps/app_a/sessions', env)).toBe(true));
  it('blocks foreign org', () => expect(isAllowedSarvamPath('orgs/org_evil/workspaces/ws_a/apps/app_a', env)).toBe(false));
  it('blocks foreign app', () => expect(isAllowedSarvamPath('orgs/org_a/workspaces/ws_a/apps/app_b', env)).toBe(false));
  it('blocks traversal', () => {
    expect(isAllowedSarvamPath('orgs/org_a/../org_evil', env)).toBe(false);
    expect(isAllowedSarvamPath('orgs/org_a/%2e%2e/x', env)).toBe(false);
  });
});

describe('queue helpers', () => {
  it('clamps to CF max delay', () => expect(clampDelay(24 * 3600)).toBe(12 * 3600));
  it('backs off', () => expect([1, 2, 3].map(retryDelaySeconds)).toEqual([60, 120, 240]));
});

describe('env + knowledge', () => {
  it('debug only in explicit dev', () => {
    expect(isDevEnv({})).toBe(false);
    expect(isDevEnv({ ENVIRONMENT: 'prod' })).toBe(false);
    expect(isDevEnv({ ENVIRONMENT: 'development' })).toBe(true);
  });
  it('sanitises FTS input', () => expect(toFtsQuery('fees? "DROP" OR *')).toBe('"fees" OR "drop" OR "or"'));
  it('chunks long text', () => expect(chunkText('a. '.repeat(1000)).length).toBeGreaterThan(1));
});
