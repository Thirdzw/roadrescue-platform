import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';
import 'demo_account_screen.dart';

class AccountLoginScreen extends StatefulWidget {
  final Future<void> Function(String email, String password) onLogin;
  final ValueChanged<DemoAccountMode> onOpenDemo;
  final DemoAccountMode? initialDemoMode;

  const AccountLoginScreen({
    super.key,
    required this.onLogin,
    required this.onOpenDemo,
    this.initialDemoMode,
  });

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _verificationCode = TextEditingController();
  bool _submitting = false;
  bool _showPassword = false;
  bool _verificationStep = false;
  DemoAccountMode? _pendingDemoMode;
  String? _error;

  @override
  void initState() {
    super.initState();
    final mode = widget.initialDemoMode;
    if (mode != null) {
      _email.text = DemoAccountCredentials.emailFor(mode);
      _password.text = DemoAccountCredentials.passwordFor(mode);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _verificationCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_verificationStep) {
        if (_verificationCode.text.trim() !=
            DemoAccountCredentials.verificationCode) {
          setState(() {
            _submitting = false;
            _error = 'Verification code is incorrect.';
          });
          return;
        }
        final mode = _pendingDemoMode;
        if (mode == null) {
          throw StateError('The demo account verification has expired.');
        }
        widget.onOpenDemo(mode);
        if (mounted) Navigator.of(context).pop();
        return;
      }

      final demoMode = DemoAccountCredentials.modeForEmail(_email.text);
      if (demoMode != null) {
        if (_password.text != DemoAccountCredentials.passwordFor(demoMode)) {
          setState(() {
            _submitting = false;
            _error = 'Demo email or password is incorrect.';
          });
          return;
        }
        setState(() {
          _submitting = false;
          _pendingDemoMode = demoMode;
          _verificationStep = true;
        });
        return;
      }

      await widget.onLogin(_email.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _messageFor(error);
      });
    }
  }

  String _messageFor(Object error) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Email or password is incorrect.',
        'invalid-email' => 'Enter a valid email address.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        'network-request-failed' => 'Check your internet connection and retry.',
        'operation-not-allowed' =>
          'Email and password sign-in is not enabled for this app.',
        _ => 'Could not sign in: ${error.message ?? error.code}',
      };
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Log in to RoadRescue')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.car_crash_rounded,
                        color: C.navy, size: 52),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: C.dark,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use your account details, or sign in to a demo account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 26),
                    if (_verificationStep) ...[
                      Text(
                        'Step 2 of 2 · Verify ${_email.text.trim()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: C.dark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _verificationCode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: '6-digit demo verification code',
                          prefixIcon: Icon(Icons.verified_user_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) == 6
                            ? null
                            : 'Enter the 6-digit verification code.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Demo verification code: '
                        '${DemoAccountCredentials.verificationCode}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => setState(() {
                                  _verificationStep = false;
                                  _pendingDemoMode = null;
                                  _verificationCode.clear();
                                  _error = null;
                                }),
                        child: const Text('Back to email and password'),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (!email.contains('@') ||
                              email.endsWith('@') ||
                              email.startsWith('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFB42318)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: C.navy,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_verificationStep
                              ? 'Verify & continue'
                              : 'Log in'),
                    ),
                    if (!_verificationStep) ...[
                      const SizedBox(height: 20),
                      _demoCredentials(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _demoCredentials() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Demo sign-in details',
              style: TextStyle(fontWeight: FontWeight.w700, color: C.dark),
            ),
            SizedBox(height: 8),
            Text(
              'Motorist: ${DemoAccountCredentials.motoristEmail}\n'
              'Password: ${DemoAccountCredentials.motoristPassword}',
            ),
            SizedBox(height: 6),
            Text(
              'Provider: ${DemoAccountCredentials.providerEmail}\n'
              'Password: ${DemoAccountCredentials.providerPassword}',
            ),
            SizedBox(height: 8),
            Text(
              'Demo accounts use a local two-step preview and do not create '
              'or authenticate a Firebase account.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      );
}

class DemoAccountCredentials {
  static const motoristEmail = 'motorist.demo@roadrescue.app';
  static const motoristPassword = 'MotoristDemo!2026';
  static const providerEmail = 'provider.demo@roadrescue.app';
  static const providerPassword = 'ProviderDemo!2026';
  static const verificationCode = '246810';

  static DemoAccountMode? modeForEmail(String email) {
    return switch (email.trim().toLowerCase()) {
      motoristEmail => DemoAccountMode.motorist,
      providerEmail => DemoAccountMode.provider,
      _ => null,
    };
  }

  static String emailFor(DemoAccountMode mode) =>
      mode == DemoAccountMode.motorist ? motoristEmail : providerEmail;

  static String passwordFor(DemoAccountMode mode) =>
      mode == DemoAccountMode.motorist ? motoristPassword : providerPassword;
}
