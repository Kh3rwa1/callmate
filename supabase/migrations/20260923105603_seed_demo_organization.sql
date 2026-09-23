/*
# Seed the demo organization

## What this does
Creates one tenant ("org_demo" — Sunrise Dental Clinic) together with its AI
employee, inbound phone number, usage/plan row, 18 customers, their call
history (including three missed inbound calls), timelines and follow-up queue.
The values mirror the demo data the app previously kept in memory, so the
screens look identical while now being backed by the real database.

## Why a organisation row exists at all
Sarvam configuration is per tenant, never global. Each organization owns its own
Sarvam org/workspace/deployment ids, phone number, agent configuration,
contacts, campaigns, calls and usage. The backend scopes every query by
`organization_id`, so one tenant can never read another tenant's voice data.

## Notes
1. Idempotent: every statement is an upsert or guarded by NOT EXISTS, so a lost
   response can be re-applied safely with the same filename.
2. `voice_mode` starts as 'mock' so the app is fully usable before real Sarvam
   credentials are added. Switching it to 'sarvam' turns on the live integration.
3. The Sarvam identifiers are intentionally NULL here. They are tenant
   configuration and must be filled from the real dashboard values — nothing is
   hardcoded in the application.
4. No destructive statements.
*/

INSERT INTO organizations (id, name, sarvam_org_id, sarvam_workspace_id, sarvam_deployment_id, sarvam_app_version, voice_mode)
VALUES ('org_demo', 'Sunrise Dental Clinic', NULL, NULL, NULL, 1, 'mock')
ON CONFLICT (id) DO NOTHING;

INSERT INTO ai_agents (organization_id, name, language, voice, call_style, working_hours_start, working_hours_end, follow_up_enabled, follow_up_delay_days, greeting, inbound_enabled)
VALUES ('org_demo', 'Shampy', 'Hindi', 'Anushka', 'Friendly', '09:00', '19:00', true, 1,
        'Namaste! Main Sunrise Dental Clinic se Shampy bol rahi hoon.', true)
ON CONFLICT (organization_id) DO NOTHING;

INSERT INTO phone_numbers (id, organization_id, number, connection_id, inbound_enabled, callback_on_missed, ring_before_pickup, status)
SELECT 'pn_demo', 'org_demo', '+91 98300 41022', NULL, true, true, 3, 'connected'
WHERE NOT EXISTS (SELECT 1 FROM phone_numbers WHERE id = 'pn_demo');

INSERT INTO org_usage (organization_id, minutes_used, calls_made, plan_name, price_per_month, renews_at, cycle_started_at, credits_remaining)
SELECT 'org_demo', 412, 268, 'Growth', 2999, (now() + interval '12 days')::date, now()::date, 288
WHERE NOT EXISTS (SELECT 1 FROM org_usage WHERE organization_id = 'org_demo');

WITH seed (id, name, phone, service, status, last_call_min, last_outcome, fu_days, fu_type, fu_msg,
           appt_days, appt_time, appt_service, tags, notes, recovered, days_ago, summary, insight) AS (
  VALUES
  ('c1','Riya Das','+91 98301 22456','Dental consultation','booked',-42,'Appointment booked',NULL,NULL,NULL,
   1,'16:00','Dental consultation',ARRAY['Interested','Appointment'],
   'Prefers evening slots. Asked about EMI options.',NULL,12,
   'Wants a cleaning and check-up before the wedding season.','Customer is interested'),
  ('c2','Amit Roy','+91 90071 55320','Appointment','calling',-3,NULL,NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['Live now'],'Second attempt today.',NULL,9,
   'Asked for the price list last week.','Price is the main question'),
  ('c3','Sima Murmu','+91 88201 47863','Follow-up','followUp',-120,'No answer',0,'whatsapp',
   'Tried calling you twice today. When is a good time?',NULL,NULL,NULL,ARRAY['Follow-up'],
   'Usually picks up after 6 PM.',NULL,6,'No answer on two attempts.','Best time to reach her is evening'),
  ('c4','Rahul Das','+91 97480 11290','Root canal','booked',-300,'Appointment booked',NULL,NULL,NULL,
   2,'11:30','Root canal',ARRAY['Booked','High value'],'Referred by Riya Das.',NULL,4,
   'Booking confirmed for a root canal.','Ready to book'),
  ('c5','Priya Singh','+91 99324 66107','Coaching demo','recovered',-420,'Payment recovered',NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['Recovered'],'Paid the pending fee on the call.',7500,20,
   'Cleared the pending fee of Rs 7,500.','Payment collected on call'),
  ('c6','Ankit Sharma','+91 70421 99834','New lead','new',NULL,NULL,NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['New lead'],'Enquiry came from the website form.',NULL,1,
   'Waiting for the first call.',''),
  ('c7','Moumita Roy','+91 90738 22140','Dental consultation','followUp',-1800,'Follow-up needed',1,'call',
   'Call to confirm the date she prefers.',NULL,NULL,NULL,ARRAY['Interested'],
   'Wants a weekend slot.',NULL,8,'Interested but needs to confirm with family.','Warm lead'),
  ('c8','Sanjay Kumar','+91 98311 78820','Daycare booking','notInterested',-3120,'Not interested',NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['Closed'],'Went with another clinic closer to home.',NULL,16,
   'Not interested for now.',''),
  ('c9','Farhan Ahmed','+91 89610 44572','Appointment','booked',-1560,'Appointment booked',NULL,NULL,NULL,
   3,'10:00','Dental consultation',ARRAY['Booked'],'Morning slot requested.',NULL,5,
   'Appointment booked for Thursday morning.','Confirmed'),
  ('c10','Neha Gupta','+91 97001 33628','Skin check-up','followUp',-3000,'Follow-up needed',2,'whatsapp',
   'Share the skin package prices on WhatsApp.',NULL,NULL,NULL,ARRAY['Price enquiry'],
   'Wants packages before deciding.',NULL,11,'Asked for package pricing.','Send price list'),
  ('c11','Vikram Nair','+91 90211 66275','Payment reminder','recovered',-1200,'Payment recovered',NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['Recovered'],'Pending amount collected over UPI.',12000,25,
   'Collected Rs 12,000 that was pending for 3 weeks.','Payment collected'),
  ('c12','Sneha Patel','+91 88790 55219','Coaching demo','noResponse',-4320,'No answer',3,'call',
   'Try once more in the evening.',NULL,NULL,NULL,ARRAY['No answer'],
   'Two attempts, no answer.',NULL,13,'No response on both attempts.',''),
  ('c13','Arjun Mehta','+91 99540 12007','Site visit','followUp',-2400,'Interested',4,'call',
   'Confirm the weekend site visit.',NULL,NULL,NULL,ARRAY['Site visit'],
   'Looking at 2BHK options.',NULL,7,'Wants to visit the site this weekend.','High intent'),
  ('c14','Divya Rao','+91 90360 77341','Salon appointment','booked',-540,'Appointment booked',NULL,NULL,NULL,
   0,'18:30','Bridal trial',ARRAY['Booked','Today'],'Bridal trial this evening.',NULL,3,
   'Booked for a bridal trial today.','Confirmed for today'),
  ('c15','Kabir Sen','+91 89024 33186','New lead','calling',-2,NULL,NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['Live now'],'First call in progress.',NULL,0,
   'First conversation happening now.','Brand new lead'),
  ('c16','Pooja Iyer','+91 98456 22013','Table booking','recovered',-2880,'Payment recovered',NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['Recovered'],'Advance payment collected.',5000,22,
   'Advance of Rs 5,000 collected.','Recovered'),
  ('c17','Rohan Bhatt','+91 90876 55410','Coaching demo','noResponse',-5760,'No answer',1,'whatsapp',
   'Send the demo class link on WhatsApp.',NULL,NULL,NULL,ARRAY['No answer'],
   'Prefers WhatsApp.',NULL,18,'Did not pick up.',''),
  ('c18','Aisha Khan','+91 97068 41232','Dental consultation','new',NULL,NULL,NULL,NULL,NULL,
   NULL,NULL,NULL,ARRAY['New lead'],'Walk-in enquiry, added by the front desk.',NULL,0,
   'Not called yet.','')
)
INSERT INTO contacts (id, organization_id, name, phone, avatar_color, service, status, last_call_at,
                      last_call_outcome, next_follow_up_at, appointment, tags, notes, recovered_amount,
                      source, created_at)
SELECT
  s.id, 'org_demo', s.name, s.phone,
  (ARRAY['#18C97A','#4C7DFF','#8B5CF6','#FF9F43','#FF6B6B','#22B8CF'])[1 + ((right(s.id, length(s.id) - 1))::int - 1) % 6],
  s.service, s.status,
  CASE WHEN s.last_call_min IS NULL THEN NULL ELSE now() + (s.last_call_min * interval '1 minute') END,
  s.last_outcome,
  CASE WHEN s.fu_days IS NULL THEN NULL
       ELSE now() + (s.fu_days * interval '1 day') + interval '10 hours' END,
  CASE WHEN s.appt_days IS NULL THEN NULL
       ELSE jsonb_build_object(
         'date', to_char(now() + (s.appt_days * interval '1 day'), 'YYYY-MM-DD'),
         'time', s.appt_time, 'service', s.appt_service, 'status', 'scheduled') END,
  s.tags, s.notes, s.recovered, 'manual',
  now() - (s.days_ago * interval '1 day')
FROM seed s
ON CONFLICT (id) DO NOTHING;

-- Timelines: creation, then the call, its outcome, and any appointment.
INSERT INTO contact_timeline (id, organization_id, contact_id, label, detail, kind, at)
SELECT c.id || '_created', 'org_demo', c.id, 'Added to Callmate', NULL, 'created', c.created_at
FROM contacts c WHERE c.organization_id = 'org_demo'
ON CONFLICT (id) DO NOTHING;

INSERT INTO contact_timeline (id, organization_id, contact_id, label, detail, kind, at)
SELECT c.id || '_call', 'org_demo', c.id, 'Shampy called', NULL, 'call', c.last_call_at
FROM contacts c WHERE c.organization_id = 'org_demo' AND c.last_call_at IS NOT NULL
ON CONFLICT (id) DO NOTHING;

INSERT INTO contact_timeline (id, organization_id, contact_id, label, detail, kind, at)
SELECT c.id || '_outcome', 'org_demo', c.id, c.last_call_outcome, NULL, 'status', c.last_call_at
FROM contacts c WHERE c.organization_id = 'org_demo' AND c.last_call_outcome IS NOT NULL
ON CONFLICT (id) DO NOTHING;

INSERT INTO contact_timeline (id, organization_id, contact_id, label, detail, kind, at)
SELECT c.id || '_appt', 'org_demo', c.id, 'Appointment booked',
       (c.appointment->>'service') || ' at ' || (c.appointment->>'time'), 'appointment', now() - interval '8 hours'
FROM contacts c WHERE c.organization_id = 'org_demo' AND c.appointment IS NOT NULL
ON CONFLICT (id) DO NOTHING;

-- Call history: one call per customer that has been called.
INSERT INTO calls (id, organization_id, contact_id, direction, status, outcome, started_at, ended_at,
                   duration_seconds, summary, insight, deployment_id, agent_version)
SELECT
  'call_' || right(c.id, length(c.id) - 1), 'org_demo', c.id, 'outbound',
  CASE WHEN c.status = 'calling' THEN 'calling' ELSE 'completed' END,
  CASE WHEN c.status = 'calling' THEN NULL ELSE c.last_call_outcome END,
  c.last_call_at,
  CASE WHEN c.status = 'calling' THEN NULL ELSE c.last_call_at + interval '142 seconds' END,
  CASE WHEN c.status = 'calling' THEN 0 ELSE 142 END,
  coalesce((SELECT t.detail FROM contact_timeline t
            WHERE t.id = c.id || '_call' AND t.detail IS NOT NULL LIMIT 1), ''),
  '', NULL, NULL
FROM contacts c
WHERE c.organization_id = 'org_demo' AND c.last_call_at IS NOT NULL
ON CONFLICT (id) DO NOTHING;

-- A few missed inbound calls so every filter on the Calls screen has content.
INSERT INTO calls (id, organization_id, contact_id, direction, status, outcome, started_at, ended_at,
                   duration_seconds, summary, insight)
SELECT 'call_missed_' || v.n, 'org_demo', v.contact_id, 'inbound', 'missed', 'noResponse',
       now() - v.offset_min * interval '1 minute',
       now() - v.offset_min * interval '1 minute' + interval '12 seconds', 0,
       'Inbound call missed. Shampy will call back.', ''
FROM (VALUES (1,'c3',1440),(2,'c8',360),(3,'c12',2880)) AS v(n, contact_id, offset_min)
WHERE NOT EXISTS (SELECT 1 FROM calls WHERE id = 'call_missed_' || v.n);

-- Follow-up queue
INSERT INTO follow_ups (id, organization_id, contact_id, date_time, type, status, message)
SELECT 'f' || right(c.id, length(c.id) - 1), 'org_demo', c.id, c.next_follow_up_at,
       CASE WHEN c.next_follow_up_at IS NOT NULL THEN 'call' ELSE 'call' END,
       'pending',
       'Follow up with ' || split_part(c.name, ' ', 1) || '.'
FROM contacts c
WHERE c.organization_id = 'org_demo' AND c.next_follow_up_at IS NOT NULL
ON CONFLICT (id) DO NOTHING;

UPDATE follow_ups f
SET type = CASE
  WHEN f.contact_id IN ('c3','c10','c17') THEN 'whatsapp'
  ELSE 'call' END,
  message = CASE f.contact_id
    WHEN 'c3'  THEN 'Tried calling you twice today. When is a good time?'
    WHEN 'c7'  THEN 'Call to confirm the date she prefers.'
    WHEN 'c10' THEN 'Share the skin package prices on WhatsApp.'
    WHEN 'c12' THEN 'Try once more in the evening.'
    WHEN 'c13' THEN 'Confirm the weekend site visit.'
    WHEN 'c17' THEN 'Send the demo class link on WhatsApp.'
    ELSE f.message END
WHERE f.organization_id = 'org_demo';
