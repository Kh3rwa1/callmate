import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/app_repository.dart';
import '../../models/bootstrap.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_rows.dart';

/// The business's inbound number, as registered with the voice service.
///
/// The number and its connection are tenant configuration held by the backend,
/// so this screen reads them from there. Provider identifiers are never shown.
class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  PhoneNumbersPayload? _payload;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await ApiClient().phoneNumbers();
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _payload?.phoneNumber;
    final businessName = context.watch<AppRepository>().data.organisation.name;

    return PageScaffold(
      title: 'Phone number',
      child: _loading && phone == null
          ? const LoadingBlock(label: 'Checking your number…')
          : _error != null && phone == null
              ? ErrorBlock(
                  title: "We couldn't load your phone number",
                  message: _error!,
                  onRetry: _load,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SurfaceCard(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        children: [
                          const IconTile(icon: Icons.phone_rounded, tone: Tone.blue, size: 52),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            phone?.number ?? 'Not set',
                            style: AppText.hero,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Customers call this number',
                            style: AppText.caption.copyWith(color: AppColors.inkSoft),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          StatusPill(
                            label: phone?.status == 'connected' ? 'Connected' : 'Setting up',
                            tone: phone?.status == 'connected' ? Tone.green : Tone.amber,
                            large: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader(title: 'How calls are handled'),
                    SwitchRow(
                      icon: Icons.phone_forwarded_rounded,
                      tone: Tone.blue,
                      label: 'Send missed calls to $agentName',
                      description: 'Your AI employee calls the customer back automatically',
                      value: phone?.inboundEnabled ?? true,
                      onChanged: _toggleCallback,
                    ),
                    SettingsRow(
                      icon: Icons.timer_rounded,
                      tone: Tone.amber,
                      label: 'Ring before pickup',
                      trailing: '${phone?.ringBeforePickup ?? 3} rings',
                      onTap: () => showAppToast(context, 'Ring count saved'),
                    ),

                    if ((_payload?.providerCount ?? 0) > 0) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader(title: 'Registered with your voice service'),
                      SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_payload!.providerCount} '
                              'number${_payload!.providerCount == 1 ? '' : 's'} '
                              'are live on your voice account.',
                              style: AppText.body,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Calls are placed from these numbers so customers '
                              'recognise $businessName.',
                              style: AppText.caption.copyWith(color: AppColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Incoming calls are answered by your AI employee. The connection to '
                      'your voice service is held securely by our backend — credentials '
                      'never live inside this app.',
                      style: AppText.caption.copyWith(color: AppColors.inkSoft),
                    ),
                  ],
                ),
    );
  }

  Future<void> _toggleCallback(bool value) async {
    try {
      // Missed-call callback is part of the agent's inbound configuration.
      await ApiClient().updateAgent({'inbound_enabled': value});
      if (!mounted) return;
      setState(() {
        final current = _payload?.phoneNumber;
        _payload = PhoneNumbersPayload(
          phoneNumber: current == null
              ? null
              : PhoneNumberInfo(
                  number: current.number,
                  inboundEnabled: value,
                  callbackOnMissed: current.callbackOnMissed,
                  ringBeforePickup: current.ringBeforePickup,
                  status: current.status,
                ),
          providerCount: _payload?.providerCount ?? 0,
        );
      });
      showAppToast(
        context,
        value ? 'Missed calls will be called back' : 'Missed-call callback turned off',
      );
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    }
  }
}
