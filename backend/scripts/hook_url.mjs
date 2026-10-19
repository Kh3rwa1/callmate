// Prints the on-start hook URL for one business number's Sarvam agent (docs/SARVAM_SETUP.md).
//   INBOUND_HOOK_SECRET=… node scripts/hook_url.mjs https://callpilot-backend.dulalkisku0.workers.dev +917971443028
import { createHmac } from 'node:crypto';

const [base, number] = process.argv.slice(2);
const secret = process.env.INBOUND_HOOK_SECRET;
if (!base || !/^\+\d{11,15}$/.test(number || '') || !secret) {
  console.error('usage: INBOUND_HOOK_SECRET=… node scripts/hook_url.mjs <PUBLIC_API_BASE_URL> <+91… number>');
  process.exit(1);
}
const token = createHmac('sha256', secret).update(`hook:${number}`).digest('hex');
console.log(`${base.replace(/\/$/, '')}/voice/inbound/start?number=${encodeURIComponent(number)}&token=${token}`);
