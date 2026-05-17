import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

const _kAccent = Color(0xFF0891B2);
const _kTextHigh = Color(0xFF0F172A);
const _kTextMid = Color(0xFF64748B);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;
  bool _showTestLogin = false;
  final _idController = TextEditingController(text: 'admin');
  final _pwController = TextEditingController(text: 'admin');

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  Future<void> _signIn(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('로그인 실패: $e'),
              backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = ref.read(authServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // ── 로고 ──
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _kAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.sports_esports,
                  size: 44,
                  color: _kAccent,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '오늘의 LCK',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _kTextHigh,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'LCK 경기 일정, 순위, 승부예측\n모두 한 곳에서',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _kTextMid, fontSize: 14, height: 1.5),
              ),
              const Spacer(flex: 2),
              // ── 로그인 버튼들 ──
              if (_loading)
                const CircularProgressIndicator(color: _kAccent)
              else ...[
                _SocialLoginButton(
                  onTap: () => _signIn(() async {
                    await authService.signInWithGoogle();
                  }),
                  icon: Image.network(
                    'https://www.google.com/favicon.ico',
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.g_mobiledata, size: 24, color: _kTextHigh),
                  ),
                  label: 'Google로 계속하기',
                  backgroundColor: Colors.white,
                  textColor: _kTextHigh,
                  borderColor: _kBorder,
                ),
                const SizedBox(height: 12),
                _SocialLoginButton(
                  onTap: () => _signIn(() async {
                    await authService.signInWithApple();
                  }),
                  icon: const Icon(Icons.apple, size: 22, color: Colors.white),
                  label: 'Apple로 계속하기',
                  backgroundColor: _kTextHigh,
                  textColor: Colors.white,
                ),
              ],
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () =>
                    setState(() => _showTestLogin = !_showTestLogin),
                child: const Text(
                  '테스트 로그인',
                  style: TextStyle(color: _kTextLow, fontSize: 12),
                ),
              ),
              if (_showTestLogin) ...[
                const SizedBox(height: 12),
                _TestTextField(controller: _idController, hint: '아이디'),
                const SizedBox(height: 8),
                _TestTextField(
                    controller: _pwController,
                    hint: '비밀번호',
                    obscure: true),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _signIn(() async {
                              await authService.signInWithTestAccount(
                                _idController.text,
                                _pwController.text,
                              );
                            }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('로그인',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '로그인하면 이용약관 및 개인정보처리방침에 동의하는 것으로 간주됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kTextLow, fontSize: 11),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const _TestTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: _kTextHigh, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextLow),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;

  const _SocialLoginButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          side: borderColor != null
              ? BorderSide(color: borderColor!)
              : null,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
