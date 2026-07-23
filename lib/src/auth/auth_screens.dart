import 'dart:async';
import 'dart:math' as math;

import 'package:budget_ai/src/auth/auth_service.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:budget_ai/src/settings/user_name_settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:toastification/toastification.dart';
import 'package:url_launcher/url_launcher.dart';

enum _AuthPage { login, register, verification, forgotPassword }

class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key});

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  _AuthPage _page = _AuthPage.login;
  String _email = '';
  String _password = '';

  void _show(_AuthPage page, {String? email, String? password}) {
    HapticFeedback.selectionClick();
    setState(() {
      _page = page;
      if (email != null) _email = email;
      if (password != null) _password = password;
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (_page) {
      _AuthPage.login => LoginScreen(
        key: const ValueKey('login'),
        initialEmail: _email,
        onCreateAccount: (email) => _show(_AuthPage.register, email: email),
        onForgotPassword: (email) =>
            _show(_AuthPage.forgotPassword, email: email),
        onNeedsVerification: (email, password) =>
            _show(_AuthPage.verification, email: email, password: password),
      ),
      _AuthPage.register => RegisterScreen(
        key: const ValueKey('register'),
        initialEmail: _email,
        onBackToLogin: (email) => _show(_AuthPage.login, email: email),
        onRegistered: (email, password) =>
            _show(_AuthPage.verification, email: email, password: password),
      ),
      _AuthPage.verification => EmailVerificationScreen(
        key: ValueKey('verification-$_email'),
        email: _email,
        password: _password,
        onUseDifferentEmail: () =>
            _show(_AuthPage.register, email: _email, password: ''),
        onBackToLogin: () =>
            _show(_AuthPage.login, email: _email, password: ''),
      ),
      _AuthPage.forgotPassword => ForgotPasswordScreen(
        key: const ValueKey('forgot-password'),
        initialEmail: _email,
        onBackToLogin: (email) => _show(_AuthPage.login, email: email),
      ),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.035, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class AuthLoadingScreen extends StatelessWidget {
  const AuthLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'BUDGET AI',
      title: 'Securing your session',
      subtitle: 'Restoring your account and preparing your private workspace.',
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.initialEmail,
    required this.onCreateAccount,
    required this.onForgotPassword,
    required this.onNeedsVerification,
  });

  final String initialEmail;
  final ValueChanged<String> onCreateAccount;
  final ValueChanged<String> onForgotPassword;
  final void Function(String email, String password) onNeedsVerification;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _working) return;
    setState(() => _working = true);
    try {
      await AuthService.instance.signIn(
        email: _email.text,
        password: _password.text,
      );
      HapticFeedback.lightImpact();
    } on AuthException catch (error) {
      if (error.message.toLowerCase().contains('email not confirmed')) {
        widget.onNeedsVerification(_email.text.trim(), _password.text);
        return;
      }
      if (mounted) _showAuthError(context, error);
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'WELCOME BACK',
      title: 'Sign in to Budget AI',
      subtitle:
          'Continue to your private finance assistant and protected AI access.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _email,
                label: 'Email',
                hint: 'you@example.com',
                icon: CupertinoIcons.mail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _password,
                label: 'Password',
                hint: 'Your password',
                icon: CupertinoIcons.lock,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password.'
                    : null,
                trailing: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _working
                      ? null
                      : () => widget.onForgotPassword(_email.text.trim()),
                  child: const Text('Forgot password?'),
                ),
              ),
              AuthPrimaryButton(
                label: 'Sign in',
                icon: CupertinoIcons.arrow_right,
                working: _working,
                onPressed: _submit,
              ),
              const SizedBox(height: 10),
              _AuthSecondaryAction(
                prompt: 'New to Budget AI?',
                action: 'Create account',
                onPressed: _working
                    ? null
                    : () => widget.onCreateAccount(_email.text.trim()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.initialEmail,
    required this.onBackToLogin,
    required this.onRegistered,
  });

  final String initialEmail;
  final ValueChanged<String> onBackToLogin;
  final void Function(String email, String password) onRegistered;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: UserNameSettingsService.instance.current,
    );
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _working) return;
    setState(() => _working = true);
    try {
      final response = await AuthService.instance.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      HapticFeedback.lightImpact();
      if (response.session == null && mounted) {
        widget.onRegistered(_email.text.trim(), _password.text);
      }
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'CREATE YOUR ACCOUNT',
      title: 'Start securely',
      subtitle:
          'Your finance records stay on this device. Your account protects AI usage.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _name,
                label: 'Name',
                hint: 'What should Budget AI call you?',
                icon: CupertinoIcons.person,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter your name.'
                    : null,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _email,
                label: 'Email',
                hint: 'you@example.com',
                icon: CupertinoIcons.mail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newUsername],
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _password,
                label: 'Password',
                hint: '8+ characters',
                icon: CupertinoIcons.lock,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: _validatePassword,
                trailing: IconButton(
                  tooltip: _obscurePassword
                      ? 'Show passwords'
                      : 'Hide passwords',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const _PasswordHint(),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _confirmPassword,
                label: 'Confirm password',
                hint: 'Repeat your password',
                icon: CupertinoIcons.lock_shield,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _submit(),
                validator: (value) =>
                    value != _password.text ? 'Passwords do not match.' : null,
              ),
              const SizedBox(height: 18),
              AuthPrimaryButton(
                label: 'Create account',
                icon: CupertinoIcons.arrow_right,
                working: _working,
                onPressed: _submit,
              ),
              const SizedBox(height: 10),
              _AuthSecondaryAction(
                prompt: 'Already have an account?',
                action: 'Sign in',
                onPressed: _working
                    ? null
                    : () => widget.onBackToLogin(_email.text.trim()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    super.key,
    required this.email,
    required this.password,
    required this.onUseDifferentEmail,
    required this.onBackToLogin,
  });

  final String email;
  final String password;
  final VoidCallback onUseDifferentEmail;
  final VoidCallback onBackToLogin;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  Timer? _timer;
  int _cooldown = 60;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCooldown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(silent: true);
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking || widget.password.isEmpty) {
      if (!silent && widget.password.isEmpty) {
        _showAuthToast(
          context,
          'Return to sign in after confirming your email.',
          type: ToastificationType.info,
        );
      }
      return;
    }
    setState(() => _checking = true);
    try {
      await AuthService.instance.signIn(
        email: widget.email,
        password: widget.password,
      );
    } catch (error) {
      if (!silent && mounted) {
        _showAuthError(context, error);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.length != 6 || _checking) {
      _showAuthToast(
        context,
        'Enter the 6-digit code from your email.',
        type: ToastificationType.error,
      );
      return;
    }
    setState(() => _checking = true);
    try {
      await AuthService.instance.verifySignupCode(
        email: widget.email,
        code: code,
      );
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _checking) return;
    setState(() => _checking = true);
    try {
      await AuthService.instance.resendSignupConfirmation(widget.email);
      if (mounted) {
        _showAuthToast(context, 'A new confirmation email was sent.');
        _startCooldown();
      }
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openMail() async {
    final launched = await launchUrl(Uri(scheme: 'mailto'));
    if (!launched && mounted) {
      _showAuthToast(
        context,
        'Open your mail app and find the Budget AI email.',
        type: ToastificationType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'ONE MORE STEP',
      title: 'Check your email',
      subtitle:
          'We sent a secure confirmation to ${_maskedEmail(widget.email)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusCard(
            icon: CupertinoIcons.envelope_badge,
            message:
                'Tap the confirmation link to return here automatically, or enter the 6-digit code.',
          ),
          const SizedBox(height: 18),
          AuthTextField(
            controller: _code,
            label: 'Confirmation code',
            hint: '000000',
            icon: CupertinoIcons.number,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onSubmitted: (_) => _verifyCode(),
          ),
          const SizedBox(height: 12),
          AuthPrimaryButton(
            label: 'Verify code',
            icon: CupertinoIcons.checkmark_shield,
            working: _checking,
            onPressed: _verifyCode,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _checking ? null : _openMail,
            icon: const Icon(CupertinoIcons.mail, size: 18),
            label: const Text('Open mail app'),
          ),
          TextButton(
            onPressed: _checking ? null : () => _check(),
            child: const Text("I've confirmed — check again"),
          ),
          TextButton(
            onPressed: _cooldown == 0 && !_checking ? _resend : null,
            child: Text(
              _cooldown == 0
                  ? 'Resend confirmation email'
                  : 'Resend available in ${_cooldown}s',
            ),
          ),
          const Divider(height: 24),
          _AuthSecondaryAction(
            prompt: 'Wrong email?',
            action: 'Use a different email',
            onPressed: _checking ? null : widget.onUseDifferentEmail,
          ),
          TextButton(
            onPressed: _checking ? null : widget.onBackToLogin,
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.initialEmail,
    required this.onBackToLogin,
  });

  final String initialEmail;
  final ValueChanged<String> onBackToLogin;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _working = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _working) return;
    setState(() => _working = true);
    try {
      await AuthService.instance.sendPasswordRecovery(_email.text);
      if (mounted) {
        setState(() => _sent = true);
        _showAuthToast(context, 'Password reset email sent.');
      }
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'ACCOUNT RECOVERY',
      title: _sent ? 'Check your inbox' : 'Reset your password',
      subtitle: _sent
          ? 'If an account matches that email, a secure reset link is on its way.'
          : 'Enter your email and we will send a secure password reset link.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sent)
              const _StatusCard(
                icon: CupertinoIcons.paperplane,
                message:
                    'Open the link on this device. Budget AI will return to a protected password screen.',
              )
            else ...[
              AuthTextField(
                controller: _email,
                label: 'Email',
                hint: 'you@example.com',
                icon: CupertinoIcons.mail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _submit(),
                validator: _validateEmail,
              ),
              const SizedBox(height: 18),
              AuthPrimaryButton(
                label: 'Send reset link',
                icon: CupertinoIcons.paperplane,
                working: _working,
                onPressed: _submit,
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _working
                  ? null
                  : () => widget.onBackToLogin(_email.text.trim()),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.onCancel});

  final Future<void> Function() onCancel;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _working = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _working) return;
    setState(() => _working = true);
    try {
      await AuthService.instance.updatePassword(_password.text);
      TextInput.finishAutofillContext();
      HapticFeedback.lightImpact();
      if (mounted) _showAuthToast(context, 'Password updated successfully.');
    } catch (error) {
      if (mounted) _showAuthError(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      eyebrow: 'SECURE RECOVERY',
      title: 'Choose a new password',
      subtitle: 'Create a strong password you have not used for this account.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _password,
                label: 'New password',
                hint: '8+ characters',
                icon: CupertinoIcons.lock,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: _validatePassword,
                trailing: IconButton(
                  tooltip: _obscurePassword
                      ? 'Show passwords'
                      : 'Hide passwords',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const _PasswordHint(),
              const SizedBox(height: 12),
              AuthTextField(
                controller: _confirmPassword,
                label: 'Confirm new password',
                hint: 'Repeat your password',
                icon: CupertinoIcons.lock_shield,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (value) =>
                    value != _password.text ? 'Passwords do not match.' : null,
              ),
              const SizedBox(height: 18),
              AuthPrimaryButton(
                label: 'Update password',
                icon: CupertinoIcons.checkmark_shield,
                working: _working,
                onPressed: _submit,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _working ? null : widget.onCancel,
                child: const Text('Cancel and return to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 470),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: BudgetMarkIcon(size: 64),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            eyebrow,
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.highlight,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.7,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            title,
                            style: AppTheme.headingLarge.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontSize: 30,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            subtitle,
                            style: AppTheme.bodyMedium.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 24),
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, progress, _) => CustomPaint(
        painter: _AuthBackdropPainter(
          progress: progress,
          surface: theme.scaffoldBackgroundColor,
          primary: theme.colorScheme.primary,
          accent: AppTheme.highlight,
        ),
      ),
    );
  }
}

class _AuthBackdropPainter extends CustomPainter {
  const _AuthBackdropPainter({
    required this.progress,
    required this.surface,
    required this.primary,
    required this.accent,
  });

  final double progress;
  final Color surface;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(surface, BlendMode.srcOver);
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: 0.12 * progress),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 0.08),
              radius: size.shortestSide * 0.72,
            ),
          );
    canvas.drawRect(Offset.zero & size, paint);

    final center = Offset(size.width * 0.04, size.height * 0.93);
    final radius = size.shortestSide * 0.31 * progress;
    final glowRect = Rect.fromCircle(center: center, radius: radius * 1.08);
    canvas.drawCircle(
      center,
      radius * 1.08,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.11 * progress),
            primary.withValues(alpha: 0.035 * progress),
            primary.withValues(alpha: 0),
          ],
        ).createShader(glowRect),
    );

    for (var index = 0; index < 4; index++) {
      final ringRadius = radius * (0.42 + (index * 0.2));
      canvas.drawCircle(
        center,
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = index.isEven ? 1.35 : 0.8
          ..color = (index.isEven ? accent : primary).withValues(
            alpha: (0.18 - (index * 0.025)) * progress,
          ),
      );
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = accent.withValues(alpha: 0.34 * progress);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.8),
      -math.pi * 0.18,
      math.pi * 0.52,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.58),
      math.pi * 0.82,
      math.pi * 0.38,
      false,
      arcPaint
        ..strokeWidth = 1.7
        ..color = primary.withValues(alpha: 0.24 * progress),
    );

    for (final angle in [-0.18, 0.34, 0.82, 1.2]) {
      final dot =
          center +
          Offset(math.cos(angle * math.pi), math.sin(angle * math.pi)) *
              radius *
              0.8;
      canvas.drawCircle(
        dot,
        2.8 * progress,
        Paint()..color = accent.withValues(alpha: 0.72 * progress),
      );
    }

    canvas.drawCircle(
      center,
      4.5 * progress,
      Paint()..color = accent.withValues(alpha: 0.75 * progress),
    );
  }

  @override
  bool shouldRepaint(covariant _AuthBackdropPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      surface != oldDelegate.surface ||
      primary != oldDelegate.primary ||
      accent != oldDelegate.accent;
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.autofillHints,
    this.validator,
    this.trailing,
    this.onSubmitted,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      autocorrect: false,
      enableSuggestions: !obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: trailing,
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.working,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool working;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: working ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: working
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, size: 18),
                ],
              ),
      ),
    );
  }
}

class _AuthSecondaryAction extends StatelessWidget {
  const _AuthSecondaryAction({
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prompt, style: AppTheme.bodySmall),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.highlight, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordHint extends StatelessWidget {
  const _PasswordHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Use 8+ characters with uppercase, lowercase, and a number.',
      style: AppTheme.bodySmall.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
  }
}

void _showAuthToast(
  BuildContext context,
  String message, {
  ToastificationType type = ToastificationType.success,
}) {
  showAppToast(context, message: message, type: type);
}

void _showAuthError(BuildContext context, Object error) {
  _showAuthToast(
    context,
    friendlyAuthError(error),
    type: ToastificationType.error,
  );
}

String? _validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? _validatePassword(String? value) {
  final password = value ?? '';
  if (password.length < 8 ||
      !RegExp('[a-z]').hasMatch(password) ||
      !RegExp('[A-Z]').hasMatch(password) ||
      !RegExp('[0-9]').hasMatch(password)) {
    return 'Password does not meet the requirements.';
  }
  return null;
}

String _maskedEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2 || parts.first.isEmpty) return email;
  final name = parts.first;
  final visible = name.substring(0, name.length.clamp(1, 2));
  return '$visible${'•' * (name.length - visible.length).clamp(2, 8)}@${parts.last}';
}
