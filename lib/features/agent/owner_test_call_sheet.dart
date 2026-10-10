import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/calling_hours.dart';
import '../../core/utils/format.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// "Hear your AI now": the AI employee calls the owner's own phone
/// (`POST /agent/test-call`), so they hear what customers hear. Outside
/// calling hours it offers the in-app voice test instead.
Future<void> showOwnerTestCallSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          0,
          AppSpace.page,
          16 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: OwnerTestCallPanel(
          onDone: () => Navigator.pop(ctx),
          onTalkInApp: () {
            Navigator.pop(ctx);
            context.push('/voice-test');
          },
        ),
      ),
    ),
  );
}

/// Owner heard the AI (test call placed or in-app voice test done). Ticks
/// "Hear your AI" on the Home checklist.
final heardAiProvider = Provider<bool>((ref) {
  try {
    return ref.watch(localPrefsProvider).heardAi;
  } catch (_) {
    return false;
  }
});

/// The body of "Hear your AI": number (prefilled), "Call me now", and the
/// result. Used in the sheet and on the last first-run step. Errors show
/// inside the panel (a snackbar would sit behind a sheet).
class OwnerTestCallPanel extends ConsumerStatefulWidget {
  const OwnerTestCallPanel({
    super.key,
    required this.onDone,
    required this.onTalkInApp,
    this.showTitle = true,
    this.doneLabel,
  });

  /// After the call was placed and the owner taps Done.
  final VoidCallback onDone;

  /// Opens the in-app voice test (outside calling hours).
  final VoidCallback onTalkInApp;
  final bool showTitle;
  final String? doneLabel;

  @override
  ConsumerState<OwnerTestCallPanel> createState() => _OwnerTestCallPanelState();
}

class _OwnerTestCallPanelState extends ConsumerState<OwnerTestCallPanel> {
  final _phone = TextEditingController();
  OwnerTestCallInfo? _info;
  bool _busy = false;
  bool _placed = false;
  bool _outsideHours = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await ref.read(callRepoProvider).ownerTestCallInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        if (_phone.text.isEmpty && info.phone != null) {
          _phone.text = PhoneUtils.display(info.phone);
        }
      });
    } catch (_) {
      // The owner can still type their number; the call itself reports errors.
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _errorText(Object e, S s) {
    if (e is ApiException) {
      switch (e.code) {
        case 'test_call_limit':
          return s.testCallLimitReached;
        case 'phone_is_customer':
          return s.testCallPhoneIsCustomer;
        case 'invalid_phone':
          return s.validPhone;
      }
    }
    return friendlyError(e, s);
  }

  /// The agent's calling window, clamped to TRAI (backend default 10–19).
  RangeValues get _hours {
    final a = ref.read(agentProvider).value;
    return traiCallingHours(
      a?.callingHoursStart ?? 10,
      a?.callingHoursEnd ?? 19,
    );
  }

  bool get _inHours => isIndiaCallingHour(
    ref.read(clockProvider)(),
    start: _hours.start.round(),
    end: _hours.end.round(),
  );

  Future<void> _call() async {
    final s = context.s;
    if (!_inHours) {
      setState(() => _outsideHours = true);
      return;
    }
    final phone = PhoneUtils.normalize(_phone.text);
    if (phone == null) {
      setState(() => _error = s.validPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final prefs = ref.read(localPrefsProvider);
    try {
      final info = await ref.read(callRepoProvider).callOwner(phone);
      await prefs.setHeardAi(true);
      Haptics.success();
      if (!mounted) return;
      ref.invalidate(heardAiProvider);
      setState(() {
        _busy = false;
        _placed = true;
        _info = info;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e is ApiException && e.code == 'outside_hours') {
          _outsideHours = true;
        } else {
          _error = _errorText(e, s);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final name = ref.watch(employeeNameProvider);
    ref.watch(agentProvider);
    final info = _info;
    final noneLeft = info != null && info.remainingToday == 0;
    final outside = !_placed && (_outsideHours || !_inHours);
    final hours = _hours;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(s.hearYourAiTitle, style: t.headlineSmall),
          const SizedBox(height: 6),
          Text(
            s.hearYourAiBody(name),
            style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 18),
        ],
        if (outside) ...[
          Container(
            key: const Key('outside-hours'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.nightlight_round, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.outsideCallingHours(
                      name,
                      Fmt.hour(hours.start.round()),
                      Fmt.hour(hours.end.round()),
                    ),
                    style: t.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: s.talkInApp(name),
            icon: Icons.mic_rounded,
            onPressed: widget.onTalkInApp,
          ),
        ] else ...[
          TextField(
            controller: _phone,
            enabled: !_busy && !_placed,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]')),
            ],
            style: t.titleMedium,
            decoration: InputDecoration(
              labelText: s.yourMobileNumber,
              prefixIcon: const Icon(Icons.phone_iphone_rounded),
            ),
            onSubmitted: (_) => _call(),
          ),
          const SizedBox(height: 10),
          Text(
            [
              s.testCallUsesMinutes,
              if (info != null) s.testCallsLeft(info.remainingToday),
            ].join(' '),
            style: t.bodyMedium?.copyWith(color: AppColors.inkFaint),
          ),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.base),
            alignment: Alignment.topCenter,
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: t.bodyLarge?.copyWith(color: AppColors.hot),
                    ),
                  )
                : _placed
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.ring_volume_rounded,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.testCallPlaced,
                            style: t.titleMedium?.copyWith(
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          _placed
              ? PrimaryButton(
                  label: widget.doneLabel ?? s.done,
                  onPressed: widget.onDone,
                )
              : PrimaryButton(
                  label: s.callMeNow,
                  icon: Icons.call_rounded,
                  loading: _busy,
                  onPressed: noneLeft ? null : _call,
                ),
        ],
      ],
    );
  }
}
