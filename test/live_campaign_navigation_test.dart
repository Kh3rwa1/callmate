import 'package:callpilot/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Regression: navigating while the real mock dialer emits campaign events used
/// to throw "setState() or markNeedsBuild() called during build" from
/// HomeScreen (fixed upstream in flutter_riverpod 3.4). Uses the real dialer on
/// purpose; varying the first settle shifts where events land in the frame.
void main() {
  for (final frames in [1, 2, 5]) {
    appTest('navigating during a live campaign is safe (settle $frames)', (
      h,
    ) async {
      final b = h.backend;
      final ids = b.leads.values
          .where((l) => l.status == LeadStatus.newLead)
          .take(2)
          .map((l) => l.id)
          .toList();
      final c = b.createCampaign(
        CampaignDraft(leadIds: ids, purpose: 'Admissions'),
      );
      b.startCampaign(c.id);
      await h.settle(frames);
      await h.push('/campaigns/${c.id}');
      await h.settle(12);
      await h.go('/home');
      await h.push('/notifications');
      await h.settle(12);
      expect(h.location, '/notifications');
    });
  }
}
