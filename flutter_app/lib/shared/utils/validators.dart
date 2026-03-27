/// Input validation utilities for the Safety App.
/// Critical for ensuring SOS alerts reach valid phone numbers.
class Validators {
  Validators._();

  // Phone number regex - supports international format
  // Allows: +91 98765 43210, +1-234-567-8900, +44 20 7946 0958
  static final _phoneRegex = RegExp(
    r'^\+?[1-9]\d{0,3}[-.\s]?\(?\d{1,4}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,9}$',
  );

  // Indian phone number regex (10 digits starting with 6-9)
  static final _indianPhoneRegex = RegExp(r'^[6-9]\d{9}$');

  // Email regex - simplified but effective
  static final _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
  );

  // Disposable email domains to block
  static const _disposableEmailDomains = [
    'tempmail.com',
    '10minutemail.com',
    'guerrillamail.com',
    'mailinator.com',
    'throwaway.email',
    'temp-mail.org',
    'fakeinbox.com',
  ];

  /// Validate phone number format.
  /// Returns error message or null if valid.
  /// [value] - The phone number to validate
  /// [allowEmpty] - If true, empty values return null (valid)
  static String? validatePhone(String? value, {bool allowEmpty = false}) {
    if (value == null || value.trim().isEmpty) {
      return allowEmpty ? null : 'Phone number is required';
    }

    // Remove spaces, dashes, and parentheses for validation
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Check for minimum length
    if (cleaned.length < 10) {
      return 'Phone number is too short';
    }

    // Check for maximum length
    if (cleaned.length > 15) {
      return 'Phone number is too long';
    }

    // If starts with +, validate international format
    if (cleaned.startsWith('+')) {
      if (!_phoneRegex.hasMatch(value)) {
        return 'Please enter a valid phone number';
      }
    } else {
      // Assume Indian number if no country code
      final digitsOnly = cleaned.replaceAll(RegExp(r'[^\d]'), '');
      if (digitsOnly.length == 10) {
        if (!_indianPhoneRegex.hasMatch(digitsOnly)) {
          return 'Please enter a valid 10-digit mobile number';
        }
      } else {
        return 'Please include country code (e.g., +91) or enter 10-digit number';
      }
    }

    return null;
  }

  /// Normalize phone number for storage/sending SMS.
  /// Adds +91 prefix for Indian numbers without country code.
  static String normalizePhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // If already has country code, return as is
    if (cleaned.startsWith('+')) {
      return cleaned;
    }

    // Add Indian country code for 10-digit numbers
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length == 10) {
      return '+91$digitsOnly';
    }

    return cleaned;
  }

  /// Validate email address format.
  /// Returns error message or null if valid.
  static String? validateEmail(String? value, {bool allowEmpty = false}) {
    if (value == null || value.trim().isEmpty) {
      return allowEmpty ? null : 'Please enter your email';
    }

    final email = value.trim().toLowerCase();

    // Check length
    if (email.length > 254) {
      return 'Email address is too long';
    }

    // Check format
    if (!_emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    // Check for consecutive dots
    if (email.contains('..')) {
      return 'Invalid email format';
    }

    // Block disposable email services for safety app
    final domain = email.split('@').last;
    if (_disposableEmailDomains.contains(domain)) {
      return 'Please use a permanent email address';
    }

    return null;
  }

  /// Validate password strength.
  /// Returns error message or null if valid.
  /// Requires: 8+ chars, uppercase, lowercase, number, special char
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }

    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain an uppercase letter';
    }

    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain a lowercase letter';
    }

    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain a number';
    }

    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain a special character';
    }

    // Check against common weak passwords
    final commonPasswords = [
      'password',
      '12345678',
      'qwerty123',
      'admin123',
      'letmein',
      'welcome1',
    ];
    if (commonPasswords.any((p) => value.toLowerCase().contains(p))) {
      return 'Password is too common, please choose a stronger one';
    }

    return null;
  }

  /// Get password strength indicator.
  static PasswordStrength getPasswordStrength(String password) {
    if (password.isEmpty) return PasswordStrength.none;

    int score = 0;

    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;

    if (score <= 2) return PasswordStrength.weak;
    if (score <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  /// Validate name input.
  /// Returns error message or null if valid.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }

    final trimmed = value.trim();

    if (trimmed.length < 2) {
      return 'Name must be at least 2 characters';
    }

    if (trimmed.length > 50) {
      return 'Name is too long';
    }

    // Allow letters, spaces, hyphens, apostrophes, and dots
    if (!RegExp(r"^[a-zA-Z\s\-'\.]+$").hasMatch(trimmed)) {
      return 'Name contains invalid characters';
    }

    return null;
  }

  /// Sanitize name input by removing invalid characters.
  static String sanitizeName(String name) {
    // Remove leading/trailing whitespace
    String cleaned = name.trim();

    // Remove control characters
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // Collapse multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Limit length
    if (cleaned.length > 50) {
      cleaned = cleaned.substring(0, 50);
    }

    return cleaned;
  }

  /// Validate OTP format (6 digits only).
  static String? validateOtp(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter the OTP';
    }

    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      return 'OTP must be exactly 6 digits';
    }

    return null;
  }
}

/// Password strength levels
enum PasswordStrength {
  none,
  weak,
  medium,
  strong,
}
