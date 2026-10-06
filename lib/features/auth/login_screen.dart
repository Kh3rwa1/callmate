import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_env.dart';
import '../../core/config/brand.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/state_views.dart';

/// Authentication Screen: Phone number entry & OTP verification.
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

  Future<void> _sendOtp() async {
    _errorMessage = null;
    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (phone == null) {
      setState(() => _errorMessage = 'Please enter a valid 10-digit mobile number.');
      return;
    }
    if (_isRegister && _businessController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your business or company name.');
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
      setState(() => _errorMessage = 'Please enter the 6-digit verification code.');
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
        await ref.read(sessionProvider.notifier).register(
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.page, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            const Mascot(state: MascotState.welcome, size: 110),
                            const SizedBox(height: 12),
                            const BrandWordmark(size: 24),
                            const SizedBox(height: 4),
                            Text(
                              Brand.tagline,
                              style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
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
                            Text(
                              _otpSent
                                  ? (_isRegister ? 'Verify Registration' : 'Verify OTP')
                                  : (_isRegister ? 'Create Your Account' : 'Sign In to Your Workspace'),
                              style: t.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _otpSent
                                  ? 'Enter the 6-digit code sent to ${PhoneUtils.display(_phoneController.text)}'
                                  : (_isRegister
                                      ? 'Start hiring AI employees for your business'
                                      : 'Enter your phone number to receive a one-time login code'),
                              style: t.bodySmall,
                            ),
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
                                    const Icon(Icons.error_outline_rounded, color: AppColors.hot, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: t.bodySmall?.copyWith(color: AppColors.hot, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (!_otpSent) ...[
                              if (_isRegister) ...[
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
                              ],
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]'))],
                                decoration: const InputDecoration(
                                  labelText: 'Mobile number',
                                  hintText: '98300 12345',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                  prefixText: '+91 ',
                                ),
                              ),
                              const SizedBox(height: 20),
                              PrimaryButton(
                                label: _isRegister ? 'Get Verification Code' : 'Send OTP',
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
                                    style: t.bodySmall?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ] else ...[
                              TextField(
                                controller: _otpController,
                                keyboardType: TextInputType.number,
                                autofocus: true,
                                autofillHints: const [AutofillHints.oneTimeCode],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                textAlign: TextAlign.center,
                                style: t.headlineSmall?.copyWith(letterSpacing: 8),
                                decoration: const InputDecoration(
                                  labelText: '6-digit OTP',
                                  hintText: '••••••',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                                onSubmitted: (_) => _verifyOtp(),
                              ),
                              const SizedBox(height: 20),
                              PrimaryButton(
                                label: _isRegister ? 'Verify & Create Account' : 'Verify & Enter',
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
                                    onPressed: (_resendCountdown > 0 || _submitting)
                                        ? null
                                        : () {
                                            _sendOtp();
                                            _startCountdown();
                                          },
                                    child: Text(
                                      _resendCountdown > 0 ? 'Resend in ${_resendCountdown}s' : 'Resend code',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'By continuing, you agree to our Terms of Service & Privacy Policy.',
                        style: t.bodySmall?.copyWith(fontSize: 11, color: AppColors.inkSoft),
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
