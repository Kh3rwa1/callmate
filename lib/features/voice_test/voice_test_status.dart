import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/mascot.dart';
import '../../services/voice/voice_agent_service.dart';

/// Pure presentation mapping for the voice test screen, kept separate from the
/// widget so it can be unit tested.

/// Mascot pose for a given connection state.
MascotState mascotForVoiceState(VoiceConnectionState state) => switch (state) {
  VoiceConnectionState.speaking => MascotState.speaking,
  VoiceConnectionState.listening => MascotState.listening,
  VoiceConnectionState.thinking => MascotState.thinking,
  VoiceConnectionState.connecting => MascotState.calling,
  VoiceConnectionState.error => MascotState.error,
  VoiceConnectionState.disconnected => MascotState.success,
  VoiceConnectionState.idle => MascotState.welcome,
};

/// Status label and colour for a given connection state.
(String, Color) voiceStatusFor(
  VoiceConnectionState state, {
  bool muted = false,
}) => switch (state) {
  VoiceConnectionState.connecting => ('Connecting…', AppColors.warmInk),
  VoiceConnectionState.listening => (
    muted ? 'Muted' : 'Listening',
    AppColors.success,
  ),
  VoiceConnectionState.speaking => ('Speaking', AppColors.brand),
  VoiceConnectionState.thinking => ('Thinking…', AppColors.warmInk),
  VoiceConnectionState.disconnected => ('Disconnected', AppColors.cold),
  VoiceConnectionState.error => ('Couldn\'t connect', AppColors.hot),
  VoiceConnectionState.idle => ('Ready', AppColors.cold),
};

/// Whether a session is active (or being established) in [state].
bool isLiveVoiceState(VoiceConnectionState state) => const {
  VoiceConnectionState.listening,
  VoiceConnectionState.speaking,
  VoiceConnectionState.thinking,
  VoiceConnectionState.connecting,
}.contains(state);

/// Canned questions offered as chips: (chip label, message sent).
const voiceTestSuggestions = <(String, String)>[
  ('“What do you do?”', 'What do you do?'),
  ('“How do you handle fees?”', 'How do you handle fees and pricing?'),
  ('“Can I book a visit?”', 'Can I book an appointment or visit?'),
  ('“What are your hours?”', 'What are your calling hours?'),
];
