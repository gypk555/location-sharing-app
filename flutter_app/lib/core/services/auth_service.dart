import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../models/contact_model.dart';
import '../models/location_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/errors/app_errors.dart';
import '../../shared/utils/logger.dart';
import '../../shared/utils/validators.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _uuid = const Uuid();
  UserModel? _currentUser;

  /// Demo mode OTP attempt tracking (security: prevent brute force)
  final Map<String, int> _demoOtpAttempts = {};
  final Map<String, DateTime> _demoOtpLockouts = {};
  static const _maxDemoOtpAttempts = 5;
  static const _demoLockoutDuration = Duration(minutes: 5);

  /// Cached Hive box for performance
  Box<UserModel>? _userBox;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

  /// Get cached user box (performance: avoid reopening on every operation)
  Future<Box<UserModel>> get _box async {
    if (_userBox == null || !_userBox!.isOpen) {
      _userBox = await Hive.openBox<UserModel>(AppConstants.userBoxName);
    }
    return _userBox!;
  }

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      return null;
    }
  }

  Future<void> initialize() async {
    await _loadStoredUser();
  }

  Future<void> _loadStoredUser() async {
    try {
      final box = await _box;
      if (box.isNotEmpty) {
        _currentUser = box.getAt(0);
      }
    } catch (e) {
      AppLogger.error('Error loading stored user', e);
    }
  }

  Future<void> _saveUser(UserModel user) async {
    try {
      final box = await _box;
      await box.clear();
      await box.add(user);
      _currentUser = user;
    } catch (e) {
      AppLogger.error('Error saving user', e);
    }
  }

  // Phone OTP Authentication
  Future<void> sendPhoneOtp(String phone) async {
    // Normalize phone to E.164 format before sending to Supabase
    final normalizedPhone = Validators.normalizePhone(phone);

    // Validate E.164 format
    if (!Validators.isValidE164(normalizedPhone)) {
      throw ValidationError.invalidFormat(
        fieldName: 'phone number',
        expected: '+91XXXXXXXXXX',
      );
    }

    if (_supabase != null) {
      await _supabase!.auth.signInWithOtp(phone: normalizedPhone);
    }
    // In demo mode, we skip actual OTP
  }

  Future<UserModel> verifyPhoneOtp(String phone, String otp) async {
    // Normalize phone to E.164 format
    final normalizedPhone = Validators.normalizePhone(phone);

    // Validate E.164 format
    if (!Validators.isValidE164(normalizedPhone)) {
      throw ValidationError.invalidFormat(
        fieldName: 'phone number',
        expected: '+91XXXXXXXXXX',
      );
    }

    UserModel user;

    if (_supabase != null) {
      final response = await _supabase!.auth.verifyOTP(
        phone: normalizedPhone,
        token: otp,
        type: OtpType.sms,
      );

      user = UserModel(
        id: response.user?.id ?? _uuid.v4(),
        phone: normalizedPhone,
        authProvider: 'phone',
        createdAt: DateTime.now(),
      );
    } else {
      // Demo mode with attempt limiting (security: prevent brute force)

      // Check if locked out (use generic message to prevent user enumeration)
      final lockoutTime = _demoOtpLockouts[normalizedPhone];
      if (lockoutTime != null) {
        if (DateTime.now().isBefore(lockoutTime)) {
          // Generic message prevents attackers from knowing if phone was used
          throw ValidationError.invalidFormat(
            fieldName: 'OTP',
            expected: 'Invalid OTP. Please try again later.',
          );
        } else {
          // Lockout expired, clear it
          _demoOtpLockouts.remove(normalizedPhone);
          _demoOtpAttempts.remove(normalizedPhone);
        }
      }

      // Validate OTP format (must be exactly 6 digits)
      if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
        // Track failed attempt
        _demoOtpAttempts[normalizedPhone] =
            (_demoOtpAttempts[normalizedPhone] ?? 0) + 1;

        if (_demoOtpAttempts[normalizedPhone]! >= _maxDemoOtpAttempts) {
          _demoOtpLockouts[normalizedPhone] =
              DateTime.now().add(_demoLockoutDuration);
          _demoOtpAttempts.remove(normalizedPhone);

          throw ValidationError.invalidFormat(
            fieldName: 'OTP',
            expected: 'Too many failed attempts. Locked for 5 minutes.',
          );
        }

        throw ValidationError.invalidFormat(
          fieldName: 'OTP',
          expected: '6 digits',
        );
      }

      // Success - clear attempts
      _demoOtpAttempts.remove(normalizedPhone);

      user = UserModel(
        id: 'demo-phone-${_uuid.v4()}',
        phone: normalizedPhone,
        authProvider: 'phone',
        createdAt: DateTime.now(),
      );
    }

    await _saveUser(user);
    return user;
  }

  // Email Authentication
  Future<UserModel> registerWithEmail(
    String email,
    String password,
    String name,
  ) async {
    // Normalize email to lowercase for consistency
    final normalizedEmail = email.trim().toLowerCase();
    UserModel user;

    if (_supabase != null) {
      final response = await _supabase!.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {'name': name},
      );

      user = UserModel(
        id: response.user?.id ?? _uuid.v4(),
        email: normalizedEmail,
        name: name,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    } else {
      // Demo mode
      user = UserModel(
        id: 'demo-email-${_uuid.v4()}',
        email: normalizedEmail,
        name: name,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    }

    await _saveUser(user);
    return user;
  }

  Future<UserModel> loginWithEmail(String email, String password) async {
    // Normalize email to lowercase for consistency
    final normalizedEmail = email.trim().toLowerCase();
    UserModel user;

    if (_supabase != null) {
      final response = await _supabase!.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );

      user = UserModel(
        id: response.user?.id ?? _uuid.v4(),
        email: normalizedEmail,
        name: response.user?.userMetadata?['name'] as String?,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    } else {
      // Demo mode
      user = UserModel(
        id: 'demo-email-${_uuid.v4()}',
        email: normalizedEmail,
        name: normalizedEmail.split('@').first,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    }

    await _saveUser(user);
    return user;
  }

  // Google Sign In (placeholder - requires google_sign_in setup)
  Future<UserModel> signInWithGoogle() async {
    // Demo mode for now
    final user = UserModel(
      id: 'demo-google-${_uuid.v4()}',
      email: 'demo@gmail.com',
      name: 'Demo User',
      authProvider: 'google',
      createdAt: DateTime.now(),
    );

    await _saveUser(user);
    return user;
  }

  // Apple Sign In (placeholder - requires sign_in_with_apple setup)
  Future<UserModel> signInWithApple() async {
    // Demo mode for now
    final user = UserModel(
      id: 'demo-apple-${_uuid.v4()}',
      email: 'demo@icloud.com',
      name: 'Demo User',
      authProvider: 'apple',
      createdAt: DateTime.now(),
    );

    await _saveUser(user);
    return user;
  }

  Future<void> signOut() async {
    try {
      // Clear in-memory user immediately for security
      _currentUser = null;

      if (_supabase != null) {
        await _supabase!.auth.signOut();
      }

      // Clear all user-specific data from local storage
      await _clearAllUserData();

      AppLogger.info('User signed out and all data cleared');
    } catch (e) {
      AppLogger.error('Error signing out', e);
      // Ensure user is still cleared even on error
      _currentUser = null;
    }
  }

  /// Clear all user-specific data from Hive boxes
  /// Uses parallel clearing for better performance
  Future<void> _clearAllUserData() async {
    try {
      // Open all boxes in parallel for performance
      final futures = await Future.wait([
        Hive.openBox<UserModel>(AppConstants.userBoxName),
        Hive.openBox<ContactModel>(AppConstants.contactsBoxName),
        Hive.openBox<LocationModel>(AppConstants.locationBoxName),
      ]);

      final userBox = futures[0] as Box<UserModel>;
      final contactsBox = futures[1] as Box<ContactModel>;
      final locationBox = futures[2] as Box<LocationModel>;

      // Clear all boxes in parallel for performance
      await Future.wait([
        userBox.clear(),
        contactsBox.clear(),
        locationBox.clear(),
      ]);

      // Clear cached box reference
      _userBox = null;

      AppLogger.info('All user data cleared from local storage');
    } catch (e) {
      AppLogger.error('Error clearing user data', e);
    }
  }

  Future<void> updateProfile({
    String? name,
    String? photoUrl,
  }) async {
    if (_currentUser == null) return;

    final updatedUser = _currentUser!.copyWith(
      name: name ?? _currentUser!.name,
      photoUrl: photoUrl ?? _currentUser!.photoUrl,
    );

    await _saveUser(updatedUser);
  }

  /// Update user's phone number with E.164 validation.
  /// Phone must be in E.164 format (e.g., +917418529635).
  Future<void> updatePhone(String phone) async {
    if (_currentUser == null) return;

    // Normalize and validate phone
    final normalizedPhone = Validators.normalizePhone(phone);

    if (!Validators.isValidE164(normalizedPhone)) {
      throw ValidationError.invalidFormat(
        fieldName: 'phone number',
        expected: '+91XXXXXXXXXX',
      );
    }

    // Update in Supabase if available
    if (_supabase != null) {
      await _supabase!.auth.updateUser(
        UserAttributes(phone: normalizedPhone),
      );
    }

    // Update local user
    final updatedUser = _currentUser!.copyWith(phone: normalizedPhone);
    await _saveUser(updatedUser);
  }
}
