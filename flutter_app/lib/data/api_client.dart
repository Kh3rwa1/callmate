import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../models/bootstrap.dart';
import '../models/call.dart';
import '../models/contact.dart';

/// A failure with a message we can show the user as-is.
///
/// The backend already writes plain-language messages ("Your AI couldn't start
/// the call"), so this class simply carries them to the UI. Nothing raw is ever
/// displayed.
class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'server_error', this.status = 0});

  final String message;
  final String code;
  final int status;

  @override
  String toString() => message;
}

/// The only channel between the app and the outside world.
///
/// Every request goes to the Callmate backend, which holds the voice provider's
/// credentials and receives its webhooks. No provider secret is present here.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${Env.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (!Env.isConfigured) {
      throw const ApiException(
        'This app is not connected to a backend yet.',
        code: 'not_configured',
      );
    }

    final uri = Uri.parse('${Env.apiBaseUrl}/$path');
    late http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        'Your AI is taking longer than usual. Please try again.',
        code: 'timeout',
      );
    } catch (_) {
      throw const ApiException(
        "We couldn't reach your AI right now. Check your connection and try again.",
        code: 'network',
      );
    }

    Map<String, dynamic>? parsed;
    if (response.body.isNotEmpty) {
      try {
        parsed = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        parsed = null;
      }
    }

    if (response.statusCode >= 400) {
      final error = parsed?['error'] as Map<String, dynamic>?;
      throw ApiException(
        error?['message'] as String? ?? 'Something went wrong. Please try again.',
        code: error?['code'] as String? ?? 'server_error',
        status: response.statusCode,
      );
    }

    if (parsed == null) {
      throw const ApiException('We got an unexpected reply. Please try again.', code: 'bad_response');
    }
    return parsed;
  }

  Future<BootstrapData> bootstrap() async =>
      BootstrapData.fromJson(await _request('bootstrap'));

  Future<AiEmployee?> aiAgent() async {
    final payload = await _request('ai-agent');
    final agent = payload['agent'] as Map<String, dynamic>?;
    return agent == null ? null : AiEmployee.fromJson(agent);
  }

  Future<void> updateAgent(Map<String, dynamic> patch) async {
    await _request('ai-agent', method: 'PATCH', body: patch);
  }

  Future<PhoneNumbersPayload> phoneNumbers() async {
    final payload = await _request('phone-numbers');
    return PhoneNumbersPayload(
      phoneNumber: PhoneNumberInfo.fromJson(payload['phoneNumber'] as Map<String, dynamic>?),
      providerCount: (payload['providerNumbers'] as List<dynamic>? ?? const []).length,
    );
  }

  /// Places a call. The backend talks to the voice provider; we never do.
  Future<String> startOutboundCall({
    String? contactId,
    String? phone,
    String? campaignId,
  }) async {
    final payload = await _request('calls/outbound', method: 'POST', body: {
      if (contactId != null) 'contactId': contactId,
      if (phone != null) 'phone': phone,
      if (campaignId != null) 'campaignId': campaignId,
    });
    return payload['callId'] as String;
  }

  /// Records what happened on a call. The backend moves the customer and opens
  /// any follow-up, so the app never applies an outcome itself.
  Future<void> completeCall({
    required String callId,
    required CallOutcome outcome,
    String? summary,
    String? insight,
    String? appointmentDate,
    double? amountRecovered,
    String? notes,
  }) async {
    await _request('calls/complete', method: 'POST', body: {
      'callId': callId,
      'outcome': outcome.wire,
      if (summary != null) 'summary': summary,
      if (insight != null) 'insight': insight,
      if (appointmentDate != null) 'appointmentDate': appointmentDate,
      if (amountRecovered != null) 'amountRecovered': amountRecovered,
      if (notes != null) 'notes': notes,
    });
  }

  /// Transcripts are loaded only here, never bundled with the call list.
  Future<Transcript> transcript(String callId) async {
    final payload =
        await _request('calls/transcript?id=${Uri.encodeComponent(callId)}');
    return Transcript.fromJson(payload);
  }

  Future<String> createCampaign({
    required List<String> contactIds,
    required String purpose,
    DateTime? scheduledFor,
  }) async {
    final payload = await _request('campaigns', method: 'POST', body: {
      'contactIds': contactIds,
      'purpose': purpose,
      if (scheduledFor != null) 'scheduledFor': scheduledFor.toUtc().toIso8601String(),
    });
    return payload['campaignId'] as String;
  }

  /// Asks the backend to advance a round by one call. In mock mode the backend
  /// simulates the call; in live mode the provider places it and its webhook
  /// reports the result.
  Future<void> advanceCampaign(String campaignId) async {
    await _request('campaigns/step', method: 'POST', body: {'campaignId': campaignId});
  }

  Future<void> stopCampaign(String campaignId) async {
    await _request('campaigns/stop', method: 'POST', body: {'campaignId': campaignId});
  }

  Future<Contact> createContact({
    required String name,
    required String phone,
    required String service,
  }) async {
    final payload = await _request('contacts', method: 'POST', body: {
      'name': name,
      'phone': phone,
      'service': service,
    });
    return Contact.fromJson(
      payload['contact'] as Map<String, dynamic>,
      const [],
    );
  }

  Future<void> updateContact(
    String contactId, {
    String? name,
    String? phone,
    String? service,
    String? notes,
  }) async {
    await _request('contacts/detail', method: 'PATCH', body: {
      'contactId': contactId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (service != null) 'service': service,
      if (notes != null) 'notes': notes,
    });
  }

  Future<void> markFollowUpDone(String followUpId) async {
    await _request('follow-ups/done', method: 'POST', body: {'followUpId': followUpId});
  }
}

/// The phone-number screen's payload: the business's number plus how many numbers
/// the voice service has registered for it.
class PhoneNumbersPayload {
  const PhoneNumbersPayload({this.phoneNumber, this.providerCount = 0});

  final PhoneNumberInfo? phoneNumber;
  final int providerCount;
}
