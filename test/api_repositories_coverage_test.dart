import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callpilot/core/network/api_client.dart';
import 'package:callpilot/core/storage/secure_store.dart';
import 'package:callpilot/data/datasources/api/api_repositories.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';

class _FakeStore extends SecureStore {
  String? access = 'mock_jwt_access';
  String? refresh = 'mock_jwt_refresh';
  @override
  Future<String?> accessToken() async => access;
  @override
  Future<String?> refreshToken() async => refresh;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

class _TestAdapter implements HttpClientAdapter {
  _TestAdapter(this.responder);
  final Future<ResponseBody> Function(RequestOptions opts) responder;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? reqStream,
    Future<void>? cancel,
  ) => responder(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late _FakeStore store;
  late ApiClient client;

  setUp(() {
    store = _FakeStore();
    client = ApiClient(store, baseUrl: 'https://api.callpilot.test');
  });

  group('ApiAuthRepository Coverage', () {
    test('covers full auth lifecycle methods', () async {
      client.dio.httpClientAdapter = _TestAdapter((opts) async {
        if (opts.path == '/auth/otp/request') {
          return _json({'message': 'OTP sent'});
        }
        if (opts.path == '/auth/login' || opts.path == '/auth/register') {
          return _json({'access_token': 'acc2', 'refresh_token': 'ref2'});
        }
        if (opts.path == '/auth/logout' || opts.path == '/auth/account') {
          return _json({'success': true});
        }
        return _json({}, 404);
      });

      final repo = ApiAuthRepository(client, store);
      expect(await repo.hasSession(), isTrue);

      await repo.requestOtp(phone: '919800000000');
      await repo.login(phone: '919800000000', otp: '123456');
      expect(store.access, 'acc2');

      await repo.register(
        phone: '919800000000',
        businessName: 'Biz',
        otp: '123456',
      );
      expect(store.access, 'acc2');

      await repo.logout();
      expect(store.access, isNull);

      await repo.deleteAccount();
      expect(store.access, isNull);
    });
  });

  group('ApiBusinessRepository Coverage', () {
    test('getBusiness, saveBusiness, getAgent, saveAgent', () async {
      final bizJson = {'id': 'b1', 'name': 'Biz Name', 'category': 'coaching'};
      final agentJson = {
        'id': 'a1',
        'name': 'Maya',
        'role': 'Counselor',
        'status': 'active',
        'template_id': 'coaching_v1',
      };

      client.dio.httpClientAdapter = _TestAdapter((opts) async {
        if (opts.path == '/business') {
          return _json(bizJson);
        }
        if (opts.path == '/agent') {
          return _json(agentJson);
        }
        return _json({}, 404);
      });

      final repo = ApiBusinessRepository(client);
      final b = await repo.getBusiness();
      expect(b?.name, 'Biz Name');

      final bSaved = await repo.saveBusiness(
        const Business(
          id: 'b1',
          name: 'Updated Biz',
          category: BusinessCategory.coaching,
        ),
      );
      expect(bSaved.id, 'b1');

      final a = await repo.getAgent();
      expect(a?.name, 'Maya');

      final aSaved = await repo.saveAgent(
        const Agent(
          id: 'a1',
          name: 'Maya',
          role: 'Senior Counselor',
          status: AgentStatus.active,
          templateId: 'coaching_v1',
        ),
      );
      expect(aSaved.id, 'a1');
    });
  });

  group('ApiLeadRepository Coverage', () {
    test('list, get, create, update, newLeads, import', () async {
      final leadJson = {
        'id': 'l1',
        'business_id': 'b1',
        'name': 'John Doe',
        'phone': '919876543210',
        'status': 'new',
        'created_at': '2026-01-01T00:00:00Z',
      };

      client.dio.httpClientAdapter = _TestAdapter((opts) async {
        if (opts.path == '/leads') {
          if (opts.method == 'GET') {
            return _json({
              'items': [leadJson],
              'has_more': false,
            });
          }
          if (opts.method == 'POST') {
            return _json(leadJson);
          }
        }
        if (opts.path == '/leads/l1') {
          if (opts.method == 'GET' || opts.method == 'PATCH') {
            return _json(leadJson);
          }
        }
        if (opts.path == '/leads/import') {
          return _json({'imported': 2, 'skipped': 0, 'errors': []});
        }
        return _json({}, 404);
      });

      final repo = ApiLeadRepository(client);
      final page = await repo.list(filter: LeadFilter.all, limit: 10);
      expect(page.items.length, 1);

      final lead = await repo.get('l1');
      expect(lead.id, 'l1');

      final created = await repo.create(
        const NewLeadInput(name: 'John', phone: '919876543210'),
      );
      expect(created.id, 'l1');

      final updated = await repo.update(created.copyWith(name: 'John Updated'));
      expect(updated.id, 'l1');

      final imported = await repo.import([
        const NewLeadInput(name: 'A', phone: '919800000001'),
        const NewLeadInput(name: 'B', phone: '919800000002'),
      ]);
      expect(imported.imported, 2);

      final newL = await repo.newLeads();
      expect(newL.length, 1);
    });
  });

  group('ApiCallRepository & ApiCampaignRepository Coverage', () {
    test(
      'calls list, get, forLead, triggerCall and campaigns lifecycle',
      () async {
        final callJson = {
          'id': 'call1',
          'lead_id': 'l1',
          'lead_name': 'John Doe',
          'lead_phone': '919876543210',
          'agent_id': 'a1',
          'status': 'completed',
          'started_at': '2026-01-01T00:00:00Z',
        };
        final campJson = {
          'id': 'cmp1',
          'agent_id': 'a1',
          'purpose': 'Admission Outreach',
          'status': 'running',
          'created_at': '2026-01-01T00:00:00Z',
        };

        client.dio.httpClientAdapter = _TestAdapter((opts) async {
          if (opts.path == '/calls') {
            return _json({
              'items': [callJson],
              'has_more': false,
            });
          }
          if (opts.path == '/calls/call1') {
            return _json(callJson);
          }
          if (opts.path == '/leads/l1/call') {
            return _json({'call': callJson});
          }
          if (opts.path == '/campaigns') {
            if (opts.method == 'GET') {
              return _json({
                'items': [campJson],
              });
            }
            if (opts.method == 'POST') {
              return _json(campJson);
            }
          }
          if (opts.path == '/campaigns/cmp1') {
            return _json(campJson);
          }
          if (opts.path == '/campaigns/cmp1/start' ||
              opts.path == '/campaigns/cmp1/stop') {
            return _json(campJson);
          }
          return _json({}, 404);
        });

        final callRepo = ApiCallRepository(client);
        final callsPage = await callRepo.list(filter: CallFilter.connected);
        expect(callsPage.items.length, 1);
        final c = await callRepo.get('call1');
        expect(c.id, 'call1');
        final forL = await callRepo.forLead('l1');
        expect(forL.length, 1);
        final trig = await callRepo.triggerCall('l1');
        expect(trig.id, 'call1');

        final campRepo = ApiCampaignRepository(client);
        final active = await campRepo.active();
        expect(active?.id, 'cmp1');
        final single = await campRepo.get('cmp1');
        expect(single.id, 'cmp1');
        final created = await campRepo.create(
          const CampaignDraft(purpose: 'Outreach', leadIds: ['l1']),
        );
        expect(created.id, 'cmp1');
        final started = await campRepo.start('cmp1', consentAttestation: true);
        expect(started.id, 'cmp1');
        final stopped = await campRepo.stop('cmp1');
        expect(stopped.id, 'cmp1');
        final est = campRepo.estimateCostInr(10);
        expect(est, greaterThan(0));
      },
    );
  });

  group('ApiFollowUpRepository & ApiCallbackRepository Coverage', () {
    test('followups and callbacks', () async {
      final fJson = {
        'id': 'f1',
        'lead_id': 'l1',
        'lead_name': 'John',
        'lead_phone': '919876543210',
        'message': 'Hello',
        'status': 'ready',
        'created_at': '2026-01-01T00:00:00Z',
      };
      final cbJson = {
        'id': 'cb1',
        'lead_id': 'l1',
        'lead_name': 'John',
        'scheduled_at': '2026-01-02T10:00:00Z',
        'status': 'scheduled',
      };

      client.dio.httpClientAdapter = _TestAdapter((opts) async {
        if (opts.path == '/followups') {
          return _json({
            'items': [fJson],
          });
        }
        if (opts.path == '/followups/f1') {
          return _json(fJson);
        }
        if (opts.path == '/callbacks') {
          if (opts.method == 'GET') {
            return _json({
              'items': [cbJson],
            });
          }
          if (opts.method == 'POST') {
            return _json(cbJson);
          }
        }
        if (opts.path == '/callbacks/cb1') {
          return _json(cbJson);
        }
        return _json({}, 404);
      });

      final fRepo = ApiFollowUpRepository(client);
      final fList = await fRepo.list(pendingOnly: true);
      expect(fList.length, 1);
      final fSingle = await fRepo.get('f1');
      expect(fSingle.id, 'f1');
      final fUp = await fRepo.update(fSingle.copyWith(message: 'Updated'));
      expect(fUp.id, 'f1');
      final fCall = await fRepo.forCall('call1');
      expect(fCall?.id, 'f1');

      final cbRepo = ApiCallbackRepository(client);
      final cbList = await cbRepo.list();
      expect(cbList.length, 1);
      final cbScheduled = await cbRepo.schedule(
        leadId: 'l1',
        at: DateTime(2026, 1, 2),
      );
      expect(cbScheduled.id, 'cb1');
      final done = await cbRepo.markDone('cb1');
      expect(done.id, 'cb1');
    });
  });

  group(
    'ApiUsage, Notifications, Knowledge, Device, VoiceSession Repositories Coverage',
    () {
      test('covers usage, notif, knowledge, device, voice session', () async {
        final uJson = {
          'subscription': {
            'plan_name': 'Pro',
            'included_minutes': 1000,
            'renews_at': '2026-02-01T00:00:00Z',
            'price_inr': 4999,
          },
          'minutes_used': 50,
          'calls_made': 20,
          'rate_per_minute_inr': 6,
        };
        final notifJson = {
          'id': 'n1',
          'type': 'hot_lead',
          'title': 'Hot Lead',
          'body': 'Lead interested',
          'created_at': '2026-01-01T00:00:00Z',
        };
        final kJson = {
          'id': 'kn1',
          'type': 'text',
          'title': 'FAQ',
          'detail': 'Coaching questions',
          'status': 'ready',
          'progress': 1.0,
          'updated_at': '2026-01-01T00:00:00Z',
        };

        client.dio.httpClientAdapter = _TestAdapter((opts) async {
          if (opts.path == '/usage') {
            return _json(uJson);
          }
          if (opts.path == '/notifications') {
            return _json({
              'items': [notifJson],
            });
          }
          if (opts.path == '/notifications/n1') {
            return _json({'success': true});
          }
          if (opts.path == '/knowledge') {
            if (opts.method == 'GET') {
              return _json([kJson]);
            }
            if (opts.method == 'POST') {
              return _json(kJson);
            }
          }
          if (opts.path == '/knowledge/kn1') {
            if (opts.method == 'GET') {
              return _json(kJson);
            }
            if (opts.method == 'DELETE') {
              return _json({'deleted': true});
            }
          }
          if (opts.path == '/devices') {
            return _json({'registered': true});
          }
          if (opts.path == '/devices/tok1') {
            return _json({'deleted': true});
          }
          if (opts.path == '/voice/test-session') {
            return _json({
              'session_token': 'sess_tok',
              'org_id': 'org_1',
              'workspace_id': 'ws_1',
              'app_id': 'app_1',
              'proxy_base_url': 'https://proxy',
            });
          }
          if (opts.path == '/voice/chat') {
            return _json({'reply': 'Yes sure'});
          }
          return _json({}, 404);
        });

        final uRepo = ApiUsageRepository(client);
        final usage = await uRepo.get();
        expect(usage.subscription.planName, 'Pro');

        final nRepo = ApiNotificationRepository(client);
        final notifs = await nRepo.list();
        expect(notifs.length, 1);
        await nRepo.markRead('n1');

        final kRepo = ApiKnowledgeRepository(client);
        final kList = await kRepo.list();
        expect(kList.length, 1);
        final kSingle = await kRepo.get('kn1');
        expect(kSingle.id, 'kn1');
        final stream = kRepo.add(
          const KnowledgeInput(
            type: KnowledgeType.text,
            title: 'FAQ',
            content: 'Questions',
          ),
        );
        final kStreamFirst = await stream.first;
        expect(kStreamFirst.id, 'pending');
        await kRepo.remove('kn1');

        final dRepo = ApiDeviceRepository(client);
        await dRepo.registerDevice(token: 'tok1', platform: 'ios');
        await dRepo.unregisterDevice('tok1');

        final vsRepo = ApiVoiceSessionRepository(client);
        final sess = await vsRepo.createTestSession();
        expect(sess.sessionToken, 'sess_tok');
        final chat = await vsRepo.sendChatMessage('Hello');
        expect(chat.reply, 'Yes sure');

        final backendEvents = PushBackendEvents();
        expect(backendEvents.stream, isA<Stream<BackendEvent>>());
        backendEvents.add(const DataChangedEvent('leads'));
      });
    },
  );
}
