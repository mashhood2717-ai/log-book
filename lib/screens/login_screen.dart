import 'package:flutter/material.dart';

import '../config.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/brand.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Db.signIn(_email.text, _password.text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Db.friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(children: [
        const Positioned.fill(
          child: DriftingBlobs(colors: [Brand.sky, Brand.orange, Brand.blue]),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(width: 170)),
                    const SizedBox(height: 22),
                    const FadeSlideIn(index: 6, child: BrandWordmark(size: 30)),
                    const SizedBox(height: 6),
                    FadeSlideIn(
                      index: 7,
                      child: Text(AppConfig.appName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Brand.ink.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 32),
                    FadeSlideIn(index: 8, offset: 40, child: _formCard()),
                    const SizedBox(height: 18),
                    Text('Accounts are created by your admin.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Brand.blue.withValues(alpha: 0.12),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sign in',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                  labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _hide,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter password' : null,
              onFieldSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 22),
            _GradientButton(
              onPressed: _busy ? null : _login,
              busy: _busy,
              label: 'Sign in',
            ),
          ],
        ),
      ),
    );
  }
}

/// Big brand-gradient button with a press-down effect.
class _GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool busy;
  final String label;
  const _GradientButton(
      {required this.onPressed, required this.busy, required this.label});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: widget.onPressed == null && !widget.busy ? 0.5 : 1,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: Brand.blueGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Brand.blue.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.busy
                  ? const SizedBox(
                      key: ValueKey('busy'),
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text(widget.label,
                      key: const ValueKey('label'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}
