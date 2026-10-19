import '../../data/models/models.dart';

/// The owner's mobile network: Jio has its own call-forwarding codes;
/// Airtel, Vi, BSNL and the rest use the standard (GSM) ones.
enum ForwardingNetwork { jio, gsm }

/// One code the owner dials on their phone, with what it does.
typedef ForwardingStep = ({ForwardingStepKind kind, String code});

enum ForwardingStepKind { clear, all, noAnswer, busy, unreachable }

/// Call-forwarding codes that make the phone match the chosen [AnswerMode].
/// Switching to "missed" first clears an earlier "every call" forward, which
/// would otherwise win.
List<ForwardingStep> forwardingSteps(
  AnswerMode mode,
  ForwardingNetwork network,
  String line,
) {
  final digits = line.replaceAll(RegExp(r'\D'), '');
  // Jio takes the 10-digit number; the standard codes take +91.
  final ten = digits.length > 10
      ? digits.substring(digits.length - 10)
      : digits;
  const clear = (kind: ForwardingStepKind.clear, code: '##002#');
  return switch ((mode, network)) {
    (AnswerMode.owner, _) => [clear],
    (AnswerMode.ai, ForwardingNetwork.jio) => [
      (kind: ForwardingStepKind.all, code: '*401*$ten#'),
    ],
    (AnswerMode.ai, ForwardingNetwork.gsm) => [
      (kind: ForwardingStepKind.all, code: '**21*$line#'),
    ],
    (AnswerMode.missed, ForwardingNetwork.jio) => [
      clear,
      (kind: ForwardingStepKind.noAnswer, code: '*403*$ten#'),
      (kind: ForwardingStepKind.busy, code: '*405*$ten#'),
      (kind: ForwardingStepKind.unreachable, code: '*409*$ten#'),
    ],
    (AnswerMode.missed, ForwardingNetwork.gsm) => [
      clear,
      (kind: ForwardingStepKind.noAnswer, code: '**004*$line#'),
    ],
  };
}
