-- CallPilot Seed Data for Testing & Initial Demo

INSERT OR IGNORE INTO businesses (id, name, category, address, offerings, pricing, opening_hours, location, whatsapp_number, human_number, owner_name)
VALUES (
    'biz_demo',
    'ABC Coaching Centre',
    'coaching',
    '12 Park Street, Kolkata',
    '["NEET", "JEE Main", "WBJEE", "Class 10 Boards", "Class 12 Science"]',
    'NEET ₹52,000/yr · JEE ₹56,000/yr · Boards from ₹24,000/yr',
    'Mon–Sat, 9 AM – 8 PM',
    'Park Street, Kolkata',
    '+91 98300 12345',
    '+91 98300 54321',
    'Dulor'
);

INSERT OR IGNORE INTO agents (id, business_id, name, role, status, template_id, role_kind, skills, languages, goal, formality, capabilities, calling_hours_start, calling_hours_end, transfer_number, voice, calls_today)
VALUES (
    'agent_demo',
    'biz_demo',
    'Riya',
    'Admissions Assistant',
    'active',
    'coaching_admissions_v1',
    'admissions',
    '["admissions", "enquiryHandling", "bookAppointments"]',
    '["English", "Hindi", "Bengali"]',
    'Convert enquiries into counselling appointments',
    0.35,
    '["Calling", "Lead Qualification", "Follow-up", "Customer Questions", "Admissions Guidance", "Enquiry Handling", "Appointment Booking", "Callback Scheduling", "Hot Lead Alerts"]',
    10,
    19,
    '+91 98300 54321',
    'Friendly Female (Hindi/English)',
    0
);

INSERT OR IGNORE INTO users (id, phone, business_id)
VALUES (
    'user_demo',
    '919830012345',
    'biz_demo'
);

INSERT OR IGNORE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr)
VALUES (
    'usage_demo',
    'biz_demo',
    'Founding Plan',
    1000,
    datetime('now', '+30 days'),
    4999,
    642,
    110,
    6
);
