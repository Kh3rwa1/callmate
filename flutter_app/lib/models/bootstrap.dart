import 'call.dart';
import 'campaign.dart';
import 'contact.dart';
import 'follow_up.dart';

/// The AI employee's configuration, as held by the backend.
class AiEmployee {
  const AiEmployee({
    required this.name,
    required this.language,
    required this.voice,
    required this.callStyle,
    required this.workingHoursStart,
    required this.workingHoursEnd,
    required this.followUpEnabled,
    required this.inboundEnabled,
    this.greeting,
  });

  final String name;
  final String language;
  final String voice;
  final String callStyle;
  final String workingHoursStart;
  final String workingHoursEnd;
  final bool followUpEnabled;
  final bool inboundEnabled;
  final String? greeting;

  static AiEmployee fromJson(Map<String, dynamic> json) => AiEmployee(
        name: json['name'] as String? ?? 'Shampy',
        language: json['language'] as String? ?? 'english',
        voice: json['voice'] as String? ?? 'anushka',
        callStyle: json['call_style'] as String? ?? 'friendly',
        workingHoursStart: json['working_hours_start'] as String? ?? '09:00',
        workingHoursEnd: json['working_hours_end'] as String? ?? '19:00',
        followUpEnabled: json['follow_up_enabled'] as bool? ?? true,
        inboundEnabled: json['inbound_enabled'] as bool? ?? true,
        greeting: json['greeting'] as String?,
      );
}

/// The business's inbound number.
class PhoneNumberInfo {
  const PhoneNumberInfo({
    required this.number,
    required this.inboundEnabled,
    required this.callbackOnMissed,
    required this.ringBeforePickup,
    required this.status,
  });

  final String number;
  final bool inboundEnabled;
  final bool callbackOnMissed;
  final int ringBeforePickup;
  final String status;

  static PhoneNumberInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return PhoneNumberInfo(
      number: json['number'] as String? ?? '',
      inboundEnabled: json['inbound_enabled'] as bool? ?? true,
      callbackOnMissed: json['callback_on_missed'] as bool? ?? true,
      ringBeforePickup: json['ring_before_pickup'] as int? ?? 3,
      status: json['status'] as String? ?? 'connected',
    );
  }
}

class UsageInfo {
  const UsageInfo({
    required this.minutesUsed,
    required this.callsMade,
    required this.planName,
    required this.pricePerMonth,
    this.renewsAt,
    this.cycleStartedAt,
    required this.creditsRemaining,
  });

  final int minutesUsed;
  final int callsMade;
  final String planName;
  final double pricePerMonth;
  final DateTime? renewsAt;
  final DateTime? cycleStartedAt;
  final int creditsRemaining;

  static UsageInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return UsageInfo(
      minutesUsed: (json['minutes_used'] as num?)?.toInt() ?? 0,
      callsMade: json['calls_made'] as int? ?? 0,
      planName: json['plan_name'] as String? ?? 'Growth',
      pricePerMonth: (json['price_per_month'] as num?)?.toDouble() ?? 0,
      renewsAt: DateTime.tryParse(json['renews_at'] as String? ?? '')?.toLocal(),
      cycleStartedAt: DateTime.tryParse(json['cycle_started_at'] as String? ?? '')?.toLocal(),
      creditsRemaining: json['credits_remaining'] as int? ?? 0,
    );
  }
}

class Organisation {
  const Organisation({required this.id, required this.name, required this.voiceMode});

  final String id;
  final String name;
  final String voiceMode;

  static Organisation fromJson(Map<String, dynamic> json) => Organisation(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Your business',
        voiceMode: json['voiceMode'] as String? ?? 'mock',
      );
}

/// One complete snapshot of everything the app shows. Keeping it in a single
/// object is what lets the app re-read all state after any change.
class BootstrapData {
  const BootstrapData({
    required this.organisation,
    this.phoneNumber,
    this.agent,
    this.usage,
    required this.contacts,
    required this.calls,
    required this.followUps,
    required this.campaigns,
  });

  final Organisation organisation;
  final PhoneNumberInfo? phoneNumber;
  final AiEmployee? agent;
  final UsageInfo? usage;
  final List<Contact> contacts;
  final List<Call> calls;
  final List<FollowUp> followUps;
  final List<Campaign> campaigns;

  static const BootstrapData empty = BootstrapData(
    organisation: Organisation(id: '', name: 'Your business', voiceMode: 'mock'),
    contacts: [],
    calls: [],
    followUps: [],
    campaigns: [],
  );

  Contact? contactById(String id) {
    for (final contact in contacts) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  Call? callById(String id) {
    for (final call in calls) {
      if (call.id == id) return call;
    }
    return null;
  }

  Campaign? campaignById(String id) {
    for (final campaign in campaigns) {
      if (campaign.id == id) return campaign;
    }
    return null;
  }

  List<Call> callsForCampaign(String campaignId) =>
      calls.where((c) => c.campaignId == campaignId).toList();

  List<FollowUp> get pendingFollowUps =>
      followUps.where((f) => f.isPending).toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  static BootstrapData fromJson(Map<String, dynamic> json) {
    final timelineRaw = json['timeline'] as Map<String, dynamic>? ?? const {};
    final campaignContacts = json['campaignContacts'] as Map<String, dynamic>? ?? const {};

    return BootstrapData(
      organisation:
          Organisation.fromJson(json['organization'] as Map<String, dynamic>? ?? const {}),
      phoneNumber: PhoneNumberInfo.fromJson(json['phoneNumber'] as Map<String, dynamic>?),
      agent: json['agent'] == null
          ? null
          : AiEmployee.fromJson(json['agent'] as Map<String, dynamic>),
      usage: UsageInfo.fromJson(json['usage'] as Map<String, dynamic>?),
      contacts: (json['contacts'] as List<dynamic>? ?? const []).map((raw) {
        final row = raw as Map<String, dynamic>;
        final entries = (timelineRaw[row['id']] as List<dynamic>? ?? const [])
            .map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        return Contact.fromJson(row, entries);
      }).toList(),
      calls: (json['calls'] as List<dynamic>? ?? const [])
          .map((raw) => Call.fromJson(raw as Map<String, dynamic>))
          .toList(),
      followUps: (json['followUps'] as List<dynamic>? ?? const [])
          .map((raw) => FollowUp.fromJson(raw as Map<String, dynamic>))
          .toList(),
      campaigns: (json['campaigns'] as List<dynamic>? ?? const []).map((raw) {
        final row = raw as Map<String, dynamic>;
        final ids = (campaignContacts[row['id']] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList();
        return Campaign.fromJson(row, ids);
      }).toList(),
    );
  }
}

/// Numbers derived from the data, never stored, so they cannot go stale.
class DashboardStats {
  const DashboardStats({
    required this.totalCalls,
    required this.bookedCount,
    required this.recoveredAmount,
    required this.activeCalls,
  });

  final int totalCalls;
  final int bookedCount;
  final double recoveredAmount;
  final int activeCalls;

  static DashboardStats compute(BootstrapData data) {
    var recovered = 0.0;
    for (final contact in data.contacts) {
      recovered += contact.recoveredAmount ?? 0;
    }
    return DashboardStats(
      totalCalls: data.calls.length,
      bookedCount: data.contacts.where((c) => c.status == ContactStatus.booked).length,
      recoveredAmount: recovered,
      activeCalls: data.calls.where((c) => c.isLive).length,
    );
  }
}

/// Contacts that need the owner's attention today, in priority order.
List<Contact> contactsNeedingAttention(List<Contact> contacts, int limit) {
  final ranked = [...contacts]..sort((a, b) {
      int rank(Contact c) => switch (c.status) {
            ContactStatus.followUp => 0,
            ContactStatus.booked => 1,
            ContactStatus.recovered => 2,
            ContactStatus.noResponse => 3,
            ContactStatus.notInterested => 5,
            _ => 4,
          };
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return (b.lastCallAt ?? b.createdAt).compareTo(a.lastCallAt ?? a.createdAt);
    });
  return ranked.take(limit).toList();
}
