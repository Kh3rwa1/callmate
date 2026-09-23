import 'package:flutter/foundation.dart';

import '../models/bootstrap.dart';
import '../models/call.dart';
import '../models/campaign.dart';
import 'api_client.dart';

/// The app's single source of truth.
///
/// All business data lives on the backend. After any change we re-read the whole
/// snapshot instead of patching a local copy, so the pipeline, dashboard and call
/// history can never disagree with each other.
class AppRepository extends ChangeNotifier {
  AppRepository(this._api);

  final ApiClient _api;

  BootstrapData _data = BootstrapData.empty;
  bool _loading = false;
  String? _error;

  BootstrapData get data => _data;
  bool get isLoading => _loading;
  String? get error => _error;
  DashboardStats get stats => DashboardStats.compute(_data);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _data = await _api.bootstrap();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Runs a change against the backend and adopts the resulting state.
  ///
  /// If the change fails, its friendly message is surfaced and the original error
  /// is rethrown so the caller can react (e.g. keep a dialog open).
  Future<void> mutate(Future<void> Function() action) async {
    try {
      await action();
      _data = await _api.bootstrap();
      _error = null;
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  // --- AI employee ---------------------------------------------------------

  Future<void> updateAgent(Map<String, dynamic> patch) =>
      mutate(() => _api.updateAgent(patch));

  // --- Calls ---------------------------------------------------------------

  Future<String> startCall({String? contactId, String? phone}) =>
      _api.startOutboundCall(contactId: contactId, phone: phone);

  Future<void> completeCall({
    required String callId,
    required CallOutcome outcome,
    String? summary,
    String? insight,
    String? notes,
  }) =>
      mutate(() => _api.completeCall(
            callId: callId,
            outcome: outcome,
            summary: summary,
            insight: insight,
            notes: notes,
          ));

  Future<Transcript> transcript(String callId) => _api.transcript(callId);

  // --- Campaigns -----------------------------------------------------------

  Future<String> startCampaign(CampaignDraft draft) => _api.createCampaign(
        contactIds: draft.contactIds,
        purpose: draft.purpose,
        scheduledFor: draft.scheduledFor,
      );

  Future<void> advanceCampaign(String campaignId) =>
      mutate(() => _api.advanceCampaign(campaignId));

  Future<void> stopCampaign(String campaignId) =>
      mutate(() => _api.stopCampaign(campaignId));

  // --- Contacts ------------------------------------------------------------

  Future<void> createContact({
    required String name,
    required String phone,
    required String service,
  }) =>
      mutate(() => _api.createContact(name: name, phone: phone, service: service));

  Future<void> updateContact(
    String contactId, {
    String? name,
    String? phone,
    String? service,
    String? notes,
  }) =>
      mutate(() => _api.updateContact(
            contactId,
            name: name,
            phone: phone,
            service: service,
            notes: notes,
          ));

  // --- Follow-ups ----------------------------------------------------------

  Future<void> markFollowUpDone(String followUpId) =>
      mutate(() => _api.markFollowUpDone(followUpId));
}
