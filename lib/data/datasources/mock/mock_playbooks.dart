import '../../models/models.dart';

/// Offline stand-in for `GET /playbooks/current` (demo + tests). English
/// only; the real content in three languages lives in
/// `backend/src/services/playbooks.ts`.
CallPlaybook mockPlaybookFor(Business business) {
  final vertical = playbookVerticalFor(business.category);
  final coaching = vertical == PlaybookVertical.education;
  return CallPlaybook(
    vertical: vertical,
    category: business.category.wire,
    name: _names[vertical]!,
    businessName: business.name,
    qualifyingQuestions: coaching
        ? const [
            'Which class or exam is the student preparing for, and for which year?',
            'Do they prefer online or classroom batches, and which timing suits them?',
            'Who decides on the admission – the student or a parent?',
            'Is the fee within their budget, or do they need instalments?',
            'When would they like to attend a free demo class?',
          ]
        : const [
            'What product or service are they interested in?',
            'What do they need it for, and by when?',
            'Do they have a budget in mind?',
            'Who else is involved in the decision?',
          ],
    readyToBuy: coaching
        ? 'Knows the course and batch they want, the decision-maker is on '
              'board, and they agree to a demo class or ask how to pay the fee.'
        : 'Has a clear need and timeline, the budget fits, and they ask for '
              'the next step (a quote, a visit or a booking).',
    objections: const [
      PlaybookObjection(
        objection: 'It is too expensive',
        hint:
            'Mention offers or options from the knowledge base; never '
            'invent prices.',
      ),
      PlaybookObjection(
        objection: 'I am busy right now',
        hint: 'Ask for a better time and schedule a call back.',
      ),
    ],
    followupTemplates: const {
      FollowupOutcome.hot:
          'Hi {name}, thanks for speaking with {business}! As discussed, '
          'here are the details for your next step. Reply here to confirm.',
      FollowupOutcome.warm:
          'Hi {name}, thanks for your interest in {business}. Sharing the '
          'details here – reply with any questions.',
      FollowupOutcome.callback:
          'Hi {name}, this is {business}. As you asked, we will call you '
          'back at the time you mentioned. Reply here if another time suits '
          'you better.',
      FollowupOutcome.notInterested:
          'Hi {name}, thanks for your time today. If you need anything '
          'later, just reply here and {business} will be happy to help.',
    },
    callbackHint: coaching
        ? 'Evenings, 5–8 pm, after school or college; weekends also work '
              'for parents.'
        : 'Weekdays, 11 am–1 pm or 4–7 pm; never before 9 am or after 9 pm.',
    callbackStartHour: coaching ? 17 : 16,
    callbackEndHour: coaching ? 20 : 19,
  );
}

const _names = {
  PlaybookVertical.education: 'Coaching & education',
  PlaybookVertical.healthcare: 'Clinic & healthcare',
  PlaybookVertical.realEstate: 'Real estate',
  PlaybookVertical.salon: 'Salon & spa',
  PlaybookVertical.fitness: 'Gym & fitness',
  PlaybookVertical.general: 'General',
};
