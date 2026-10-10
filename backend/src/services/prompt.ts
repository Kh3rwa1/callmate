import { playbookFor, playbookPromptBlock } from './playbooks';

export const ROLE_GOALS: Record<string, string> = {
  coaching: 'answer questions about courses, batches and fees, guide students to book a free demo class, and collect their standard/exam and target year.',
  clinic: 'answer questions about treatments and doctor availability, guide patients to book an appointment, and confirm whether it is an emergency.',
  real_estate: 'answer questions about properties, location and amenities, understand budget and configuration, and schedule a site visit.',
  retail: 'answer questions about product catalog, pricing, store hours and location, and assist with order placement.',
  salon: 'answer questions about services, prices and stylist availability, and book an appointment.',
  restaurant: 'answer questions about the menu, vegetarian options, pricing and hours, and help book a table.',
  automotive: 'answer questions about vehicle models, test drives, service bookings and pricing.',
  default: 'represent the business professionally, answer customer queries accurately based on the provided knowledge, and guide them toward the next best step.',
};

export interface PromptContext {
  agentName: string;
  agentRole: string;
  businessName: string;
  category?: string | null;
  knowledge?: string[];
}

export function buildSystemPrompt(ctx: PromptContext): string {
  const goal = ROLE_GOALS[ctx.category || 'default'] || ROLE_GOALS.default;
  const knowledgeBlock = (ctx.knowledge && ctx.knowledge.length > 0)
    ? `\n\nBUSINESS KNOWLEDGE (use these facts to answer questions accurately):\n${ctx.knowledge.map((k, i) => `[${i + 1}] ${k}`).join('\n')}`
    : '\n\nNo specific business knowledge uploaded yet. Answer politely and offer to have a representative call back for detailed questions.';

  return `You are ${ctx.agentName}, an AI ${ctx.agentRole} for ${ctx.businessName}.
Your primary goal is to: ${goal}

RULES:
1. Always stay in character as a representative of ${ctx.businessName}.
2. Use the provided BUSINESS KNOWLEDGE to answer questions. If the knowledge does not contain the answer, politely say you don't have that specific information and offer to connect them with the team.
3. Keep responses conversational, clear, and concise (1-3 sentences) suitable for spoken voice.
4. Support English, Hindi, and Hinglish naturally depending on the user's language.
5. Never invent or hallucinate pricing, dates, or policies not present in the knowledge.
6. If the user asks not to be contacted or asks to stop calling, apologize politely, confirm they will not be called again, and emit intent 'opt_out'.

${playbookPromptBlock(playbookFor(ctx.category))}${knowledgeBlock}`;
}

export async function loadHistory(
  db: D1Database,
  businessId: string,
  conversationId: string,
  limit = 10
): Promise<Array<{ role: 'user' | 'assistant'; content: string }>> {
  const { results } = await db.prepare(
    `SELECT role, content FROM chat_messages
     WHERE conversation_id = ? AND business_id = ?
     ORDER BY created_at DESC, rowid DESC LIMIT ?`
  ).bind(conversationId, businessId, limit).all<{ role: 'user' | 'assistant'; content: string }>();
  return (results ?? []).reverse();
}

export async function saveTurn(
  db: D1Database,
  businessId: string,
  conversationId: string,
  userMessage: string,
  assistantReply: string
): Promise<void> {
  const id1 = `msg_${crypto.randomUUID()}`;
  const id2 = `msg_${crypto.randomUUID()}`;
  await db.batch([
    db.prepare('INSERT INTO chat_messages (id, conversation_id, business_id, role, content) VALUES (?, ?, ?, ?, ?)')
      .bind(id1, conversationId, businessId, 'user', userMessage),
    db.prepare('INSERT INTO chat_messages (id, conversation_id, business_id, role, content) VALUES (?, ?, ?, ?, ?)')
      .bind(id2, conversationId, businessId, 'assistant', assistantReply),
  ]);
}
