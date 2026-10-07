import { Env } from '../types';

/**
 * Only allow proxying to OUR org/workspace/app. Rejects path traversal and encoded tricks.
 * `path` = the part after /voice/sarvam-proxy/
 */
export function isAllowedSarvamPath(path: string, env: Pick<Env, 'SARVAM_ORG_ID' | 'SARVAM_WORKSPACE_ID' | 'SARVAM_ADMISSIONS_APP_ID'>): boolean {
  let decoded: string;
  try { decoded = decodeURIComponent(path); } catch { return false; }
  if (decoded.includes('..') || decoded.includes('\\') || /%2e|%2f/i.test(path)) return false;

  const segs = decoded.split('/').filter(Boolean);
  const valueAfter = (key: string) => {
    const i = segs.indexOf(key);
    return i >= 0 ? segs[i + 1] : undefined;
  };

  const org = valueAfter('orgs');
  const ws = valueAfter('workspaces');
  const app = valueAfter('apps');

  if (!env.SARVAM_ORG_ID || !env.SARVAM_WORKSPACE_ID) return false;
  if (org !== env.SARVAM_ORG_ID) return false;
  if (ws !== undefined && ws !== env.SARVAM_WORKSPACE_ID) return false;
  if (app !== undefined && app !== env.SARVAM_ADMISSIONS_APP_ID) return false;
  return true;
}
