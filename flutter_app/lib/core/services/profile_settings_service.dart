import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_settings_models.dart';
import '../../shared/utils/logger.dart';

class ProfileSettingsService {
  final SupabaseClient _supabase;

  ProfileSettingsService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  Future<Map<String, dynamic>> fetchProfileSettings(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('name, phone, sos_settings, fake_call_settings')
          .eq('id', userId)
          .single();

      return response;
    } catch (e) {
      throw Exception('Failed to fetch profile settings: $e');
    }
  }

  /// Updates SOS settings and returns the updated row from DB.
  Future<Map<String, dynamic>> updateSosSettings(String userId, SosSettings settings) async {
    final validationError = settings.validate();
    if (validationError != null) {
      throw Exception(validationError);
    }

    try {
      final response = await _supabase
          .from('profiles')
          .update({'sos_settings': settings.toJson()})
          .eq('id', userId)
          .select('sos_settings')
          .single();
      AppLogger.info('ProfileSettingsService: Updated SOS settings successfully');
      return response;
    } catch (e) {
      AppLogger.error('ProfileSettingsService: Failed to update SOS settings', e);
      throw Exception('Failed to update SOS settings: $e');
    }
  }

  /// Updates fake call settings and returns the updated row from DB.
  Future<Map<String, dynamic>> updateFakeCallSettings(
      String userId, FakeCallSettings settings) async {
    final validationError = settings.validate();
    if (validationError != null) {
      throw Exception(validationError);
    }

    try {
      final response = await _supabase
          .from('profiles')
          .update({'fake_call_settings': settings.toJson()})
          .eq('id', userId)
          .select('fake_call_settings')
          .single();
      return response;
    } catch (e) {
      throw Exception('Failed to update fake call settings: $e');
    }
  }

  /// Updates profile fields and returns the updated row from DB.
  Future<Map<String, dynamic>> updateProfile(
      String userId, {String? name, String? phone}) async {
    try {
      final Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;

      if (updates.isEmpty) return {};

      AppLogger.info('ProfileSettingsService: Updating profile for user (fields: ${updates.keys.toList()})');
      final response = await _supabase
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select('name, phone')
          .single();
      return response;
    } catch (e) {
      AppLogger.error('ProfileSettingsService: Failed to update profile', e);
      throw Exception('Failed to update profile: $e');
    }
  }
}
