// Prints the on-start hook URL for a receptionist agent (docs/SARVAM_SETUP.md).
//
// Receptionist pool agent (answers whichever number it is given):
//   node scripts/hook_url.mjs https://callpilot-backend.dulalkisku0.workers.dev --agent <agent id> <version>
//   → a new random token, the hook URL to paste into the agent's load_business tool, and the
//     SARVAM_RECEPTIONIST_AGENTS entry "<agent id>:<version>:<sha256 of the token>" for wrangler.toml.
//
// One number's own agent (older SARVAM_BUSINESS_NUMBERS setup):
//   INBOUND_HOOK_SECRET=… node scripts/hook_url.mjs https://callpilot-backend.dulalkisku0.workers.dev +917971443028
import { createHash, createHmac, randomBytes } from 'node:crypto';

const [base, second, agentId, version] = process.argv.slice(2);
const root = (base || '').replace(/\/$/, '');

if (second === '--agent') {
  if (!root || !/^[^:\s,]+$/.test(agentId || '') || !/^[1-9]\d*$/.test(version || '')) {
    console.error('usage: node scripts/hook_url.mjs <PUBLIC_API_BASE_URL> --agent <agent id> <version>');
    process.exit(1);
  }
  const token = randomBytes(24).toString('hex');
  const hash = createHash('sha256').update(token).digest('hex');
  console.log(`hook URL:  ${root}/voice/inbound/start?agent=${encodeURIComponent(agentId)}&token=${token}`);
  console.log(`SARVAM_RECEPTIONIST_AGENTS entry:  ${agentId}:${version}:${hash}`);
  process.exit(0);
}

const number = second;
const secret = process.env.INBOUND_HOOK_SECRET;
if (!root || !/^\+\d{11,15}$/.test(number || '') || !secret) {
  console.error('usage: INBOUND_HOOK_SECRET=… node scripts/hook_url.mjs <PUBLIC_API_BASE_URL> <+91… number>');
  console.error('   or: node scripts/hook_url.mjs <PUBLIC_API_BASE_URL> --agent <agent id> <version>');
  process.exit(1);
}
const token = createHmac('sha256', secret).update(`hook:${number}`).digest('hex');
console.log(`${root}/voice/inbound/start?number=${encodeURIComponent(number)}&token=${token}`);
