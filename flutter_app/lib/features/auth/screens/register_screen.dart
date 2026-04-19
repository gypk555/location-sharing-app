import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/password_breach_indicator.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _confirmPasswordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Password breach check state
  String _lastCheckedPassword = '';
  bool _hasCheckedBreach = false;

  @override
  void initState() {
    super.initState();
    // Reset breach check state when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(passwordBreachCheckProvider.notifier).reset();
    });

    // Check breach when confirm password field is focused
    _confirmPasswordFocusNode.addListener(_onConfirmPasswordFocus);
  }

  /// Trigger breach check when user focuses on confirm password field
  void _onConfirmPasswordFocus() {
    if (_confirmPasswordFocusNode.hasFocus && !_hasCheckedBreach) {
      final password = _passwordController.text;
      if (password.length >= 8) {
        _hasCheckedBreach = true;
        _checkPasswordBreach(password);
      }
    }
  }

  @override
  void dispose() {
    // Reset breach state to prevent stale data on next visit
    ref.read(passwordBreachCheckProvider.notifier).reset();
    // Clean up focus node
    _confirmPasswordFocusNode.removeListener(_onConfirmPasswordFocus);
    _confirmPasswordFocusNode.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Handle password field changes - reset breach check flag
  void _onPasswordChanged(String value) {
    // Reset breach check flag so it re-checks when confirm field is focused
    _hasCheckedBreach = false;

    // Clear indicator if password doesn't meet basic requirements
    if (value.length < 8) {
      ref.read(passwordBreachCheckProvider.notifier).reset();
    }
  }

  /// Check password against HIBP with race condition handling
  Future<void> _checkPasswordBreach(String password) async {
    // Check mounted BEFORE making API call to prevent unnecessary requests
    if (!mounted) return;

    _lastCheckedPassword = password;

    ref.read(passwordBreachCheckProvider.notifier).setChecking();

    final result = await ref
        .read(passwordBreachServiceProvider)
        .checkPassword(password);

    // Race condition fix: Only update if password hasn't changed
    if (_lastCheckedPassword != password) return;
    if (!mounted) return;

    ref.read(passwordBreachCheckProvider.notifier).setResult(result);
  }

  /// Retry breach check (for error state)
  void _retryBreachCheck() {
    final password = _passwordController.text;
    if (password.length >= 8) {
      _checkPasswordBreach(password);
    }
  }

  String? _validateName(String? value) {
    return Validators.validateName(value);
  }

  String? _validateEmail(String? value) {
    return Validators.validateEmail(value);
  }

  String? _validatePassword(String? value) {
    return Validators.validatePassword(value);
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final breachState = ref.read(passwordBreachCheckProvider);

    // Show warning dialog if password is breached (user preference: warn but allow)
    if (breachState.isBreached) {
      final proceed = await _showBreachWarningDialog();
      if (!proceed) return;
    }

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final password = _passwordController.text;

    await ref
        .read(authStateProvider.notifier)
        .registerWithEmail(email, password, name);

    // Check mounted immediately after async gap to prevent crash
    if (!mounted) return;

    final authState = ref.read(authStateProvider);

    // Handle duplicate email via error response (prevents user enumeration)
    if (authState.error != null &&
        (authState.error!.toLowerCase().contains('already') ||
         authState.error!.toLowerCase().contains('exists') ||
         authState.error!.toLowerCase().contains('registered'))) {
      _showEmailExistsDialog();
      return;
    }

    if (authState.isAuthenticated) {
      context.go('/');
    }
  }

  /// Show dialog when email is already registered
  void _showEmailExistsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.email, color: Colors.blue, size: 48),
        title: const Text('Email Already Registered'),
        content: const Text(
          'This email is already registered. Please log in instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/login');
            },
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  /// Show warning dialog when user tries to register with a breached password
  Future<bool> _showBreachWarningDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.warning_amber, color: Colors.orange, size: 48),
            title: const Text('Password Found in Data Breach'),
            content: const Text(
              'This password has appeared in known data breaches and may be compromised.\n\n'
              'For your safety, we strongly recommend choosing a different password.\n\n'
              'Do you want to continue anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Choose Different Password'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final breachState = ref.watch(passwordBreachCheckProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // Header
                const Icon(
                  Icons.person_add,
                  size: 64,
                  color: Color(0xFFE91E63), // AppTheme.primaryColor
                ),
                const SizedBox(height: 16),
                Text(
                  'Create Account',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign up to get started with Safety App',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Name field
                TextFormField(
                  controller: _nameController,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: Validators.maxNameLength,
                  inputFormatters: [
                    Validators.nameInputFormatter,
                    Validators.noEmojiFormatter,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    hintText: 'Enter your full name',
                    counterText: '', // Hide character counter
                  ),
                  validator: _validateName,
                ),

                const SizedBox(height: 16),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: Validators.maxEmailLength,
                  inputFormatters: [Validators.emailInputFormatter],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'Enter your email',
                    counterText: '', // Hide character counter
                  ),
                  validator: _validateEmail,
                ),

                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  maxLength: Validators.maxPasswordLength,
                  onChanged: _onPasswordChanged,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    hintText: 'Min 8 chars with upper, lower, number, special',
                    helperText: 'Use a strong password for your safety',
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
                  validator: _validatePassword,
                ),

                // Password breach indicator
                PasswordBreachIndicator(
                  state: breachState,
                  onRetry: _retryBreachCheck,
                ),

                const SizedBox(height: 16),

                // Confirm Password field
                TextFormField(
                  controller: _confirmPasswordController,
                  focusNode: _confirmPasswordFocusNode,
                  obscureText: _obscureConfirmPassword,
                  maxLength: Validators.maxPasswordLength,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    hintText: 'Confirm your password',
                    counterText: '', // Hide character counter
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword);
                      },
                    ),
                  ),
                  validator: _validateConfirmPassword,
                ),

                const SizedBox(height: 24),

                // Register button
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _handleRegister,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Account'),
                ),

                // Error message
                if (authState.error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.errorColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            authState.error!,
                            style: const TextStyle(color: AppTheme.errorColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Login link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Login'),
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
