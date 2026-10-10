import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/settings.dart';
import 'package:callpilot/core/theme/app_colors.dart';
import 'package:callpilot/core/widgets/mascot.dart';
import 'package:callpilot/features/home/home_screen.dart';
import 'package:callpilot/features/voice_test/voice_test_screen.dart';
import 'package:callpilot/features/voice_test/voice_test_status.dart';
import 'package:callpilot/services/voice/mock_voice_agent_service.dart';
import 'package:callpilot/services/voice/voice_agent_service.dart';
import 'package:callpilot/services/voice/voice_persona.dart';
import 'package:callpilot/l10n/s.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

/// Records what the screen asks of the voice service.
class _SpyVoice extends MockVoiceAgentService {
  _SpyVoice({super.failFirstAttempt})
    : super(
        agentName: 'Riya',
        agentRole: 'Counsellor',
        businessName: 'ABC Coaching Centre',
      );

  final sent = <String>[];
  final mutes = <bool>[];
  Map<String, dynamic>? lastVariables;
  int stops = 0;

  @override
  Future<void> startTestSession({
    Map<String, dynamic> agentVariables = const {},
  }) {
    lastVariables = agentVariables;
    return super.startTestSession(agentVariables: agentVariables);
  }

  @override
  Future<void> sendText(String text) {
    sent.add(text);
    return super.sendText(text);
  }

  @override
  Future<void> setMuted(bool muted) {
    mutes.add(muted);
    return super.setMuted(muted);
  }

  @override
  Future<void> stopSession() {
    stops++;
    return super.stopSession();
  }
}

/// Always fails like a denied microphone.
class _DeniedVoice extends MockVoiceAgentService {
  _DeniedVoice()
    : super(agentName: 'Riya', agentRole: 'Counsellor', businessName: 'ABC');

  @override
  Future<void> startTestSession({
    Map<String, dynamic> agentVariables = const {},
  }) async => throw const VoiceAgentException(
    'Microphone access is needed.',
    permissionDenied: true,
  );
}

/// Fails with a non-voice error.
class _CrashingVoice extends MockVoiceAgentService {
  _CrashingVoice()
    : super(agentName: 'Riya', agentRole: 'Counsellor', businessName: 'ABC');

  @override
  Future<void> startTestSession({
    Map<String, dynamic> agentVariables = const {},
  }) async => throw StateError('socket closed');
}

void main() {
  group('voice test status mapping', () {
    test('every state maps to a mascot pose and label', () {
      for (final s in VoiceConnectionState.values) {
        expect(mascotForVoiceState(s), isA<BirdPose>());
        expect(voiceStatusFor(s).$1, isNotEmpty);
      }
      expect(
        mascotForVoiceState(VoiceConnectionState.speaking),
        BirdPose.speaking,
      );
      expect(mascotForVoiceState(VoiceConnectionState.error), BirdPose.error);
    });

    test('listening shows Muted when muted', () {
      expect(voiceStatusFor(VoiceConnectionState.listening).$1, 'Listening');
      expect(voiceStatusFor(VoiceConnectionState.listening, muted: true), (
        'Muted',
        AppColors.success,
      ));
      expect(voiceStatusFor(VoiceConnectionState.error).$2, AppColors.hot);
    });

    test('only active states are live', () {
      expect(VoiceConnectionState.values.where(isLiveVoiceState).toSet(), {
        VoiceConnectionState.listening,
        VoiceConnectionState.speaking,
        VoiceConnectionState.thinking,
        VoiceConnectionState.connecting,
      });
    });
  });

  group('VoiceTestScreen', () {
    late _SpyVoice voice;

    appTest('runs a live session: suggestions, typed text, mute and end', (
      h,
    ) async {
      await h.push('/voice-test');
      expect(find.byType(VoiceTestScreen), findsOneWidget);
      expect(find.textContaining('Talk to '), findsOneWidget);
      expect(voice.lastVariables?['mode'], 'owner_test');
      expect(voice.lastVariables?['business_name'], 'ABC Coaching Centre');

      // Connected after the mock's 1.3 s handshake; agent greets.
      await h.settle(20);
      expect(find.textContaining('Namaste'), findsWidgets);

      await h.tapText('“What do you do?”');
      expect(voice.sent, ['What do you do?']);

      await h.tester.enterText(find.byType(TextField), '  Do you have  ');
      await h.tester.testTextInput.receiveAction(TextInputAction.send);
      await h.settle(2);
      expect(voice.sent.last, 'Do you have');
      expect(find.text('Do you have'), findsWidgets);

      // Empty input is ignored.
      await h.tap(find.byIcon(Icons.send_rounded));
      expect(voice.sent, hasLength(2));

      await h.tap(find.byIcon(Icons.mic_rounded));
      expect(voice.mutes, [true]);
      expect(find.text('Unmute'), findsOneWidget);
      await h.tap(find.byIcon(Icons.mic_off_rounded));
      expect(voice.mutes, [true, false]);

      await h.tap(find.byIcon(Icons.call_end_rounded));
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Talk again'), findsOneWidget);

      await h.tapText('Done');
      expect(h.location, '/home');
      expect(find.byType(HomeScreen), findsOneWidget);
    }, voice: () => voice = _SpyVoice());

    appTest(
      'a man employee speaks in a man\'s voice, in the owner\'s language',
      (h) async {
        h.backend.agent = h.backend.agent.copyWith(voice: maleVoice);
        h.container.read(dataVersionProvider.notifier).bump();
        await h.container.read(languageProvider.notifier).set(AppLang.hi);
        await h.push('/voice-test');
        expect(voice.lastVariables?['gender'], 'male');
        expect(voice.lastVariables?['speaker'], 'shubh_hi_customer');
        expect(voice.lastVariables?['language_code'], 'hi-IN');
      },
      voice: () => voice = _SpyVoice(),
    );

    appTest('the default employee speaks in a woman\'s voice', (h) async {
      await h.push('/voice-test');
      expect(voice.lastVariables?['gender'], 'female');
      expect(voice.lastVariables?['speaker'], 'ishita_enhi_customer');
      expect(voice.lastVariables?['speaker'], isNot('meera'));
    }, voice: () => voice = _SpyVoice());

    appTest(
      'from onboarding: finishing the scripted call completes onboarding',
      (h) async {
        expect(h.prefs.onboarded, isFalse);
        await h.go('/voice-test?from=onboarding');
        // Let the whole scripted conversation play out.
        for (var i = 0; i < 40; i++) {
          await h.tester.pump(const Duration(seconds: 1));
        }
        expect(find.text('Talk again'), findsOneWidget);

        await h.tapText('Talk again');
        expect(find.text('Talk again'), findsNothing);
        await h.tap(find.byIcon(Icons.call_end_rounded));

        await h.tapText('Continue');
        expect(h.prefs.onboarded, isTrue);
        expect(h.prefs.agentTested, isTrue);
        expect(h.location, '/home');
      },
      onboarded: false,
      location: '/onboarding',
    );

    appTest('connection failure shows retry which reconnects', (h) async {
      await h.push('/voice-test');
      await h.settle(12);
      expect(find.text('Couldn\'t connect'), findsOneWidget);
      expect(find.textContaining('couldn\'t connect'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);

      await h.tapText('Try again');
      await h.settle(12);
      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('Namaste'), findsWidgets);
    }, voice: () => _SpyVoice(failFirstAttempt: true));

    appTest(
      'error from onboarding offers to continue to the dashboard',
      (h) async {
        await h.go('/voice-test?from=onboarding');
        await h.settle(4);
        expect(find.textContaining('couldn\'t connect'), findsOneWidget);
        // The raw transport error never reaches the owner.
        expect(find.textContaining('socket closed'), findsNothing);

        await h.tapText('Continue to dashboard');
        expect(h.prefs.onboarded, isTrue);
        expect(h.location, '/home');
      },
      onboarded: false,
      location: '/onboarding',
      voice: _CrashingVoice.new,
    );

    appTest('denied microphone shows open settings; End leaves the screen', (
      h,
    ) async {
      await h.push('/voice-test');
      await h.settle(4);
      expect(find.text('Microphone access is needed.'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      await h.tap(find.byIcon(Icons.call_end_rounded));
      expect(h.location, '/home');
    }, voice: _DeniedVoice.new);

    appTest('backgrounding the app stops a live session', (h) async {
      await h.push('/voice-test');
      await h.settle(12);
      final before = voice.stops;
      h.tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      await h.settle(2);
      expect(voice.stops, greaterThan(before));
      expect(find.text('Disconnected'), findsOneWidget);
      h.tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    }, voice: () => voice = _SpyVoice());
  });
}
