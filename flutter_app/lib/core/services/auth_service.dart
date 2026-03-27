import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _uuid = const Uuid();
  UserModel? _currentUser;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;

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
      final box = await Hive.openBox<UserModel>(AppConstants.userBoxName);
      if (box.isNotEmpty) {
        _currentUser = box.getAt(0);
      }
    } catch (e) {
      AppLogger.error('Error loading stored user', e);
    }
  }

  Future<void> _saveUser(UserModel user) async {
    try {
      final box = await Hive.openBox<UserModel>(AppConstants.userBoxName);
      await box.clear();
      await box.add(user);
      _currentUser = user;
    } catch (e) {
      AppLogger.error('Error saving user', e);
    }
  }

  // Phone OTP Authentication
  Future<void> sendPhoneOtp(String phone) async {
    if (_supabase != null) {
      await _supabase!.auth.signInWithOtp(phone: phone);
    }
    // In demo mode, we skip actual OTP
  }

  Future<UserModel> verifyPhoneOtp(String phone, String otp) async {
    UserModel user;

    if (_supabase != null) {
      final response = await _supabase!.auth.verifyOTP(
        phone: phone,
        token: otp,
        type: OtpType.sms,
      );

      user = UserModel(
        id: response.user?.id ?? _uuid.v4(),
        phone: phone,
        authProvider: 'phone',
        createdAt: DateTime.now(),
      );
    } else {
      // Demo mode
      if (otp.length != 6) {
        throw Exception('Invalid OTP');
      }
      user = UserModel(
        id: 'demo-phone-${_uuid.v4()}',
        phone: phone,
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
    UserModel user;

    if (_supabase != null) {
      final response = await _supabase!.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

      user = UserModel(
        id: response.user?.id ?? _uuid.v4(),
        email: email,
        name: name,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    } else {
      // Demo mode
      user = UserModel(
        id: 'demo-email-${_uuid.v4()}',
        email: email,
        name: name,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    }

    await _saveUser(user);
    return user;
  }

  Future<UserModel> loginWithEmail(String email, String password) async {
    UserModel user;

    if (_supabase != null) {
      final response = await _supabase!.auth.signInWithPassword(
        email: email,
        password: password,
      );

      user = UserModel(
        id: response.user?.id ?? _uuid.v4(),
        email: email,
        name: response.user?.userMetadata?['name'] as String?,
        authProvider: 'email',
        createdAt: DateTime.now(),
      );
    } else {
      // Demo mode
      user = UserModel(
        id: 'demo-email-${_uuid.v4()}',
        email: email,
        name: email.split('@').first,
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
      if (_supabase != null) {
        await _supabase!.auth.signOut();
      }

      final box = await Hive.openBox<UserModel>(AppConstants.userBoxName);
      await box.clear();
      _currentUser = null;
    } catch (e) {
      AppLogger.error('Error signing out', e);
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
}
