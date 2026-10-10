import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/motion.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/state_views.dart';
import '../../data/models/models.dart';
import '../../l10n/l10n.dart';

/// "Hear your AI now": the AI employee calls the owner's own phone
/// (`POST /agent/test-call`), so they hear what customers hear.
Future<void> showOwnerTestCallSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _OwnerTestCallSheet(),
  );
}

class _OwnerTestCallSheet extends ConsumerStatefulWidget {
  const _OwnerTestCallSheet();
  @override
  ConsumerState<_OwnerTestCallSheet> createState() =>
      _OwnerTestCallSheetState();
}

class _OwnerTestCallSheetState extends ConsumerState<_OwnerTestCallSheet> {
  final _phone = TextEditingController();
  OwnerTestCallInfo? _info;
  bool _busy = false;
  bool _placed = false;
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

  Future<void> _call() async {
    final s = context.s;
    final phone = PhoneUtils.normalize(_phone.text);
    if (phone == null) {
      setState(() => _error = s.validPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await ref.read(callRepoProvider).callOwner(phone);
      Haptics.success();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _placed = true;
        _info = info;
      });
    } catch (e) {
      if (!mounted) return;
      // A snackbar would sit behind this sheet; show the error in it.
      setState(() {
        _busy = false;
        _error = _errorText(e, s);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final name = ref.watch(employeeNameProvider);
    final info = _info;
    final noneLeft = info != null && info.remainingToday == 0;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.page,
          0,
          AppSpace.page,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.hearYourAiTitle, style: t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              s.hearYourAiBody(name),
              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _phone,
              enabled: !_busy && !_placed,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]')),
              ],
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
              style: t.bodySmall?.copyWith(color: AppColors.inkFaint),
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
                        style: t.bodyMedium?.copyWith(color: AppColors.hot),
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
                              style: t.titleSmall?.copyWith(
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
                    label: s.done,
                    onPressed: () => Navigator.pop(context),
                  )
                : PrimaryButton(
                    label: s.callMeNow,
                    icon: Icons.call_rounded,
                    loading: _busy,
                    onPressed: noneLeft ? null : _call,
                  ),
          ],
        ),
      ),
    );
  }
}
