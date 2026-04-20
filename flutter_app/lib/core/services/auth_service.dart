import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../models/contact_model.dart';
import '../models/location_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/errors/app_errors.dart';
import '../../shared/utils/logger.dart';
import '../../shared/utils/validators.dart';
import 'secure_hive.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _uuid = const Uuid();
  UserModel? _currentUser;

  /// OS-backed storage for the cached-user JSON blob used on the splash
  /// fast-path. Replaces the previous SharedPreferences-backed cache which
  /// stored identity in plaintext on disk (security fix H-2).
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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
      _userBox = await SecureHive.openBox<UserModel>(AppConstants.userBoxName);
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
    final sw = Stopwatch()..start();
    AppLogger.info('AuthService.initialize start');
    await loadCachedUserFast();
    await loadStoredUserFromHive();
    sw.stop();
    AppLogger.info('AuthService.initialize done in ${sw.elapsedMilliseconds}ms');
  }

  Future<UserModel?> loadCachedUserFast() async {
    try {
      // Migrate the legacy plaintext blob from SharedPreferences to secure
      // storage on first launch after the H-2 upgrade, then remove it.
      await _migrateLegacyCachedUser();

      final raw = await _secureStorage.read(key: AppConstants.cachedUserKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _currentUser = UserModel(
        id: json['id'] as String,
        authProvider: json['authProvider'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        name: json['name'] as String?,
        photoUrl: json['photoUrl'] as String?,
      );
      return _currentUser;
    } catch (e) {
      AppLogger.error('Error loading cached user', e);
      return null;
    }
  }

  /// One-shot migration: old builds stored the cached user JSON in plaintext
  /// SharedPreferences. Copy any legacy blob into secure storage, then delete
  /// it. Idempotent — safe to call repeatedly.
  Future<void> _migrateLegacyCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(AppConstants.cachedUserKey);
      if (legacy == null || legacy.isEmpty) return;

      final alreadyInSecure =
          await _secureStorage.read(key: AppConstants.cachedUserKey);
      if (alreadyInSecure == null || alreadyInSecure.isEmpty) {
        await _secureStorage.write(
          key: AppConstants.cachedUserKey,
          value: legacy,
        );
      }
      await prefs.remove(AppConstants.cachedUserKey);
    } catch (e) {
      AppLogger.error('Error migrating legacy cached user', e);
    }
  }

  Future<UserModel?> loadStoredUserFromHive() async {
    try {
      AppLogger.info('AuthService._loadStoredUser start');
      final box = await _box;
      if (box.isNotEmpty) {
        final dynamic data = box.getAt(0);
        if (data is UserModel) {
          _currentUser = data;
        } else if (data is Map) {
          // Robustness: handle Map data from previous app versions or corrupted storage
          try {
            _currentUser = UserModel.fromJson(Map<String, dynamic>.from(data));
            AppLogger.warning('AuthService: Migrated Map user from Hive to UserModel');
          } catch (e) {
            AppLogger.error('AuthService: Failed to parse user Map from Hive', e);
            _currentUser = null;
          }
        } else {
          _currentUser = null;
        }
        
        if (_currentUser != null) {
          AppLogger.info('AuthService._loadStoredUser loaded user from Hive');
          await _saveUserToPrefs(_currentUser!);
        }
      } else {
        AppLogger.info('AuthService._loadStoredUser no user in Hive');
      }
      return _currentUser;
    } catch (e) {
      AppLogger.error('Error loading stored user', e);
      return null;
    }
  }

  Future<void> _saveUserToPrefs(UserModel user) async {
    try {
      await _secureStorage.write(
        key: AppConstants.cachedUserKey,
        value: jsonEncode(_minimalUserJson(user)),
      );
    } catch (e) {
      AppLogger.error('Error saving cached user', e);
    }
  }

  Future<void> _clearCachedUser() async {
    try {
      await _secureStorage.delete(key: AppConstants.cachedUserKey);
      // Also wipe any lingering plaintext blob from pre-H-2 installs.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.cachedUserKey);
    } catch (e) {
      AppLogger.error('Error clearing cached user', e);
    }
  }

  Map<String, dynamic> _minimalUserJson(UserModel user) {
    return {
      'id': user.id,
      'authProvider': user.authProvider,
      'createdAt': user.createdAt.toIso8601String(),
      'email': user.email,
      'phone': user.phone,
      'name': user.name,
      'photoUrl': user.photoUrl,
    };
  }

  Future<void> _saveUser(UserModel user) async {
    try {
      final box = await _box;
      await box.clear();
      await box.add(user);
      _currentUser = user;
      await _saveUserToPrefs(user);
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

  /// Check if email is already registered in Supabase.
  /// Uses RPC function for efficient lookup.
  /// Returns true if email exists, false otherwise.
  /// Fails open (returns false on errors) to avoid blocking legitimate registrations.
  Future<bool> checkEmailExists(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    // Validate email format first
    if (Validators.validateEmail(normalizedEmail) != null) {
      return false; // Invalid email can't exist
    }

    if (_supabase == null) {
      return false; // Demo mode - allow all
    }

    try {
      final response = await _supabase!.rpc(
        'check_email_exists',
        params: {'email_input': normalizedEmail},
      );
      return response as bool? ?? false;
    } catch (e) {
      AppLogger.error('Email existence check failed', e);
      // Fail open - don't block registration on error
      return false;
    }
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

  // Google / Apple Sign In are not yet wired to real OAuth.
  // The previous placeholder implementations silently minted fake "demo" users
  // that never reached Supabase, so every authenticated write failed RLS. They
  // now throw so any stray caller produces a loud, debuggable failure instead
  // of a broken session (security fix H-1). The UI gates the buttons behind a
  // "Coming soon" message — wire real OAuth here before re-enabling them.
  Future<UserModel> signInWithGoogle() async {
    throw UnimplementedError(
      'Google sign-in is not yet available. Please sign in with email or phone.',
    );
  }

  Future<UserModel> signInWithApple() async {
    throw UnimplementedError(
      'Apple sign-in is not yet available. Please sign in with email or phone.',
    );
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
      await _clearCachedUser();

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
        SecureHive.openBox<UserModel>(AppConstants.userBoxName),
        SecureHive.openBox<ContactModel>(AppConstants.contactsBoxName),
        SecureHive.openBox<LocationModel>(AppConstants.locationBoxName),
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
      await _clearCachedUser();

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

    // Update in Supabase Auth metadata if available
    if (_supabase != null && name != null) {
      try {
        await _supabase!.auth.updateUser(
          UserAttributes(data: {'name': name}),
        );
      } catch (e) {
        AppLogger.warning('AuthService: Failed to update Auth metadata, proceeding with local update: $e');
      }
    }

    await _saveUser(updatedUser);
  }

  /// Update user's phone number with E.164 validation.
  /// Phone must be in E.164 format (e.g., +917418529635).
  Future<void> updatePhone(String phone) async {
    if (_currentUser == null) return;

    // Normalize and validate phone
    AppLogger.debug('AuthService.updatePhone: Normalizing phone ***${phone.length > 2 ? phone.substring(phone.length - 2) : ''}');
    final normalizedPhone = Validators.normalizePhone(phone);
    AppLogger.debug('AuthService.updatePhone: Normalized OK');

    if (!Validators.isValidE164(normalizedPhone)) {
      throw ValidationError.invalidFormat(
        fieldName: 'phone number',
        expected: '+91XXXXXXXXXX',
      );
    }

    // Update in Supabase if available
    if (_supabase != null) {
      try {
        await _supabase!.auth.updateUser(
          UserAttributes(phone: normalizedPhone),
        );
      } catch (e) {
        AppLogger.warning('AuthService: Failed to update Auth phone, proceeding with local update: $e');
      }
    }

    // Update local user
    AppLogger.debug('AuthService.updatePhone: Updating local user');
    final updatedUser = _currentUser!.copyWith(phone: normalizedPhone);
    await _saveUser(updatedUser);
    AppLogger.debug('AuthService.updatePhone: Local user updated successfully');
  }
}
