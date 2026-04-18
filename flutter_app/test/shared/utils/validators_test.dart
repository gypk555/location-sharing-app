import 'package:flutter_test/flutter_test.dart';
import 'package:safety_app/shared/utils/validators.dart';

/// Seed unit tests for the Validators layer. This is the first step of the
/// test pyramid recommended in code-review finding §3.1 — Validators is the
/// highest-value target because every input path (phone, email, password,
/// emergency-contact name) flows through it.
void main() {
  group('Validators.normalizePhone', () {
    test('prefixes 10-digit Indian number with +91', () {
      expect(Validators.normalizePhone('9876543210'), '+919876543210');
    });

    test('strips spaces, dashes and parens', () {
      expect(
        Validators.normalizePhone('+91 98765-43210'),
        '+919876543210',
      );
      expect(
        Validators.normalizePhone('(987) 654-3210'),
        '+919876543210',
      );
    });

    test('keeps existing country code untouched', () {
      expect(Validators.normalizePhone('+14155552671'), '+14155552671');
    });

    test('strips Unicode digits to prevent bypass', () {
      // Devanagari digits — must not leak through validation.
      const devanagari = '\u0967\u0968\u0969\u096A\u096B\u096C\u096D\u096E\u096F\u0966';
      final normalized = Validators.normalizePhone(devanagari);
      expect(normalized, '+0'); // Sentinel "invalid" value from implementation
      expect(Validators.isValidE164(normalized), isFalse);
    });

    test('round-trips through isValidE164 for real numbers', () {
      final cases = [
        '9876543210',
        '+91 98765 43210',
        '+1 415 555 2671',
      ];
      for (final input in cases) {
        final e164 = Validators.normalizePhone(input);
        expect(
          Validators.isValidE164(e164),
          isTrue,
          reason: 'Expected $input -> $e164 to be valid E.164',
        );
      }
    });
  });

  group('Validators.isValidE164', () {
    test('accepts standard Indian and US numbers', () {
      expect(Validators.isValidE164('+919876543210'), isTrue);
      expect(Validators.isValidE164('+14155552671'), isTrue);
    });

    test('rejects numbers starting with 0 after +', () {
      expect(Validators.isValidE164('+0123456789'), isFalse);
    });

    test('rejects numbers without +', () {
      expect(Validators.isValidE164('919876543210'), isFalse);
    });

    test('rejects non-digit characters', () {
      expect(Validators.isValidE164('+91 98765'), isFalse);
      expect(Validators.isValidE164('+91abc123'), isFalse);
    });
  });

  group('Validators.validatePassword', () {
    test('rejects passwords shorter than 8 characters', () {
      expect(Validators.validatePassword('Ab1!xy'), isNotNull);
    });

    test('rejects passwords missing uppercase', () {
      expect(Validators.validatePassword('abcdef1!'), isNotNull);
    });

    test('rejects passwords missing lowercase', () {
      expect(Validators.validatePassword('ABCDEF1!'), isNotNull);
    });

    test('rejects passwords missing a digit', () {
      expect(Validators.validatePassword('Abcdefgh!'), isNotNull);
    });

    test('rejects passwords missing a special character', () {
      expect(Validators.validatePassword('Abcdefg1'), isNotNull);
    });

    test('rejects common passwords even if they match the regex rules', () {
      // "Password123!" fits all char-class rules but is on the common list.
      expect(
        Validators.validatePassword('Password123!'),
        contains('common'),
      );
    });

    test('rejects sequential-digit passwords', () {
      expect(
        Validators.validatePassword('Str0ng123!'),
        contains('sequential'),
      );
    });

    test('accepts a genuinely strong password', () {
      expect(Validators.validatePassword('Zmq\$Lr9vN@k'), isNull);
    });
  });

  group('Validators.containsSqlInjection', () {
    test('flags UNION SELECT payloads', () {
      expect(
        Validators.containsSqlInjection("a' UNION SELECT password FROM users--"),
        isTrue,
      );
    });

    test('flags DROP TABLE payloads', () {
      expect(
        Validators.containsSqlInjection('1; DROP TABLE contacts;--'),
        isTrue,
      );
    });

    test('does not flag benign names that contain SQL keywords', () {
      expect(Validators.containsSqlInjection('Selena'), isFalse);
      expect(Validators.containsSqlInjection('update my contact'), isFalse);
    });

    test('handles null and empty safely', () {
      expect(Validators.containsSqlInjection(null), isFalse);
      expect(Validators.containsSqlInjection(''), isFalse);
    });
  });

  group('Validators.isValidE164 on known bad inputs', () {
    test('empty string is not E.164', () {
      expect(Validators.isValidE164(''), isFalse);
    });

    test('whitespace-only is not E.164', () {
      expect(Validators.isValidE164('   '), isFalse);
    });
  });
}
