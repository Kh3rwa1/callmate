import 'dart:async';
import 'dart:io';

import 'package:callpilot/core/config/app_env.dart';
import 'package:callpilot/data/models/misc.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/services/voice/sarvam_voice_agent_service.dart';
import 'package:callpilot/services/voice/voice_agent_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake backend voice-session endpoint.
class _Sessions implements VoiceSessionRepository {
  _Sessions(this._create);
  final Future<VoiceTestSession> Function() _create;
  int created = 0;

  @override
  Future<VoiceTestSession> createTestSession() {
    created++;
    return _create();
  }

  @override
  Future<VoiceChatReply> sendChatMessage(
    String message, {
    String? conversationId,
  }) async => VoiceChatReply(reply: 'echo $message');
}

VoiceTestSession _session({String token = 'sess_123', String proxy = ''}) =>
    VoiceTestSession(
      sessionToken: token,
      orgId: 'org_1',
      workspaceId: 'ws_1',
      appId: 'app_1',
      proxyBaseUrl: proxy,
    );

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _microphone = 7;

/// The SDK's audio interface talks to the `record` plugin; there is no
/// platform in unit tests, so every call is a no-op.
const _record = MethodChannel('com.llfbandit.record/messages');

void _mockMicrophone({required bool granted}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissions, (call) async {
        if (call.method == 'requestPermissions') {
          return {_microphone: granted ? 1 : 0};
        }
        if (call.method == 'checkPermissionStatus') return granted ? 1 : 0;
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveSarvamProxyBaseUrl', () {
    test('uses the backend-provided proxy URL and normalises the slash', () {
      expect(
        resolveSarvamProxyBaseUrl(
          'https://api.callpilot.in/voice/sarvam-proxy',
        ),
        'https://api.callpilot.in/voice/sarvam-proxy/',
      );
      expect(
        resolveSarvamProxyBaseUrl(' https://p.test/x/ '),
        'https://p.test/x/',
      );
    });

    test('falls back to API base URL + SARVAM_PROXY_PATH, never Sarvam', () {
      expect(
        resolveSarvamProxyBaseUrl(
          '',
          apiBaseUrl: 'https://api.callpilot.in/',
          proxyPath: 'voice/sarvam-proxy',
        ),
        'https://api.callpilot.in/voice/sarvam-proxy/',
      );
      final defaulted = resolveSarvamProxyBaseUrl('');
      expect(defaulted, startsWith(AppEnv.effectiveApiBaseUrl));
      expect(defaulted, endsWith(AppEnv.sarvamProxyPath));
      expect(defaulted, isNot(contains('sarvam.ai')));
    });
  });

  group('SarvamVoiceAgentService (native path)', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissions, null);
    });

    Future<
      ({SarvamVoiceAgentService service, List<VoiceConnectionState> states})
    >
    make(_Sessions sessions) async {
      final service = SarvamVoiceAgentService(sessions);
      final states = <VoiceConnectionState>[];
      service.getConnectionState().listen(states.add);
      addTearDown(service.dispose);
      return (service: service, states: states);
    }

    test('microphone denial surfaces a permission error', () async {
      _mockMicrophone(granted: false);
      final sessions = _Sessions(() async => _session());
      final t = await make(sessions);

      await expectLater(
        t.service.startTestSession(),
        throwsA(
          isA<VoiceAgentException>().having(
            (e) => e.permissionDenied,
            'permissionDenied',
            isTrue,
          ),
        ),
      );
      expect(t.service.currentState, VoiceConnectionState.error);
      expect(sessions.created, 0, reason: 'no backend session without mic');
    });

    test('backend session failure is reported (no direct fallback)', () async {
      _mockMicrophone(granted: true);
      final sessions = _Sessions(() async => throw Exception('503'));
      final t = await make(sessions);

      await expectLater(
        t.service.startTestSession(),
        throwsA(
          isA<VoiceAgentException>()
              .having((e) => e.message, 'message', contains('backend'))
              .having((e) => e.permissionDenied, 'permissionDenied', isFalse),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(t.states, [
        VoiceConnectionState.connecting,
        VoiceConnectionState.error,
      ]);
    });

    test('a session without a proxy token is refused', () async {
      _mockMicrophone(granted: true);
      final sessions = _Sessions(() async => _session(token: ''));
      final t = await make(sessions);

      await expectLater(
        t.service.startTestSession(),
        throwsA(
          isA<VoiceAgentException>().having(
            (e) => e.message,
            'message',
            contains('secure voice session'),
          ),
        ),
      );
      expect(t.service.currentState, VoiceConnectionState.error);
    });

    test(
      'connects only to our proxy with the session token as bearer',
      () async {
        // Local stand-in for the backend proxy: records the SDK's signed-URL
        // request and rejects it so the SDK never opens a websocket.
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = previous);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen = Completer<HttpRequest>();
        server.listen((req) {
          if (!seen.isCompleted) seen.complete(req);
          req.response
            ..statusCode = 502
            ..close();
        });

        _mockMicrophone(granted: true);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(_record, (_) async => null);
        addTearDown(() => messenger.setMockMethodCallHandler(_record, null));
        final proxy = 'http://127.0.0.1:${server.port}/voice/sarvam-proxy';
        final sessions = _Sessions(() async => _session(proxy: proxy));
        final t = await make(sessions);

        await expectLater(
          t.service.startTestSession(agentVariables: {'mode': 'owner_test'}),
          throwsA(
            isA<VoiceAgentException>().having(
              (e) => e.message,
              'message',
              contains('Sarvam voice connection error'),
            ),
          ),
        );

        final req = await seen.future;
        expect(req.uri.path, startsWith('/voice/sarvam-proxy/'));
        expect(req.uri.path, contains('org_1'));
        expect(req.headers.value('authorization'), 'Bearer sess_123');
        expect(req.headers.value('x-api-key'), isNull);
        expect(t.service.currentState, VoiceConnectionState.error);
      },
    );
  });

  group('SarvamVoiceAgentService idle behaviour', () {
    test('text/audio before a session are ignored; mute is tracked', () async {
      final service = SarvamVoiceAgentService(
        _Sessions(() async => _session()),
      );
      final transcripts = <List<VoiceTranscriptEntry>>[];
      service.getTranscriptStream().listen(transcripts.add);

      await service.sendText('   ');
      await service.sendText('hello');
      await service.sendAudio(Uint8List(8));
      expect(transcripts, isEmpty);

      expect(service.isMuted, isFalse);
      await service.setMuted(true);
      expect(service.isMuted, isTrue);
      await service.sendAudio(Uint8List(8));

      final levels = <double>[];
      service.levelStream.listen(levels.add);
      await service.stopSession();
      await Future<void>.delayed(Duration.zero);
      expect(service.currentState, VoiceConnectionState.disconnected);
      expect(levels, [0]);
      await service.dispose();
    });
  });
}
