import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/language_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
    // Bir önceki oturumdan kalan eski hata varsa sil
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().clearError();
    });
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = prefs.getBool('remember_me') ?? true;
      if (_rememberMe) {
        _emailCtrl.text = prefs.getString('saved_email') ?? '';
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
    );

    if (!mounted) return;

    if (success) {
      // Save credentials if remember me is checked
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
      if (_rememberMe) {
        await prefs.setString('saved_email', _emailCtrl.text.trim());
      } else {
        await prefs.remove('saved_email');
      }

      // Load favorites
      context
          .read<FavoritesProvider>()
          .loadFavorites(auth.currentUser!.id);
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('sign_in_hint'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // Logo / branding
                Center(
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    context.tr('welcome_back'),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                Center(
                  child: Text(
                    context.tr('sign_in_subtitle'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),

                // Error banner
                if (auth.error != null) ...[
                  _ErrorBanner(message: auth.error!),
                  const SizedBox(height: 16),
                ],

                // Email
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('email'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return context.tr('email_required');
                    if (!v.contains('@')) return context.tr('invalid_email');
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: context.tr('password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return context.tr('password_required');
                    if (v.length < 6) return context.tr('password_too_short');
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                // Remember Me & Forgot Password
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(context.tr('remember_me')),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(context.tr('loading')),
                        ));
                      },
                      child: Text(context.tr('forgot_password')),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Submit
                auth.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submit,
                          child: Text(context.tr('sign_in_hint')),
                        ),
                      ),

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(context.tr('no_account')),
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: Text(context.tr('create_one')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  bool get _isNetworkError =>
      message.contains('uyku') ||
      message.contains('bağlanamadı') ||
      message.contains('Restore');

  @override
  Widget build(BuildContext context) {
    final color = _isNetworkError
        ? const Color(0xFFE67E22) // turuncu — ağ uyarısı
        : Theme.of(context).colorScheme.error; // kırmızı — auth hatası

    final bgColor = color.withOpacity(0.08);
    final borderColor = color.withOpacity(0.25);
    final icon = _isNetworkError ? Icons.wifi_off_rounded : Icons.error_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13, height: 1.5),
            ),
          ),
          GestureDetector(
            onTap: () => context.read<AuthProvider>().clearError(),
            child: Icon(Icons.close, color: color.withOpacity(0.6), size: 18),
          ),
        ],
      ),
    );
  }
}
