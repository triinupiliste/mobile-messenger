import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isResendingVerification = false;
  String? _errorMessage;

  void _clearLoginFeedback() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
    context.read<AuthProvider>().clearLoginFeedback();
  }

  Future<void> _openRegistration() async {
    _clearLoginFeedback();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (!mounted) return;
    _clearLoginFeedback();
  }

  Future<void> _openForgotPassword() async {
    _clearLoginFeedback();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
    if (!mounted) return;
    _clearLoginFeedback();
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final error = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (error != null) {
      setState(() {
        _errorMessage = error;
      });
    }
  }

  Future<void> _resendVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isResendingVerification = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final message = await authProvider.resendVerificationEmail(email);
    if (!mounted) return;
    setState(() => _isResendingVerification = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? 'Verification email sent.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.chat_bubble_rounded,
                    size: 80, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Welcome Back!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to continue messaging',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.errorBackground,
                      border: Border.all(color: AppColors.errorBorder),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                if (context.watch<AuthProvider>().emailVerificationRequired)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      onPressed:
                          _isResendingVerification ? null : _resendVerification,
                      icon: _isResendingVerification
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mark_email_unread_outlined),
                      label: const Text('Resend verification email'),
                    ),
                  ),
                TextFormField(
                  controller: _emailController,
                  onChanged: (_) => _clearLoginFeedback(),
                  decoration: const InputDecoration(
                      labelText: 'Email', prefixIcon: Icon(Icons.email)),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      value!.isEmpty ? 'Please enter your email' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  onChanged: (_) => _clearLoginFeedback(),
                  decoration: const InputDecoration(
                      labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                  obscureText: true,
                  validator: (value) =>
                      value!.isEmpty ? 'Please enter your password' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _openForgotPassword,
                    child: const Text('Forgot password?',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: AppColors.onPrimary)
                      : const Text('Log In',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _openRegistration,
                  child: Text("Don't have an account? Sign Up",
                      style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
