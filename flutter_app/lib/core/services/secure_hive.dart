import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/logger.dart';

/// Centralizes Hive encryption so every box in the app is opened with the
/// same AES cipher. The key material lives in the OS keystore (iOS Keychain /
/// Android Keystore) via [FlutterSecureStorage]; it never touches SharedPreferences
/// and is never logged (security fix H-2).
///
/// Use [SecureHive.init] once from `main()` after [Hive.initFlutter] and
/// before any boxes are opened. After that, call [SecureHive.openBox] instead
/// of [Hive.openBox] at every callsite.
class SecureHive {
  SecureHive._();

  static const _keyStorageKey = 'hive_aes_key_v1';
  static const _migrationFlagPrefix = 'hive_enc_migrated_v1:';

  /// AndroidOptions: force EncryptedSharedPreferences so the key blob is
  /// encrypted at rest even on devices that don't expose the hardware-backed
  /// Keystore path. iOS defaults are already first-partition keychain.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static HiveAesCipher? _cipher;

  /// Initialize the cipher. Must be called before any [openBox].
  /// Idempotent — repeated calls are no-ops.
  static Future<void> init() async {
    if (_cipher != null) return;

    String? encodedKey = await _secureStorage.read(key: _keyStorageKey);
    if (encodedKey == null || encodedKey.isEmpty) {
      final keyBytes = Hive.generateSecureKey();
      encodedKey = base64UrlEncode(keyBytes);
      await _secureStorage.write(key: _keyStorageKey, value: encodedKey);
      AppLogger.info('Generated new Hive encryption key');
    }

    _cipher = HiveAesCipher(base64Url.decode(encodedKey));
  }

  /// Open an encrypted box. Transparently migrates any legacy unencrypted
  /// box found on disk by copying rows into a fresh encrypted box and then
  /// deleting the legacy one (security fix H-2 migration path).
  static Future<Box<T>> openBox<T>(String name) async {
    if (_cipher == null) {
      throw StateError(
        'SecureHive.init() must be called before SecureHive.openBox()',
      );
    }

    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }

    await _migrateLegacyBoxIfNeeded<T>(name);

    return Hive.openBox<T>(name, encryptionCipher: _cipher);
  }

  /// One-shot migration: if a pre-encryption box still exists on disk, copy
  /// its rows into a new encrypted box. Attempting to open an unencrypted box
  /// with a cipher would throw `HiveError: wrong key`, so this must run first.
  static Future<void> _migrateLegacyBoxIfNeeded<T>(String name) async {
    final migrationKey = '$_migrationFlagPrefix$name';
    final alreadyMigrated = await _secureStorage.read(key: migrationKey);
    if (alreadyMigrated == 'true') return;

    if (!await Hive.boxExists(name)) {
      await _secureStorage.write(key: migrationKey, value: 'true');
      return;
    }

    try {
      final legacy = await Hive.openBox<T>(name);
      final legacyEntries = <dynamic, T>{};
      for (final k in legacy.keys) {
        final v = legacy.get(k);
        if (v != null) legacyEntries[k] = v;
      }
      await legacy.close();
      await Hive.deleteBoxFromDisk(name);

      if (legacyEntries.isNotEmpty) {
        final fresh =
            await Hive.openBox<T>(name, encryptionCipher: _cipher);
        await fresh.putAll(legacyEntries);
        await fresh.close();
        AppLogger.info(
          'Migrated ${legacyEntries.length} entries from legacy '
          'unencrypted box "$name" to encrypted box',
        );
      }
    } catch (e) {
      // Box was likely already encrypted (user upgraded, reinstalled with
      // same key, etc.). Nothing to migrate — mark as done and move on.
      AppLogger.info('Legacy migration skipped for "$name" ($e)');
    } finally {
      await _secureStorage.write(key: migrationKey, value: 'true');
    }
  }

  /// Drop the encryption key and every migration flag. Used by sign-out so
  /// the next user starts with a fresh key and no cached secrets (defense in
  /// depth — the boxes themselves are cleared separately).
  static Future<void> resetForSignOut() async {
    await _secureStorage.delete(key: _keyStorageKey);
    for (final name in const [
      AppConstants.userBoxName,
      AppConstants.contactsBoxName,
      AppConstants.locationBoxName,
      AppConstants.settingsBoxName,
    ]) {
      await _secureStorage.delete(key: '$_migrationFlagPrefix$name');
    }
    _cipher = null;
  }
}
