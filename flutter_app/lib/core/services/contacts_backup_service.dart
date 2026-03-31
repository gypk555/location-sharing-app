import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/contact_model.dart';
import '../../shared/errors/app_errors.dart';
import '../../shared/utils/logger.dart';
import '../../shared/utils/validators.dart';

/// Result of a backup operation
class BackupResult {
  final bool success;
  final String? filePath;
  final String? error;
  final String? recoverySuggestion;
  final String? errorCode;
  final int contactCount;

  const BackupResult({
    required this.success,
    this.filePath,
    this.error,
    this.recoverySuggestion,
    this.errorCode,
    this.contactCount = 0,
  });

  /// Create a successful result
  factory BackupResult.ok({
    String? filePath,
    required int contactCount,
  }) {
    return BackupResult(
      success: true,
      filePath: filePath,
      contactCount: contactCount,
    );
  }

  /// Create a failed result from an AppError
  factory BackupResult.fromError(AppError error) {
    return BackupResult(
      success: false,
      error: error.userMessage,
      recoverySuggestion: error.recoverySuggestion,
      errorCode: error.code.code,
    );
  }
}

/// Result of an import operation
class ImportResult {
  final bool success;
  final List<ContactModel> contacts;
  final String? error;
  final String? recoverySuggestion;
  final String? errorCode;

  const ImportResult({
    required this.success,
    this.contacts = const [],
    this.error,
    this.recoverySuggestion,
    this.errorCode,
  });

  /// Create a successful result
  factory ImportResult.ok({required List<ContactModel> contacts}) {
    return ImportResult(
      success: true,
      contacts: contacts,
    );
  }

  /// Create a failed result from an AppError
  factory ImportResult.fromError(AppError error) {
    return ImportResult(
      success: false,
      error: error.userMessage,
      recoverySuggestion: error.recoverySuggestion,
      errorCode: error.code.code,
    );
  }
}

/// Service for exporting and importing contacts
class ContactsBackupService {
  ContactsBackupService._();
  static final instance = ContactsBackupService._();

  /// Export contacts to a JSON file and share it
  Future<BackupResult> exportAndShare(List<ContactModel> contacts) async {
    if (contacts.isEmpty) {
      return BackupResult.fromError(BackupError.noContactsToExport());
    }

    try {
      // Convert contacts to JSON
      final contactsJson = contacts
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'phone': c.phone,
                'email': c.email,
                'relationship': c.relationship,
                'isSosContact': c.isSosContact,
                'isLocationSharing': c.isLocationSharing,
                'isPrimary': c.isPrimary,
                'addedAt': c.addedAt.toIso8601String(),
              })
          .toList();

      final exportData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'contactCount': contacts.length,
        'contacts': contactsJson,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      // Handle web platform differently
      if (kIsWeb) {
        return _exportForWeb(jsonString, contacts.length);
      }

      // Create temp file for sharing
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'safety_app_contacts_$timestamp.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonString);

      // Share the file with guaranteed cleanup via finally block
      late ShareResult shareResult;
      try {
        shareResult = await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Safety App Contacts Backup',
          text: 'My emergency contacts backup from Safety App',
        );
      } finally {
        // CRITICAL: Clean up temp file in finally block
        // This ensures deletion even if share is cancelled, fails, or app crashes
        try {
          if (await file.exists()) {
            await file.delete();
            AppLogger.debug('Temp export file cleaned up');
          }
        } catch (e) {
          AppLogger.error('SECURITY: Could not delete temp file: ${file.path}', e);
        }
      }

      if (shareResult.status == ShareResultStatus.success ||
          shareResult.status == ShareResultStatus.dismissed) {
        AppLogger.info('Contacts exported: ${contacts.length} contacts');
        return BackupResult.ok(
          filePath: file.path,
          contactCount: contacts.length,
        );
      } else {
        return BackupResult.fromError(BackupError.shareCancelled());
      }
    } on FileSystemException catch (e, stackTrace) {
      AppLogger.error('Export failed - file system error', e);
      final appError = ErrorHandler.fromException(e, stackTrace);
      return BackupResult.fromError(appError);
    } on TimeoutException catch (e, stackTrace) {
      AppLogger.error('Export failed - timeout', e);
      return BackupResult.fromError(
        NetworkError.timeout(originalError: e, stackTrace: stackTrace),
      );
    } catch (e, stackTrace) {
      AppLogger.error('Export failed', e);
      final appError = BackupError.exportFailed(
        details: e.toString(),
        originalError: e,
        stackTrace: stackTrace,
      );
      return BackupResult.fromError(appError);
    }
  }

  /// Export for web platform (copy to clipboard or download)
  Future<BackupResult> _exportForWeb(String jsonString, int count) async {
    // On web, we'll use share which triggers download
    try {
      await Share.share(
        jsonString,
        subject: 'Safety App Contacts Backup',
      );
      return BackupResult.ok(contactCount: count);
    } catch (e, stackTrace) {
      AppLogger.error('Web export failed', e);
      return BackupResult.fromError(
        BackupError.exportFailed(
          details: 'Web export failed',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Save contacts to a file in downloads (for platforms that support it)
  /// Uses app-specific storage to comply with Android scoped storage requirements.
  Future<BackupResult> saveToDownloads(List<ContactModel> contacts) async {
    if (contacts.isEmpty) {
      return BackupResult.fromError(BackupError.noContactsToExport());
    }

    if (kIsWeb) {
      return exportAndShare(contacts);
    }

    try {
      final contactsJson = contacts
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'phone': c.phone,
                'email': c.email,
                'relationship': c.relationship,
                'isSosContact': c.isSosContact,
                'isLocationSharing': c.isLocationSharing,
                'isPrimary': c.isPrimary,
                'addedAt': c.addedAt.toIso8601String(),
              })
          .toList();

      // Generate checksum for integrity verification
      final checksum = _generateChecksum(contactsJson);

      final exportData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'contactCount': contacts.length,
        'contacts': contactsJson,
        'checksum': checksum,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      // Use app-specific external storage (secure, no extra permissions needed)
      // This complies with Android 10+ scoped storage requirements
      Directory? baseDirectory;
      if (Platform.isAndroid) {
        // Use app-specific external storage (secure, sandboxed)
        baseDirectory = await getExternalStorageDirectory();
        if (baseDirectory != null) {
          // Create a Backups subfolder
          final backupsDir = Directory(path.join(baseDirectory.path, 'Backups'));
          if (!await backupsDir.exists()) {
            await backupsDir.create(recursive: true);
          }
          baseDirectory = backupsDir;
        }
      } else if (Platform.isIOS) {
        baseDirectory = await getApplicationDocumentsDirectory();
      } else {
        baseDirectory = await getDownloadsDirectory();
      }

      if (baseDirectory == null) {
        return BackupResult.fromError(
          StorageError.permissionDenied(),
        );
      }

      // Generate safe filename with path traversal protection
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final rawFileName = 'safety_app_contacts_$timestamp.json';

      // Use path.basename to prevent directory traversal attacks
      final safeFileName = path.basename(rawFileName);

      // Validate filename contains only safe characters (security)
      if (!RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(safeFileName)) {
        return BackupResult.fromError(
          BackupError.exportFailed(details: 'Invalid filename generated'),
        );
      }

      // Construct safe path using path.join (prevents traversal)
      final filePath = path.join(baseDirectory.path, safeFileName);

      // Security: Verify the resolved path is still within base directory
      final canonicalBasePath = baseDirectory.absolute.path;
      final resolvedFile = File(filePath);
      final canonicalFilePath = resolvedFile.absolute.path;
      if (!canonicalFilePath.startsWith(canonicalBasePath)) {
        AppLogger.error('Security: Path traversal attempt detected');
        return BackupResult.fromError(
          BackupError.exportFailed(details: 'Security: Invalid file path'),
        );
      }

      await resolvedFile.writeAsString(jsonString);

      AppLogger.info('Contacts saved securely (count: ${contacts.length})');
      return BackupResult.ok(
        filePath: resolvedFile.path,
        contactCount: contacts.length,
      );
    } on FileSystemException catch (e, stackTrace) {
      AppLogger.error('Save to downloads failed - file system error', e);
      if (e.osError?.errorCode == 13) {
        return BackupResult.fromError(
          StorageError.permissionDenied(originalError: e, stackTrace: stackTrace),
        );
      }
      return BackupResult.fromError(
        StorageError.writeFailed(
          details: e.message,
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.error('Save to downloads failed', e);
      return BackupResult.fromError(
        BackupError.exportFailed(
          details: e.toString(),
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Generate SHA-256 checksum for data integrity verification
  String _generateChecksum(dynamic data) {
    final jsonString = json.encode(data);
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Maximum file size for import (5MB) - security limit to prevent DoS
  static const int _maxImportFileSize = 5 * 1024 * 1024;

  /// Maximum number of contacts to import - security limit
  static const int _maxImportContacts = 1000;

  /// Import contacts from a JSON file
  Future<ImportResult> importFromFile() async {
    try {
      // Pick a JSON file with validation
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        // User cancelled file picker - not an error
        return const ImportResult(
          success: false,
          error: 'No file selected',
          recoverySuggestion: 'Please select a backup file to import contacts.',
        );
      }

      final file = result.files.first;

      // Validate file extension (defense in depth)
      if (!file.name.toLowerCase().endsWith('.json')) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'Please select a JSON backup file (*.json).',
          ),
        );
      }

      String jsonString;

      // Handle web vs native
      if (kIsWeb) {
        if (file.bytes == null) {
          return ImportResult.fromError(
            StorageError.readFailed(details: 'Could not read file bytes'),
          );
        }

        // Check file size on web
        if (file.bytes!.length > _maxImportFileSize) {
          return ImportResult.fromError(
            BackupError.importFailed(
              details: 'Backup file too large (${(file.bytes!.length / 1024 / 1024).toStringAsFixed(1)} MB). '
                  'Maximum size: ${_maxImportFileSize ~/ 1024 ~/ 1024} MB.',
            ),
          );
        }

        jsonString = utf8.decode(file.bytes!);
      } else {
        if (file.path == null) {
          return ImportResult.fromError(
            StorageError.fileNotFound(fileName: file.name),
          );
        }

        // Check file size before reading (security: prevent DoS)
        final fileHandle = File(file.path!);
        final fileSize = await fileHandle.length();

        if (fileSize > _maxImportFileSize) {
          return ImportResult.fromError(
            BackupError.importFailed(
              details: 'Backup file too large (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB). '
                  'Maximum size: ${_maxImportFileSize ~/ 1024 ~/ 1024} MB.',
            ),
          );
        }

        // Check minimum size (valid JSON must have some content)
        if (fileSize < 50) {
          return ImportResult.fromError(
            BackupError.invalidBackupFile(
              details: 'Backup file is too small to be valid.',
            ),
          );
        }

        jsonString = await fileHandle.readAsString();
      }

      return importFromJson(jsonString);
    } on FileSystemException catch (e, stackTrace) {
      AppLogger.error('Import failed - file system error', e);
      if (e.osError?.errorCode == 2) {
        return ImportResult.fromError(
          StorageError.fileNotFound(originalError: e, stackTrace: stackTrace),
        );
      }
      if (e.osError?.errorCode == 13) {
        return ImportResult.fromError(
          StorageError.permissionDenied(originalError: e, stackTrace: stackTrace),
        );
      }
      return ImportResult.fromError(
        StorageError.readFailed(
          details: e.message,
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    } on FormatException catch (e, stackTrace) {
      AppLogger.error('Import failed - format error', e);
      return ImportResult.fromError(
        BackupError.invalidBackupFile(
          details: 'File is not valid UTF-8 text',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.error('Import failed', e);
      return ImportResult.fromError(
        BackupError.importFailed(
          details: e.toString(),
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Import contacts from JSON string
  ImportResult importFromJson(String jsonString) {
    try {
      final data = json.decode(jsonString);

      // Validate format
      if (data is! Map<String, dynamic>) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'Expected JSON object at root level',
          ),
        );
      }

      // Strict version validation (security: reject invalid versions)
      final version = data['version'] as int?;
      if (version == null) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'Backup file is missing version information.',
          ),
        );
      }

      if (version < 1 || version > 1) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'Backup file version $version is not supported. '
                '${version < 1 ? "File may be corrupted." : "Please update the app."}',
          ),
        );
      }

      // Verify required structure
      if (!data.containsKey('exportedAt') ||
          !data.containsKey('contactCount') ||
          !data.containsKey('contacts')) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'Backup file is missing required fields.',
          ),
        );
      }

      final contactsList = data['contacts'] as List?;
      if (contactsList == null) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'No contacts array found in backup file',
          ),
        );
      }

      if (contactsList.isEmpty) {
        return const ImportResult(
          success: false,
          error: 'No contacts in backup file',
          recoverySuggestion: 'The backup file is empty. Please select a backup that contains contacts.',
        );
      }

      // Security: Limit number of contacts to import
      if (contactsList.length > _maxImportContacts) {
        return ImportResult.fromError(
          BackupError.importFailed(
            details: 'Too many contacts in backup file (${contactsList.length}). '
                'Maximum supported: $_maxImportContacts contacts.',
          ),
        );
      }

      // Verify checksum if present (integrity check)
      final storedChecksum = data['checksum'] as String?;
      if (storedChecksum != null) {
        final calculatedChecksum = _generateChecksum(contactsList);
        if (calculatedChecksum != storedChecksum) {
          return ImportResult.fromError(
            BackupError.invalidBackupFile(
              details: 'Backup file checksum mismatch. File may have been tampered with.',
            ),
          );
        }
        AppLogger.info('Backup checksum verified successfully');
      }

      final contacts = <ContactModel>[];
      int skippedCount = 0;

      for (final item in contactsList) {
        try {
          // Security: Validate and sanitize email before importing
          String? email;
          if (item['email'] != null) {
            final emailStr = item['email'] as String;

            // Check for injection attacks in email
            if (Validators.containsSqlInjection(emailStr) ||
                Validators.containsXss(emailStr)) {
              skippedCount++;
              AppLogger.warning('Skipping contact with malicious email');
              continue;
            }

            // Validate email format (allow empty but not invalid)
            final emailError = Validators.validateEmail(emailStr, allowEmpty: true);
            if (emailError == null || emailStr.isEmpty) {
              email = emailStr.trim().toLowerCase();
            } else {
              // Invalid email format, set to null instead of skipping contact
              email = null;
              AppLogger.warning('Ignoring invalid email format for contact');
            }
          }

          // Security: Validate and sanitize name
          final rawName = item['name'] as String? ?? '';
          if (Validators.containsSqlInjection(rawName) ||
              Validators.containsXss(rawName)) {
            skippedCount++;
            AppLogger.warning('Skipping contact with malicious name');
            continue;
          }
          final sanitizedName = Validators.sanitizeName(rawName);

          // Security: Validate and sanitize relationship
          String? relationship;
          if (item['relationship'] != null) {
            final rawRelationship = item['relationship'] as String;
            if (!Validators.containsSqlInjection(rawRelationship) &&
                !Validators.containsXss(rawRelationship)) {
              relationship = Validators.sanitizeForDatabase(rawRelationship);
            }
          }

          // Parse date safely
          DateTime addedAt;
          try {
            addedAt = item['addedAt'] != null
                ? DateTime.parse(item['addedAt'] as String)
                : DateTime.now();
          } catch (e) {
            addedAt = DateTime.now();
            AppLogger.warning('Invalid date format in backup, using current time');
          }

          final contact = ContactModel(
            id: item['id'] as String? ?? '',
            name: sanitizedName,
            phone: item['phone'] as String? ?? '',
            email: email,
            relationship: relationship,
            isSosContact: item['isSosContact'] as bool? ?? true,
            isLocationSharing: item['isLocationSharing'] as bool? ?? false,
            isPrimary: item['isPrimary'] as bool? ?? false,
            addedAt: addedAt,
            isSynced: false, // Will need to sync after import
          );

          // Validate required fields
          if (contact.name.isNotEmpty && contact.phone.isNotEmpty) {
            contacts.add(contact);
          } else {
            skippedCount++;
            AppLogger.warning('Skipping contact with missing name or phone');
          }
        } catch (e) {
          skippedCount++;
          AppLogger.warning('Skipping invalid contact: $e');
        }
      }

      if (contacts.isEmpty) {
        return ImportResult.fromError(
          BackupError.invalidBackupFile(
            details: 'No valid contacts found. $skippedCount contact(s) had invalid data.',
          ),
        );
      }

      AppLogger.info('Imported ${contacts.length} contacts from backup (skipped $skippedCount)');
      return ImportResult.ok(contacts: contacts);
    } on FormatException catch (e, stackTrace) {
      AppLogger.error('JSON parse error', e);
      return ImportResult.fromError(
        BackupError.invalidBackupFile(
          details: 'Invalid JSON format: ${e.message}',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.error('Parse error', e);
      return ImportResult.fromError(
        BackupError.importFailed(
          details: 'Failed to parse backup file: $e',
          originalError: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
