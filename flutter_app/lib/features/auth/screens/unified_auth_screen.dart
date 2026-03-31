import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/password_breach_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/password_breach_indicator.dart';

/// Authentication mode for the unified auth screen
enum AuthMode {
  /// Initial state - user enters email first
  initial,
  /// Login mode - email exists, show password field
  login,
  /// Signup mode - new email, show full registration form
  signup,
}

/// Unified authentication screen that combines login and registration.
/// Uses smart email detection to determine the appropriate flow.
class UnifiedAuthScreen extends ConsumerStatefulWidget {
  const UnifiedAuthScreen({super.key});

  @override
  ConsumerState<UnifiedAuthScreen> createState() => _UnifiedAuthScreenState();
}

class _UnifiedAuthScreenState extends ConsumerState<UnifiedAuthScreen> {
  // Current auth mode
  AuthMode _mode = AuthMode.initial;
  bool _isPhoneAuth = false;
  bool _isCheckingEmail = false;

  // Form key
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Focus nodes
  final _confirmPasswordFocusNode = FocusNode();

  // UI state
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Error state
  String? _emailError;
  String? _phoneError;
  String? _passwordError;

  // OTP rate limiting (security: prevent SMS bombing)
  DateTime? _lastOtpSentTime;
  static const _otpCooldown = Duration(seconds: 60);

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

  @override
  void dispose() {
    ref.read(passwordBreachCheckProvider.notifier).reset();
    _confirmPasswordFocusNode.removeListener(_onConfirmPasswordFocus);
    _confirmPasswordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
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

  /// Handle password field changes - reset breach check flag
  void _onPasswordChanged(String value) {
    _hasCheckedBreach = false;
    if (value.length < 8) {
      ref.read(passwordBreachCheckProvider.notifier).reset();
    }
  }

  /// Check password against HIBP with race condition handling
  Future<void> _checkPasswordBreach(String password) async {
    if (!mounted) return;

    _lastCheckedPassword = password;
    ref.read(passwordBreachCheckProvider.notifier).setChecking();

    final result = await ref
        .read(passwordBreachServiceProvider)
        .checkPassword(password);

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

  /// Check email and determine auth mode
  Future<void> _checkEmail() async {
    final email = _emailController.text.trim();

    // Validate email format
    final error = Validators.validateEmail(email);
    if (error != null) {
      setState(() => _emailError = error);
      return;
    }

    setState(() {
      _emailError = null;
      _isCheckingEmail = true;
    });

    final exists = await ref.read(authServiceProvider).checkEmailExists(email);

    if (!mounted) return;

    setState(() {
      _isCheckingEmail = false;
      _mode = exists ? AuthMode.login : AuthMode.signup;
    });
  }

  /// Reset to initial email entry state
  void _resetToEmail() {
    setState(() {
      _mode = AuthMode.initial;
      _passwordController.clear();
      _confirmPasswordController.clear();
      _nameController.clear();
      _hasCheckedBreach = false;
      _obscurePassword = true;
      _obscureConfirmPassword = true;
      _passwordError = null;
    });
    ref.read(passwordBreachCheckProvider.notifier).reset();
  }

  /// Handle phone login - send OTP
  Future<void> _handlePhoneLogin() async {
    final phone = _phoneController.text.trim();

    final phoneError = Validators.validatePhone(phone);
    if (phoneError != null) {
      setState(() => _phoneError = phoneError);
      return;
    }

    final normalizedPhone = Validators.normalizePhone(phone);

    if (!Validators.isValidE164(normalizedPhone)) {
      setState(() => _phoneError = 'Invalid phone format. Use +91XXXXXXXXXX');
      return;
    }

    // Rate limiting check (security: prevent SMS bombing)
    if (_lastOtpSentTime != null) {
      final elapsed = DateTime.now().difference(_lastOtpSentTime!);
      if (elapsed < _otpCooldown) {
        final remainingSeconds = _otpCooldown.inSeconds - elapsed.inSeconds;
        setState(() => _phoneError =
            'Please wait $remainingSeconds seconds before requesting another OTP');
        return;
      }
    }

    setState(() => _phoneError = null);

    await ref.read(authStateProvider.notifier).sendPhoneOtp(normalizedPhone);
    if (mounted) {
      _lastOtpSentTime = DateTime.now();
      context.push('/otp', extra: normalizedPhone);
    }
  }

  /// Handle email login
  Future<void> _handleEmailLogin() async {
    final password = _passwordController.text;

    // Validate password with user feedback
    if (password.isEmpty) {
      setState(() => _passwordError = 'Please enter your password');
      return;
    }

    if (password.length < 8) {
      setState(() => _passwordError = 'Password must be at least 8 characters');
      return;
    }

    setState(() => _passwordError = null);

    final email = _emailController.text.trim();

    // Check password breach BEFORE login (while widget is still mounted)
    // This avoids race condition with router navigation
    final breachResult = await ref
        .read(passwordBreachServiceProvider)
        .checkPassword(password);

    // Now perform login
    await ref.read(authStateProvider.notifier).loginWithEmail(email, password);

    // After login, check if we should show breach warning
    // (works even if widget unmounted - provider operations are still valid)
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated && breachResult.isBreached) {
      // Load user-specific preference
      await ref.read(dontShowBreachWarningProvider.notifier).loadForUser(authState.user!.id);
      if (!ref.read(dontShowBreachWarningProvider)) {
        ref.read(showBreachWarningProvider.notifier).state = true;
      }
    }
  }

  /// Handle registration
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final breachState = ref.read(passwordBreachCheckProvider);

    // Show warning dialog if password is breached
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

    if (!mounted) return;

    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      context.go('/');
    }
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

  // Validation methods
  String? _validateName(String? value) => Validators.validateName(value);
  String? _validatePassword(String? value) => Validators.validatePassword(value);

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final breachState = ref.watch(passwordBreachCheckProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // Logo and title
                const Icon(
                  Icons.shield,
                  size: 80,
                  color: Color(0xFFE91E63),
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
                const SizedBox(height: 8),
                Text(
                  'Sign in or create an account',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Phone/Email toggle
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Phone')),
                    ButtonSegment(value: false, label: Text('Email')),
                  ],
                  selected: {_isPhoneAuth},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _isPhoneAuth = selection.first;
                      _mode = AuthMode.initial;
                      _emailError = null;
                      _phoneError = null;
                    });
                    ref.read(passwordBreachCheckProvider.notifier).reset();
                  },
                ),

                const SizedBox(height: 24),

                // Form content based on mode
                if (_isPhoneAuth)
                  _buildPhoneForm(authState)
                else
                  _buildEmailForm(authState, breachState),

                const SizedBox(height: 32),

                // Social login section
                _buildSocialLogin(authState),

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
                        Icon(Icons.error_outline, color: AppTheme.errorColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            authState.error!,
                            style: TextStyle(color: AppTheme.errorColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build phone authentication form
  Widget _buildPhoneForm(AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            counterText: '',
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
      ],
    );
  }

  /// Build email authentication form (unified login/signup)
  Widget _buildEmailForm(AuthState authState, PasswordBreachCheckState breachState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Email field - always visible
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          maxLength: Validators.maxEmailLength,
          inputFormatters: [Validators.emailInputFormatter],
          enabled: _mode == AuthMode.initial,
          onChanged: (_) {
            if (_emailError != null) {
              setState(() => _emailError = null);
            }
          },
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            hintText: 'your@email.com',
            helperText: _mode == AuthMode.initial
                ? "We'll check if you have an account"
                : null,
            errorText: _emailError,
            counterText: '',
            suffixIcon: _mode != AuthMode.initial
                ? IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: _resetToEmail,
                    tooltip: 'Use different email',
                  )
                : null,
          ),
        ),

        // Mode-specific content with animation
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildModeSpecificContent(authState, breachState),
        ),
      ],
    );
  }

  /// Build content based on current auth mode
  Widget _buildModeSpecificContent(AuthState authState, PasswordBreachCheckState breachState) {
    switch (_mode) {
      case AuthMode.initial:
        return _buildInitialMode(authState);
      case AuthMode.login:
        return _buildLoginMode(authState);
      case AuthMode.signup:
        return _buildSignupMode(authState, breachState);
    }
  }

  /// Initial mode - Continue button to check email
  Widget _buildInitialMode(AuthState authState) {
    return Column(
      key: const ValueKey('initial'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isCheckingEmail ? null : _checkEmail,
          child: _isCheckingEmail
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }

  /// Login mode - password field only
  Widget _buildLoginMode(AuthState authState) {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Welcome back!',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
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
            prefixIcon: const Icon(Icons.lock_outline),
            counterText: '',
            errorText: _passwordError,
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
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resetToEmail,
          child: const Text('Use different email'),
        ),
      ],
    );
  }

  /// Signup mode - full registration form
  Widget _buildSignupMode(AuthState authState, PasswordBreachCheckState breachState) {
    return Column(
      key: const ValueKey('signup'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Create your account',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
        ),
        const SizedBox(height: 16),

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
            counterText: '',
          ),
          validator: _validateName,
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
            counterText: '',
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
            counterText: '',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
          ),
          validator: _validateConfirmPassword,
        ),

        const SizedBox(height: 24),

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
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resetToEmail,
          child: const Text('Use different email'),
        ),
      ],
    );
  }

  /// Build social login section
  Widget _buildSocialLogin(AuthState authState) {
    return Column(
      children: [
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

        // Google Sign In
        OutlinedButton.icon(
          onPressed: authState.isLoading
              ? null
              : () => ref.read(authStateProvider.notifier).signInWithGoogle(),
          icon: const Icon(Icons.g_mobiledata, size: 24),
          label: const Text('Continue with Google'),
        ),

        const SizedBox(height: 12),

        // Apple Sign In
        OutlinedButton.icon(
          onPressed: authState.isLoading
              ? null
              : () => ref.read(authStateProvider.notifier).signInWithApple(),
          icon: const Icon(Icons.apple, size: 24),
          label: const Text('Continue with Apple'),
        ),
      ],
    );
  }
}
