import 'package:flutter/services.dart';

/// Input validation utilities for the Safety App.
/// Critical for ensuring SOS alerts reach valid phone numbers.
class Validators {
  Validators._();

  // ========================================
  // INPUT FORMATTERS
  // ========================================

  /// Phone number input formatter - allows digits, +, spaces, dashes, parentheses
  static final phoneInputFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'[\d\s\-\+\(\)]'),
  );

  /// Name input formatter - allows letters, spaces, hyphens, apostrophes, dots
  static final nameInputFormatter = FilteringTextInputFormatter.allow(
    RegExp(r"[a-zA-Z\s\-'\.]"),
  );

  /// Email input formatter - allows valid email characters
  static final emailInputFormatter = FilteringTextInputFormatter.allow(
    RegExp(r"[a-zA-Z0-9@._\-+]"),
  );

  /// OTP input formatter - digits only
  static final otpInputFormatter = FilteringTextInputFormatter.digitsOnly;

  /// No emoji formatter - removes emojis from input
  /// Uses consolidated character class to prevent ReDoS attacks
  static final noEmojiFormatter = FilteringTextInputFormatter.deny(
    RegExp(
      r'[\u{1F300}-\u{1F9FF}\u{2600}-\u{27BF}\u{1F1E0}-\u{1F1FF}]',
      unicode: true,
    ),
  );

  // ========================================
  // MAX LENGTHS
  // ========================================

  /// Maximum length for name field
  static const int maxNameLength = 50;

  /// Maximum length for email field
  static const int maxEmailLength = 254;

  /// Maximum length for phone field (including formatting)
  static const int maxPhoneLength = 20;

  /// Maximum length for password field
  static const int maxPasswordLength = 128;

  // ========================================
  // SECURITY - SQL INJECTION & XSS PROTECTION
  // ========================================

  /// SQL injection patterns - looks for actual SQL syntax, not just keywords
  /// Requires SQL structure like: keyword + space + something
  static final _sqlInjectionPatterns = [
    // SQL commands with structure (not just keywords)
    RegExp(r"\bSELECT\s+.+\s+FROM\b", caseSensitive: false),
    RegExp(r"\bINSERT\s+INTO\b", caseSensitive: false),
    RegExp(r"\bUPDATE\s+.+\s+SET\b", caseSensitive: false),
    RegExp(r"\bDELETE\s+FROM\b", caseSensitive: false),
    RegExp(r"\bDROP\s+(TABLE|DATABASE)\b", caseSensitive: false),
    RegExp(r"\bUNION\s+(ALL\s+)?SELECT\b", caseSensitive: false),
    RegExp(r"\bALTER\s+TABLE\b", caseSensitive: false),
    RegExp(r"\bCREATE\s+(TABLE|DATABASE)\b", caseSensitive: false),
    RegExp(r"\bTRUNCATE\s+TABLE\b", caseSensitive: false),
    RegExp(r"\bEXEC(UTE)?\s*\(", caseSensitive: false),
    // Comment injection
    RegExp(r";\s*--"),
    RegExp(r"/\*.*\*/"),
    // Stored procedure calls
    RegExp(r"\bxp_\w+", caseSensitive: false),
    RegExp(r"\bsp_\w+", caseSensitive: false),
    // Time-based injection
    RegExp(r"\bSLEEP\s*\(", caseSensitive: false),
    RegExp(r"\bBENCHMARK\s*\(", caseSensitive: false),
    RegExp(r"\bWAITFOR\s+DELAY\b", caseSensitive: false),
    // Hex encoding
    RegExp(r"0x[0-9a-fA-F]+"),
  ];

  /// OR/AND injection pattern (e.g., OR 1=1, AND 1=1)
  static final _sqlLogicInjection = RegExp(
    r'\b(OR|AND)\b\s+\d+\s*=\s*\d+',
    caseSensitive: false,
  );

  /// XSS (Cross-Site Scripting) patterns to detect and block
  static final _xssPatterns = RegExp(
    r'<script|</script|javascript:|onerror\s*=|onload\s*=|onclick\s*=|<iframe|<object|<embed',
    caseSensitive: false,
  );

  /// HTML tag pattern
  static final _htmlTagPattern = RegExp(r'<[a-zA-Z][^>]*>');

  /// Check if input contains SQL injection patterns
  /// Returns true if potentially malicious
  /// Note: This checks for actual SQL syntax, not just keywords
  static bool containsSqlInjection(String? input) {
    if (input == null || input.isEmpty) return false;

    // Check for SQL injection patterns (actual syntax)
    for (final pattern in _sqlInjectionPatterns) {
      if (pattern.hasMatch(input)) {
        return true;
      }
    }

    // Check for logic injection (OR 1=1, AND 1=1)
    if (_sqlLogicInjection.hasMatch(input)) {
      return true;
    }

    // Check for suspicious combination: quote + semicolon
    if (input.contains("'") && input.contains(';')) {
      return true;
    }

    return false;
  }

  /// Check if input contains XSS patterns
  /// Returns true if potentially malicious
  static bool containsXss(String? input) {
    if (input == null || input.isEmpty) return false;
    return _xssPatterns.hasMatch(input);
  }

  /// Check if input contains HTML tags (potential XSS vector)
  static bool containsHtmlTags(String? input) {
    if (input == null || input.isEmpty) return false;
    return _htmlTagPattern.hasMatch(input);
  }

  /// Comprehensive security validation for any text input
  /// Returns error message if malicious content detected, null if safe
  static String? validateSecureInput(String? value, {String fieldName = 'Input'}) {
    if (value == null || value.isEmpty) return null;

    if (containsSqlInjection(value)) {
      return '$fieldName contains invalid characters';
    }

    if (containsXss(value)) {
      return '$fieldName contains invalid characters';
    }

    if (containsHtmlTags(value)) {
      return '$fieldName contains invalid characters';
    }

    return null;
  }

  /// Sanitize input by removing potentially dangerous content
  /// Use this before storing any user input
  static String sanitizeInput(String input) {
    String sanitized = input;

    // Remove null bytes
    sanitized = sanitized.replaceAll('\x00', '');

    // Remove control characters except newline and tab
    sanitized = sanitized.replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // Escape HTML special characters (defense against XSS)
    sanitized = sanitized
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');

    // Trim whitespace
    sanitized = sanitized.trim();

    return sanitized;
  }

  /// Sanitize input for safe database storage (less aggressive)
  /// Removes dangerous patterns but preserves most characters
  static String sanitizeForDatabase(String input) {
    String sanitized = input;

    // Remove null bytes
    sanitized = sanitized.replaceAll('\x00', '');

    // Remove control characters
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // Remove SQL comment patterns
    sanitized = sanitized.replaceAll(RegExp(r'--'), '');
    sanitized = sanitized.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

    // Trim
    sanitized = sanitized.trim();

    return sanitized;
  }

  // E.164 format regex - matches database constraint: ^\+[1-9]\d{1,14}$
  // Must start with +, followed by country code (1-9), then 1-14 more digits
  // Examples: +917418529635, +14155552671, +442071234567
  static final _e164Regex = RegExp(r'^\+[1-9]\d{1,14}$');

  // Phone number regex - supports international format with formatting
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
      // Use [0-9] instead of \d to prevent Unicode digit bypass (security)
      final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
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

  /// Normalize phone number to E.164 format for storage/sending SMS.
  /// E.164 format: +[country code][number] (e.g., +917418529635)
  /// Adds +91 prefix for Indian numbers without country code.
  /// Uses ASCII-only digit matching [0-9] to prevent Unicode digit bypass attacks.
  static String normalizePhone(String phone) {
    // Remove all formatting characters (spaces, dashes, parentheses, dots)
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

    // Validate only ASCII characters are present (security: prevent Unicode digits)
    if (!RegExp(r'^[\+0-9]*$').hasMatch(cleaned)) {
      // Remove any non-ASCII characters
      final asciiOnly = cleaned.replaceAll(RegExp(r'[^\+0-9]'), '');
      if (asciiOnly.isEmpty) return '+0'; // Invalid, will fail E.164 validation
      return normalizePhone(asciiOnly);
    }

    // If already has country code, ensure it's clean
    if (cleaned.startsWith('+')) {
      // Remove any remaining non-digit characters except the leading +
      // Use [0-9] instead of \d to only match ASCII digits (security)
      return '+${cleaned.substring(1).replaceAll(RegExp(r'[^0-9]'), '')}';
    }

    // Extract ASCII digits only (use [0-9] not \d for security)
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');

    // Add Indian country code for 10-digit numbers
    if (digitsOnly.length == 10) {
      return '+91$digitsOnly';
    }

    // If number starts with country code without +, add +
    if (digitsOnly.length > 10 && digitsOnly.length <= 15) {
      return '+$digitsOnly';
    }

    // Return with + prefix as fallback
    return '+$digitsOnly';
  }

  /// Validate phone number is in E.164 format (for database storage).
  /// This matches the database constraint: ^\+[1-9]\d{1,14}$
  /// Returns error message or null if valid.
  static String? validateE164Phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    if (!_e164Regex.hasMatch(value)) {
      return 'Phone must be in E.164 format (e.g., +917418529635)';
    }

    return null;
  }

  /// Check if a phone number is valid E.164 format.
  /// Use this before saving to database.
  static bool isValidE164(String phone) {
    return _e164Regex.hasMatch(phone);
  }

  /// Validate email address format.
  /// Returns error message or null if valid.
  /// Includes SQL injection and XSS protection.
  static String? validateEmail(String? value, {bool allowEmpty = false}) {
    if (value == null || value.trim().isEmpty) {
      return allowEmpty ? null : 'Please enter your email';
    }

    final email = value.trim().toLowerCase();

    // Security check - SQL injection and XSS
    if (containsSqlInjection(email) || containsXss(email)) {
      return 'Email contains invalid characters';
    }

    // Check length
    if (email.length > maxEmailLength) {
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

    // Check against common weak passwords (expanded list)
    const commonPasswords = [
      'password', 'password1', 'password123', 'passw0rd', 'p@ssword',
      '12345678', '123456789', '1234567890',
      'qwerty123', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm',
      'admin123', 'admin1234',
      'letmein', 'letmein1',
      'welcome1', 'welcome123',
      'monkey123', 'dragon123', 'master123', 'sunshine1', 'princess1',
      'football1', 'baseball1', 'iloveyou1',
      'trustno1', 'shadow123', 'superman1', 'michael1',
      'abc12345', '1q2w3e4r', 'qazwsx123',
    ];
    final lowerValue = value.toLowerCase();
    if (commonPasswords.any((p) => lowerValue.contains(p))) {
      return 'Password is too common, please choose a stronger one';
    }

    // Check for sequential characters (e.g., abc, 123, xyz)
    if (RegExp(r'(012|123|234|345|456|567|678|789|890)').hasMatch(value)) {
      return 'Password contains sequential numbers';
    }

    // Check for repeated characters (e.g., aaa, 111)
    if (RegExp(r'(.)\1{2,}').hasMatch(value)) {
      return 'Password contains too many repeated characters';
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
  /// Includes SQL injection and XSS protection.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }

    final trimmed = value.trim();

    // Security check - SQL injection and XSS
    final securityError = validateSecureInput(trimmed, fieldName: 'Name');
    if (securityError != null) {
      return securityError;
    }

    if (trimmed.length < 2) {
      return 'Name must be at least 2 characters';
    }

    if (trimmed.length > 50) {
      return 'Name is too long';
    }

    // Allow letters, spaces, hyphens, apostrophes, and dots (whitelist approach)
    // This is secure by design - only allows safe characters
    if (!RegExp(r"^[a-zA-Z\s\-'\.]+$").hasMatch(trimmed)) {
      return 'Name contains invalid characters';
    }

    return null;
  }

  /// Sanitize name input by removing invalid characters.
  /// Includes security sanitization for defense-in-depth.
  static String sanitizeName(String name) {
    // First apply security sanitization
    String cleaned = sanitizeForDatabase(name);

    // Remove leading/trailing whitespace
    cleaned = cleaned.trim();

    // Remove any characters not in whitelist
    cleaned = cleaned.replaceAll(RegExp(r"[^a-zA-Z\s\-'\.]"), '');

    // Collapse multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Limit length
    if (cleaned.length > maxNameLength) {
      cleaned = cleaned.substring(0, maxNameLength);
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
