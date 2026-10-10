import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_env.dart';
import '../../core/motion/motion.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/brand_widgets.dart';
import '../../core/widgets/mascot.dart';
import '../../core/widgets/settings_sheets.dart';
import '../../core/widgets/state_views.dart';
import '../../data/repositories/repositories.dart';
import '../../l10n/l10n.dart';
import '../../services/auth/google_auth_service.dart';
import 'google_button.dart';

/// Authentication Screen: Google sign-in (default), with phone + OTP behind
/// `PHONE_OTP_LOGIN`.
///
/// Motion: the mascot pops in and floats, the pitch rises in line by line,
/// and moving between Google / registration / phone / code crossfades the
/// form in place. A rejected entry shakes the error banner.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { google, googleRegister, phone, code }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _businessController = TextEditingController();
  final _referralController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => _open(AppEnv.termsUrl);
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => _open(AppEnv.privacyUrl);

  /// Phone + OTP flow instead of Google.
  bool _usePhone = false;

  /// Google account is new: collect business name + contact number.
  bool _googleRegistering = false;

  bool _isRegister = false;
  bool _otpSent = false;
  bool _submitting = false;
  String? _errorMessage;
  int _shakes = 0;

  int _resendCountdown = 30;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Prefill the code this install came with (Play install referrer).
    ref
        .read(installReferralCodeProvider.future)
        .then((code) {
          if (mounted && code != null && _referralController.text.isEmpty) {
            _referralController.text = code;
          }
        })
        .catchError((_) {});
  }

  /// The referral code typed or prefilled, or null when empty.
  String? get _referralCode {
    final code = _referralController.text.trim();
    return code.isEmpty ? null : code;
  }

  @override
  void dispose() {
    _referralController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _businessController.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  _Mode get _mode {
    if (!_usePhone) {
      return _googleRegistering ? _Mode.googleRegister : _Mode.google;
    }
    return _otpSent ? _Mode.code : _Mode.phone;
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Shows [message] in the banner, with a shake and a buzz.
  void _fail(String message) {
    Haptics.warn();
    setState(() {
      _submitting = false;
      _errorMessage = message;
      _shakes++;
    });
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
    final s = context.s;
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
      if (mounted) _fail(friendlyError(e, s));
    }
  }

  Future<void> _finishGoogleRegistration() async {
    final s = context.s;
    final businessName = _businessController.text.trim();
    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (businessName.isEmpty) {
      _fail(s.errBusinessName);
      return;
    }
    if (phone == null) {
      _fail(s.errPhone10);
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .completeGoogleRegistration(
            businessName: businessName,
            phone: phone,
            referralCode: _referralCode,
          );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      context.go('/onboarding');
    } catch (e) {
      if (mounted) _fail(friendlyError(e, s));
    }
  }

  Future<void> _sendOtp() async {
    final s = context.s;
    _errorMessage = null;
    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (phone == null) {
      _fail(s.errPhone10);
      return;
    }
    if (_isRegister && _businessController.text.trim().isEmpty) {
      _fail(s.errBusinessName);
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
      if (mounted) _fail(friendlyError(e, s));
    }
  }

  Future<void> _verifyOtp() async {
    final s = context.s;
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _fail(s.errOtp6);
      return;
    }

    final phone = PhoneUtils.normalize(_phoneController.text.trim());
    if (phone == null) {
      _fail(s.errInvalidPhone);
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
              referralCode: _referralCode,
            );
      } else {
        await ref.read(sessionProvider.notifier).login(phone: phone, otp: otp);
      }
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final prefs = ref.read(localPrefsProvider);
      context.go(prefs.onboarded ? '/home' : '/onboarding');
    } catch (e) {
      if (mounted) _fail(friendlyError(e, s));
    }
  }

  // ------------------------------------------------------------ Layout

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final mode = _mode;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (AppEnv.showDemoTools)
            TextButton.icon(
              onPressed: () => context.push('/demo'),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: Text(s.demoMode),
            ),
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: LanguageChip(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      AnimatedSwitcher(
                        duration: AppMotion.of(context, AppMotion.slow),
                        switchInCurve: AppMotion.emphasized,
                        switchOutCurve: AppMotion.exit,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, ?current],
                        ),
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: mode == _Mode.google
                            ? _hero(context, key: const ValueKey('hero'))
                            : _formCard(context, mode),
                      ),
                      const SizedBox(height: 20),
                      _Terms(
                        termsTap: AppEnv.termsUrl.isEmpty ? null : _termsTap,
                        privacyTap: AppEnv.privacyUrl.isEmpty
                            ? null
                            : _privacyTap,
                        style: t.bodySmall?.copyWith(
                          fontSize: 13,
                          color: AppColors.inkFaint,
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

  /// Signed-out landing: the pitch and the Google button.
  Widget _hero(BuildContext context, {Key? key}) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final points = [
      (Icons.call_rounded, s.loginPointCalls),
      (Icons.local_fire_department_rounded, s.loginPointScores),
      (Icons.verified_user_outlined, s.loginPointSend),
    ];
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Reveal(child: Center(child: BrandWordmark(size: 20))),
        const SizedBox(height: 20),
        const Center(
          child: PopIn(
            delay: Duration(milliseconds: 80),
            duration: Duration(milliseconds: 680),
            child: FloatIdle(
              amplitude: 8,
              child: Mascot(state: MascotState.welcome, size: 150),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Reveal(
          index: 3,
          child: Semantics(
            header: true,
            child: Text(
              s.loginHeadline,
              textAlign: TextAlign.center,
              style: t.displaySmall?.copyWith(
                fontSize: 31,
                height: 1.12,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Reveal(
          index: 4,
          child: Text(
            s.loginLanguages,
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: AppColors.inkFaint),
          ),
        ),
        const SizedBox(height: 24),
        for (final (i, (icon, text)) in points.indexed)
          Reveal(
            index: 5 + i,
            offset: 10,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  IconBubble(
                    size: 32,
                    color: AppColors.brandSoft,
                    child: Icon(icon, size: 17, color: AppColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: t.bodyMedium?.copyWith(
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        _errorArea(),
        Reveal(
          index: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoogleSignInButton(
                loading: _submitting,
                onPressed: _continueWithGoogle,
              ),
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
                    child: Text(s.usePhoneInstead),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Registration and phone sign-in: a card whose contents crossfade
  /// between steps while the card resizes smoothly.
  Widget _formCard(BuildContext context, _Mode mode) {
    final s = context.s;
    final t = Theme.of(context).textTheme;
    final title = switch (mode) {
      _Mode.googleRegister => s.setUpYourBusiness,
      _Mode.code => s.enterCode,
      _Mode.phone => _isRegister ? s.createAccount : s.signIn,
      _Mode.google => s.welcome,
    };
    final subtitle = mode == _Mode.code
        ? '${s.sentTo(PhoneUtils.display(_phoneController.text))}'
              '${AppEnv.flavor != AppFlavor.prod ? s.useTestCode : ''}'
        : null;
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: PopIn(child: Mascot(state: MascotState.welcome, size: 96)),
        ),
        const SizedBox(height: 12),
        const Center(child: BrandWordmark(size: 22)),
        const SizedBox(height: 28),
        AppCard(
          padding: const EdgeInsets.all(22),
          child: AnimatedSize(
            duration: AppMotion.of(context, AppMotion.base),
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwapFade(
                  child: Align(
                    key: ValueKey(title),
                    alignment: Alignment.centerLeft,
                    child: Text(title, style: t.titleLarge),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: t.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
                const SizedBox(height: 20),
                _errorArea(),
                SwapFade(
                  child: KeyedSubtree(
                    key: ValueKey(mode),
                    child: switch (mode) {
                      _Mode.googleRegister => _googleRegisterFields(s),
                      _Mode.phone => _phoneFields(s),
                      _Mode.code => _codeFields(s, t),
                      _Mode.google => const SizedBox.shrink(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The banner opens smoothly and shakes on every rejected attempt.
  Widget _errorArea() => Shake(
    trigger: _shakes,
    child: AnimatedSize(
      duration: AppMotion.of(context, AppMotion.base),
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: _errorMessage == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ErrorBanner(message: _errorMessage!),
            ),
    ),
  );

  /// Editable; prefilled from the install referrer when there is one.
  Widget _referralField(S s) => TextField(
    key: const ValueKey('referral-code-field'),
    controller: _referralController,
    textCapitalization: TextCapitalization.characters,
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
      LengthLimitingTextInputFormatter(12),
    ],
    decoration: InputDecoration(
      labelText: s.referralCodeOptional,
      helperText: s.referralCodeHelper,
      prefixIcon: const Icon(Icons.card_giftcard_outlined),
    ),
  );

  Widget _googleRegisterFields(S s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _businessController,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.organizationName],
        decoration: InputDecoration(
          labelText: s.businessName,
          hintText: s.businessNameHint,
          prefixIcon: const Icon(Icons.business_outlined),
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
        decoration: InputDecoration(
          labelText: s.businessMobile,
          hintText: '98300 12345',
          helperText: s.shownOnFollowUps,
          prefixIcon: const Icon(Icons.phone_outlined),
          prefixText: '+91 ',
        ),
      ),
      const SizedBox(height: 14),
      _referralField(s),
      const SizedBox(height: 20),
      PrimaryButton(
        label: s.createAccountCta,
        loading: _submitting,
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
          child: Text(s.useDifferentGoogle),
        ),
      ),
    ],
  );

  Widget _phoneFields(S s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnimatedSize(
        duration: AppMotion.of(context, AppMotion.base),
        curve: AppMotion.emphasized,
        alignment: Alignment.topCenter,
        child: _isRegister
            ? Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _businessController,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.organizationName],
                      decoration: InputDecoration(
                        labelText: s.businessName,
                        hintText: s.businessNameHint,
                        prefixIcon: const Icon(Icons.business_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _referralField(s),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
      TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ -]')),
        ],
        decoration: InputDecoration(
          labelText: s.mobileNumber,
          hintText: '98300 12345',
          prefixIcon: const Icon(Icons.phone_outlined),
          prefixText: '+91 ',
        ),
      ),
      const SizedBox(height: 20),
      PrimaryButton(
        label: _isRegister ? s.getCode : s.sendOtp,
        loading: _submitting,
        onPressed: _sendOtp,
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: _submitting
              ? null
              : () => setState(() {
                  _isRegister = !_isRegister;
                  _errorMessage = null;
                }),
          child: SwapFade(
            child: Text(
              _isRegister ? s.haveAccount : s.newHere,
              key: ValueKey(_isRegister),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _codeFields(S s, TextTheme t) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
        decoration: InputDecoration(
          labelText: s.otpLabel,
          hintText: '••••••',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
        ),
        onSubmitted: (_) => _verifyOtp(),
      ),
      const SizedBox(height: 20),
      PrimaryButton(
        label: _isRegister ? s.verifyCreate : s.verifyEnter,
        loading: _submitting,
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
                : () => setState(() {
                    _otpSent = false;
                    _otpController.clear();
                    _errorMessage = null;
                  }),
            child: Text(s.changeNumber),
          ),
          TextButton(
            onPressed: (_resendCountdown > 0 || _submitting)
                ? null
                : () {
                    _sendOtp();
                    _startCountdown();
                  },
            child: Text(
              _resendCountdown > 0
                  ? s.resendIn(_resendCountdown)
                  : s.resendCode,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// "By continuing, you agree to our Terms & Privacy Policy." The two names
/// are links once their URLs are configured.
class _Terms extends StatelessWidget {
  const _Terms({
    required this.termsTap,
    required this.privacyTap,
    required this.style,
  });
  final GestureRecognizer? termsTap;
  final GestureRecognizer? privacyTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    TextStyle? link(GestureRecognizer? tap) => tap == null
        ? null
        : TextStyle(
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.inkFaint,
          );
    return Center(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: s.termsPrefix),
            TextSpan(
              text: s.terms,
              recognizer: termsTap,
              style: link(termsTap),
            ),
            TextSpan(text: s.and),
            TextSpan(
              text: s.privacyPolicy,
              recognizer: privacyTap,
              style: link(privacyTap),
            ),
            TextSpan(text: s.termsSuffix),
          ],
        ),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.hotSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.hot, size: 20),
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
    ),
  );
}
