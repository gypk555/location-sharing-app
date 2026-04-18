import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPhoneLogin = true;
  bool _obscurePassword = true;
  String? _phoneError;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    // Clear any MaterialBanners to prevent memory leak
    ScaffoldMessenger.of(context).clearMaterialBanners();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Show a "coming soon" snackbar for providers that aren't wired yet.
  void _showComingSoon(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$provider is coming soon. Please use email or phone.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _clearErrors() {
    setState(() {
      _phoneError = null;
      _emailError = null;
      _passwordError = null;
    });
  }

  Future<void> _handlePhoneLogin() async {
    _clearErrors();
    final phone = _phoneController.text.trim();

    // Validate phone number
    final phoneError = Validators.validatePhone(phone);
    if (phoneError != null) {
      setState(() => _phoneError = phoneError);
      return;
    }

    // Normalize phone number (add country code if needed)
    final normalizedPhone = Validators.normalizePhone(phone);

    // Validate E.164 format after normalization
    if (!Validators.isValidE164(normalizedPhone)) {
      setState(() => _phoneError = 'Invalid phone format. Use +91XXXXXXXXXX');
      return;
    }

    await ref.read(authStateProvider.notifier).sendPhoneOtp(normalizedPhone);
    if (mounted) {
      context.push('/otp', extra: normalizedPhone);
    }
  }

  Future<void> _handleEmailLogin() async {
    _clearErrors();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Validate email
    final emailError = Validators.validateEmail(email);
    if (emailError != null) {
      setState(() => _emailError = emailError);
      return;
    }

    // Validate password is not empty
    if (password.isEmpty) {
      setState(() => _passwordError = 'Please enter your password');
      return;
    }

    // Minimum password length check for login
    if (password.length < 6) {
      setState(() => _passwordError = 'Password must be at least 6 characters');
      return;
    }

    await ref.read(authStateProvider.notifier).loginWithEmail(email, password);

    // Check mounted immediately after async gap to prevent crash
    if (!mounted) return;

    // Check if login was successful
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      // Background breach check after successful login
      _checkPasswordBreachPostLogin(password);
    }

    // Navigation is handled by auth state listener in router
  }

  /// Check password against breach database after successful login.
  /// Shows non-blocking banner if password is compromised.
  Future<void> _checkPasswordBreachPostLogin(String password) async {
    // Store password snapshot to check for race condition
    final passwordSnapshot = password;

    final result = await ref
        .read(passwordBreachServiceProvider)
        .checkPassword(passwordSnapshot);

    // Race condition check: verify password hasn't changed during async gap
    if (_passwordController.text != passwordSnapshot) return;
    if (!mounted) return;

    if (result.isBreached) {
      // Clear any existing banners first
      ScaffoldMessenger.of(context).clearMaterialBanners();
      // Show non-blocking MaterialBanner to warn user
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          backgroundColor: Colors.orange.shade50,
          leading: const Icon(Icons.warning_amber, color: Colors.orange),
          content: const Text(
            'Your password was found in a data breach. '
            'We recommend changing it for your safety.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                // TODO: Navigate to change password screen when implemented
              },
              child: const Text('Change Password'),
            ),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              },
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),

              // Logo and title
              const Icon(
                Icons.shield,
                size: 80,
                color: Color(0xFFE91E63), // AppTheme.primaryColor
              ),
              const SizedBox(height: 16),
              Text(
                'Safety App',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your safety is our priority',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // Toggle buttons
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Phone')),
                  ButtonSegment(value: false, label: Text('Email')),
                ],
                selected: {_isPhoneLogin},
                onSelectionChanged: (selection) {
                  setState(() => _isPhoneLogin = selection.first);
                },
              ),

              const SizedBox(height: 24),

              // Login form
              if (_isPhoneLogin) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: Validators.maxPhoneLength,
                  inputFormatters: [Validators.phoneInputFormatter],
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone),
                    hintText: '+91 98765 43210',
                    helperText: 'Enter 10-digit number or include country code',
                    errorText: _phoneError,
                    errorMaxLines: 2,
                    counterText: '', // Hide character counter
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _handlePhoneLogin,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send OTP'),
                ),
              ] else ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: Validators.maxEmailLength,
                  inputFormatters: [Validators.emailInputFormatter],
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email),
                    hintText: 'your@email.com',
                    errorText: _emailError,
                    counterText: '', // Hide character counter
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  maxLength: Validators.maxPasswordLength,
                  onChanged: (_) {
                    if (_passwordError != null) {
                      setState(() => _passwordError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    errorText: _passwordError,
                    counterText: '', // Hide character counter
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _handleEmailLogin,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),
              ],

              const SizedBox(height: 32),

              // Social login
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 24),

              // Google Sign In — OAuth not yet wired; gated to prevent fake
              // demo sessions that fail every RLS-protected write (H-1).
              OutlinedButton.icon(
                onPressed: () => _showComingSoon('Google sign-in'),
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Continue with Google'),
              ),

              const SizedBox(height: 12),

              // Apple Sign In — see note above (H-1).
              OutlinedButton.icon(
                onPressed: () => _showComingSoon('Apple sign-in'),
                icon: const Icon(Icons.apple, size: 24),
                label: const Text('Continue with Apple'),
              ),

              if (authState.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  authState.error!,
                  style: TextStyle(color: AppTheme.errorColor),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 24),

              // Register link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text('Register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
