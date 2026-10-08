import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_env.dart';
import '../../core/config/brand.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repositories.dart';
import '../../services/auth/google_auth_service.dart';
import 'google_button.dart';

/// Authentication Screen: Google sign-in (default), with phone + OTP behind
/// `PHONE_OTP_LOGIN`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _businessController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Phone + OTP flow instead of Google.
  bool _usePhone = false;

  /// Google account is new: collect business name + contact number.
  bool _googleRegistering = false;

  bool _isRegister = false;
  bool _otpSent = false;
  bool _submitting = false;
  String? _errorMessage;

  int _resendCountdown = 30;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _businessController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendCountdown = 0);
      } else {
        if (mounted) setState(() => _resendCountdown--);
      }
    });
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final outcome = await ref
          .read(sessionProvider.notifier)
          .signInWithGoogle();
      if (!mounted) return;
      if (outcome == GoogleSignInOutcome.registrationRequired) {
        setState(() {
          _googleRegistering = true;
          _submitting = false;
        });
        return;
      }
      HapticFeedback.heavyImpact();
      context.go('/home');
    } on GoogleSignInCancelled {
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = friendlyError(e);
        });
      }
    }
  }

  Future<void> _finishGoogleRegistration() async {
    final businessName = _businessController.text.trim();
    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (businessName.isEmpty) {
      setState(
        () => _errorMessage = 'Please enter your business or company name.',
      );
      return;
    }
    if (phone == null) {
      setState(
        () => _errorMessage = 'Please enter a valid 10-digit mobile number.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .completeGoogleRegistration(businessName: businessName, phone: phone);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      context.go('/onboarding');
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = friendlyError(e);
        });
      }
    }
  }

  /// Signed-out landing: no form yet, just the pitch and the Google button.
  bool get _heroMode => !_usePhone && !_googleRegistering;

  List<Widget> _hero(TextTheme t) => [
    const SizedBox(height: 8),
    Reveal(child: Center(child: const _FloatingMascot())),
    const SizedBox(height: 22),
    Reveal(
      index: 1,
      child: Text(
        'Your AI employee\ncalls every lead',
        textAlign: TextAlign.center,
        style: t.displaySmall?.copyWith(fontSize: 31, height: 1.12),
      ),
    ),
    const SizedBox(height: 10),
    Reveal(
      index: 2,
      child: Text(
        'Calls, qualifies and drafts your WhatsApp follow-ups, '
        'in Hindi, English and Bengali.',
        textAlign: TextAlign.center,
        style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
      ),
    ),
    const SizedBox(height: 26),
    for (final (i, (icon, text, tint, fg)) in const [
      (
        Icons.bolt_rounded,
        'Calls new leads within minutes',
        AppColors.brandSoft,
        AppColors.brand,
      ),
      (
        Icons.local_fire_department_rounded,
        'Scores who is ready to buy',
        AppColors.hotSoft,
        AppColors.hot,
      ),
      (
        Icons.chat_rounded,
        'You review every message, then tap Send',
        AppColors.whatsappSoft,
        AppColors.whatsapp,
      ),
    ].indexed)
      Reveal(
        index: 3 + i,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: t.titleSmall)),
            ],
          ),
        ),
      ),
    const SizedBox(height: 18),
    if (_errorMessage != null) ...[
      _ErrorBanner(message: _errorMessage!),
      const SizedBox(height: 14),
    ],
    Reveal(
      index: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _googleSection(t),
      ),
    ),
  ];

  String get _title {
    if (!_usePhone) {
      return _googleRegistering ? 'Set Up Your Business' : 'Welcome';
    }
    if (_otpSent) return _isRegister ? 'Verify Registration' : 'Verify OTP';
    return _isRegister ? 'Create Your Account' : 'Sign In to Your Workspace';
  }

  String get _subtitle {
    if (!_usePhone) {
      return _googleRegistering
          ? 'One last step: tell us about your business'
          : 'Sign in or create your account with Google';
    }
    if (_otpSent) {
      final hint = AppEnv.flavor != AppFlavor.prod
          ? ' (Use 123456 on staging)'
          : '';
      return 'Enter the 6-digit code sent to ${PhoneUtils.display(_phoneController.text)}$hint';
    }
    return _isRegister
        ? 'Start hiring AI employees for your business'
        : 'Enter your phone number to receive a one-time login code';
  }

  List<Widget> _googleSection(TextTheme t) {
    if (_googleRegistering) {
      return [
        TextField(
          controller: _businessController,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.organizationName],
          decoration: const InputDecoration(
            labelText: 'Business name',
            hintText: 'e.g. Apex Coaching / Sharma Realty',
            prefixIcon: Icon(Icons.business_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Business mobile number',
            hintText: '98300 12345',
            helperText: 'Customers see this number on WhatsApp follow-ups',
            prefixIcon: Icon(Icons.phone_outlined),
            prefixText: '+91 ',
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Create Account',
          loading: _submitting,
          color: AppColors.success,
          onPressed: _finishGoogleRegistration,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () async {
                    await ref.read(googleAuthProvider).signOut();
                    if (mounted) {
                      setState(() {
                        _googleRegistering = false;
                        _errorMessage = null;
                      });
                    }
                  },
            child: const Text('Use a different Google account'),
          ),
        ),
      ];
    }
    return [
      GoogleSignInButton(loading: _submitting, onPressed: _continueWithGoogle),
      if (AppEnv.phoneOtpLogin) ...[
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _usePhone = true;
                    _errorMessage = null;
                  }),
            child: const Text('Use phone number instead'),
          ),
        ),
      ],
    ];
  }

  Future<void> _sendOtp() async {
    _errorMessage = null;
    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (phone == null) {
      setState(
        () => _errorMessage = 'Please enter a valid 10-digit mobile number.',
      );
      return;
    }
    if (_isRegister && _businessController.text.trim().isEmpty) {
      setState(
        () => _errorMessage = 'Please enter your business or company name.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(sessionProvider.notifier).requestOtp(phone: phone);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _otpSent = true;
        _submitting = false;
        _errorMessage = null;
      });
      _startCountdown();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = friendlyError(e);
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(
        () => _errorMessage = 'Please enter the 6-digit verification code.',
      );
      return;
    }

    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (phone == null) {
      setState(() => _errorMessage = 'Invalid phone number.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      if (_isRegister) {
        await ref
            .read(sessionProvider.notifier)
            .register(
              phone: phone,
              businessName: _businessController.text.trim(),
              otp: otp,
            );
      } else {
        await ref.read(sessionProvider.notifier).login(phone: phone, otp: otp);
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final prefs = ref.read(localPrefsProvider);
      context.go(prefs.onboarded ? '/home' : '/onboarding');
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (AppEnv.showDemoTools)
            TextButton.icon(
              onPressed: () => context.push('/demo'),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: const Text('Demo mode'),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.page,
              vertical: 12,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_heroMode)
                        ..._hero(t)
                      else ...[
                        Center(
                          child: Column(
                            children: [
                              const Mascot(
                                state: MascotState.welcome,
                                size: 110,
                              ),
                              const SizedBox(height: 12),
                              const BrandWordmark(size: 24),
                              const SizedBox(height: 4),
                              Text(
                                Brand.tagline,
                                style: t.bodyMedium?.copyWith(
                                  color: AppColors.inkSoft,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),

                        AppCard(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(_title, style: t.titleLarge),
                              const SizedBox(height: 6),
                              Text(_subtitle, style: t.bodySmall),
                              const SizedBox(height: 20),

                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.hotSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.hot,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: t.bodySmall?.copyWith(
                                            color: AppColors.hot,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_usePhone)
                                ..._googleSection(t)
                              else if (!_otpSent) ...[
                                if (_isRegister) ...[
                                  TextField(
                                    controller: _businessController,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    autofillHints: const [
                                      AutofillHints.organizationName,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Business name',
                                      hintText:
                                          'e.g. Apex Coaching / Sharma Realty',
                                      prefixIcon: Icon(Icons.business_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber,
                                  ],
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9+ -]'),
                                    ),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Mobile number',
                                    hintText: '98300 12345',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                    prefixText: '+91 ',
                                  ),
                                ),
                                const SizedBox(height: 20),
                                PrimaryButton(
                                  label: _isRegister
                                      ? 'Get Verification Code'
                                      : 'Send OTP',
                                  loading: _submitting,
                                  color: AppColors.brand,
                                  onPressed: _sendOtp,
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: TextButton(
                                    onPressed: _submitting
                                        ? null
                                        : () {
                                            setState(() {
                                              _isRegister = !_isRegister;
                                              _errorMessage = null;
                                            });
                                          },
                                    child: Text(
                                      _isRegister
                                          ? 'Already have an account? Sign in'
                                          : 'New to ${Brand.appName}? Register your business',
                                      style: t.bodySmall?.copyWith(
                                        color: AppColors.brand,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                TextField(
                                  controller: _otpController,
                                  keyboardType: TextInputType.number,
                                  autofocus: true,
                                  autofillHints: const [
                                    AutofillHints.oneTimeCode,
                                  ],
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: t.headlineSmall?.copyWith(
                                    letterSpacing: 8,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: '6-digit OTP',
                                    hintText: '••••••',
                                    prefixIcon: Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                  ),
                                  onSubmitted: (_) => _verifyOtp(),
                                ),
                                const SizedBox(height: 20),
                                PrimaryButton(
                                  label: _isRegister
                                      ? 'Verify & Create Account'
                                      : 'Verify & Enter',
                                  loading: _submitting,
                                  color: AppColors.success,
                                  onPressed: _verifyOtp,
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  runSpacing: 4,
                                  children: [
                                    TextButton(
                                      onPressed: _submitting
                                          ? null
                                          : () {
                                              setState(() {
                                                _otpSent = false;
                                                _otpController.clear();
                                                _errorMessage = null;
                                              });
                                            },
                                      child: const Text('Change number'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          (_resendCountdown > 0 || _submitting)
                                          ? null
                                          : () {
                                              _sendOtp();
                                              _startCountdown();
                                            },
                                      child: Text(
                                        _resendCountdown > 0
                                            ? 'Resend in ${_resendCountdown}s'
                                            : 'Resend code',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          'By continuing, you agree to our Terms of Service & Privacy Policy.',
                          style: t.bodySmall?.copyWith(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The welcome mascot, gently floating.
class _FloatingMascot extends StatefulWidget {
  const _FloatingMascot();
  @override
  State<_FloatingMascot> createState() => _FloatingMascotState();
}

class _FloatingMascotState extends State<_FloatingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.reduced(context) && !_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) => Transform.translate(
      offset: Offset(0, -8 * Curves.easeInOut.transform(_c.value)),
      child: child,
    ),
    child: const Mascot(state: MascotState.welcome, size: 150),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.hotSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.hot, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.hot,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
