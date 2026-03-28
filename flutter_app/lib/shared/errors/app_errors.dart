import 'dart:async';
import 'dart:io';

/// Error codes for tracking and debugging
enum ErrorCode {
  // Network errors (1xx)
  networkOffline('E101'),
  networkTimeout('E102'),
  networkUnreachable('E103'),
  serverError('E104'),

  // Storage errors (2xx)
  storageReadFailed('E201'),
  storageWriteFailed('E202'),
  storagePermissionDenied('E203'),
  storageFull('E204'),
  fileNotFound('E205'),

  // Sync errors (3xx)
  syncFailed('E301'),
  syncTimeout('E302'),
  syncConflict('E303'),
  syncRateLimited('E304'),

  // Auth errors (4xx)
  notLoggedIn('E401'),
  sessionExpired('E402'),
  unauthorized('E403'),

  // Validation errors (5xx)
  invalidInput('E501'),
  invalidFormat('E502'),
  emptyData('E503'),

  // Import/Export errors (6xx)
  exportFailed('E601'),
  importFailed('E602'),
  invalidBackupFile('E603'),
  noContactsToExport('E604'),
  shareCancelled('E605'),

  // Unknown
  unknown('E999');

  final String code;
  const ErrorCode(this.code);
}

/// Base class for app-specific errors with user-friendly messages
class AppError implements Exception {
  final ErrorCode code;
  final String message;
  final String userMessage;
  final String? recoverySuggestion;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const AppError({
    required this.code,
    required this.message,
    required this.userMessage,
    this.recoverySuggestion,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => '[$code] $message';

  /// Format for logging
  String toLogString() {
    final buffer = StringBuffer();
    buffer.writeln('[${code.code}] $message');
    if (originalError != null) {
      buffer.writeln('Caused by: $originalError');
    }
    if (stackTrace != null) {
      buffer.writeln('Stack trace: $stackTrace');
    }
    return buffer.toString();
  }
}

/// Network-related errors
class NetworkError extends AppError {
  const NetworkError._({
    required super.code,
    required super.message,
    required super.userMessage,
    super.recoverySuggestion,
    super.originalError,
    super.stackTrace,
  });

  factory NetworkError.offline({dynamic originalError, StackTrace? stackTrace}) {
    return NetworkError._(
      code: ErrorCode.networkOffline,
      message: 'Device is offline',
      userMessage: 'No internet connection',
      recoverySuggestion: 'Please check your Wi-Fi or mobile data and try again.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory NetworkError.timeout({dynamic originalError, StackTrace? stackTrace}) {
    return NetworkError._(
      code: ErrorCode.networkTimeout,
      message: 'Network request timed out',
      userMessage: 'Connection timed out',
      recoverySuggestion: 'The server is taking too long to respond. Please try again later.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory NetworkError.serverError({
    String? details,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return NetworkError._(
      code: ErrorCode.serverError,
      message: details ?? 'Server returned an error',
      userMessage: 'Server error occurred',
      recoverySuggestion: 'There\'s a problem with our servers. Please try again in a few minutes.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }
}

/// Storage-related errors
class StorageError extends AppError {
  const StorageError._({
    required super.code,
    required super.message,
    required super.userMessage,
    super.recoverySuggestion,
    super.originalError,
    super.stackTrace,
  });

  factory StorageError.readFailed({
    String? details,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return StorageError._(
      code: ErrorCode.storageReadFailed,
      message: details ?? 'Failed to read from storage',
      userMessage: 'Unable to load data',
      recoverySuggestion: 'Try restarting the app. If the problem persists, clear app data.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory StorageError.writeFailed({
    String? details,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return StorageError._(
      code: ErrorCode.storageWriteFailed,
      message: details ?? 'Failed to write to storage',
      userMessage: 'Unable to save data',
      recoverySuggestion: 'Check if you have enough storage space and try again.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory StorageError.permissionDenied({
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return StorageError._(
      code: ErrorCode.storagePermissionDenied,
      message: 'Storage permission denied',
      userMessage: 'Storage access denied',
      recoverySuggestion: 'Please grant storage permission in Settings to save files.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory StorageError.fileNotFound({
    String? fileName,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return StorageError._(
      code: ErrorCode.fileNotFound,
      message: 'File not found: ${fileName ?? 'unknown'}',
      userMessage: 'File not found',
      recoverySuggestion: 'The file may have been moved or deleted. Please select a different file.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }
}

/// Sync-related errors
class SyncError extends AppError {
  const SyncError._({
    required super.code,
    required super.message,
    required super.userMessage,
    super.recoverySuggestion,
    super.originalError,
    super.stackTrace,
  });

  factory SyncError.failed({
    String? details,
    int syncedCount = 0,
    int failedCount = 0,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    String userMsg = 'Failed to sync contacts';
    if (failedCount > 0) {
      userMsg = '$failedCount contact(s) failed to sync';
    }

    return SyncError._(
      code: ErrorCode.syncFailed,
      message: details ?? 'Sync operation failed',
      userMessage: userMsg,
      recoverySuggestion: 'Check your internet connection and try again. '
          'Your contacts are saved locally and will sync when online.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory SyncError.timeout({dynamic originalError, StackTrace? stackTrace}) {
    return SyncError._(
      code: ErrorCode.syncTimeout,
      message: 'Sync operation timed out',
      userMessage: 'Sync timed out',
      recoverySuggestion: 'The sync is taking too long. Please try again with a better connection.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory SyncError.rateLimited({dynamic originalError, StackTrace? stackTrace}) {
    return SyncError._(
      code: ErrorCode.syncRateLimited,
      message: 'Sync rate limited',
      userMessage: 'Please wait before retrying',
      recoverySuggestion: 'Too many sync attempts. Please wait a few seconds and try again.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }
}

/// Auth-related errors
class AuthError extends AppError {
  const AuthError._({
    required super.code,
    required super.message,
    required super.userMessage,
    super.recoverySuggestion,
    super.originalError,
    super.stackTrace,
  });

  factory AuthError.notLoggedIn({dynamic originalError, StackTrace? stackTrace}) {
    return AuthError._(
      code: ErrorCode.notLoggedIn,
      message: 'User not logged in',
      userMessage: 'Please log in to continue',
      recoverySuggestion: 'Log in to sync your contacts across devices.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory AuthError.sessionExpired({dynamic originalError, StackTrace? stackTrace}) {
    return AuthError._(
      code: ErrorCode.sessionExpired,
      message: 'Session expired',
      userMessage: 'Your session has expired',
      recoverySuggestion: 'Please log in again to continue.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }
}

/// Import/Export errors
class BackupError extends AppError {
  const BackupError._({
    required super.code,
    required super.message,
    required super.userMessage,
    super.recoverySuggestion,
    super.originalError,
    super.stackTrace,
  });

  factory BackupError.exportFailed({
    String? details,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return BackupError._(
      code: ErrorCode.exportFailed,
      message: details ?? 'Export operation failed',
      userMessage: 'Failed to export contacts',
      recoverySuggestion: 'Check your storage permissions and try again.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory BackupError.importFailed({
    String? details,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return BackupError._(
      code: ErrorCode.importFailed,
      message: details ?? 'Import operation failed',
      userMessage: 'Failed to import contacts',
      recoverySuggestion: 'Make sure the file is a valid Safety App backup file.',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory BackupError.invalidBackupFile({
    String? details,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return BackupError._(
      code: ErrorCode.invalidBackupFile,
      message: details ?? 'Invalid backup file format',
      userMessage: 'Invalid backup file',
      recoverySuggestion: 'The file format is not recognized. Please select a valid Safety App backup file (.json).',
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  factory BackupError.noContactsToExport() {
    return const BackupError._(
      code: ErrorCode.noContactsToExport,
      message: 'No contacts to export',
      userMessage: 'No contacts to export',
      recoverySuggestion: 'Add some contacts first before exporting.',
    );
  }

  factory BackupError.shareCancelled() {
    return const BackupError._(
      code: ErrorCode.shareCancelled,
      message: 'Share was cancelled',
      userMessage: 'Export cancelled',
      recoverySuggestion: null, // No recovery needed, user cancelled
    );
  }
}

/// Validation errors
class ValidationError extends AppError {
  const ValidationError._({
    required super.code,
    required super.message,
    required super.userMessage,
    super.recoverySuggestion,
  });

  factory ValidationError.emptyData({String? fieldName}) {
    return ValidationError._(
      code: ErrorCode.emptyData,
      message: 'Empty data: ${fieldName ?? 'field'}',
      userMessage: '${fieldName ?? 'Field'} cannot be empty',
      recoverySuggestion: 'Please fill in the required information.',
    );
  }

  factory ValidationError.invalidFormat({
    required String fieldName,
    String? expected,
  }) {
    return ValidationError._(
      code: ErrorCode.invalidFormat,
      message: 'Invalid format for $fieldName',
      userMessage: 'Invalid $fieldName format',
      recoverySuggestion: expected != null
          ? 'Please use the correct format: $expected'
          : 'Please check and correct the $fieldName.',
    );
  }
}

/// Utility class for handling and converting exceptions
class ErrorHandler {
  ErrorHandler._();

  /// Convert any exception to an AppError
  static AppError fromException(dynamic error, [StackTrace? stackTrace]) {
    if (error is AppError) {
      return error;
    }

    if (error is SocketException) {
      return NetworkError.offline(originalError: error, stackTrace: stackTrace);
    }

    if (error is TimeoutException) {
      return NetworkError.timeout(originalError: error, stackTrace: stackTrace);
    }

    if (error is FileSystemException) {
      if (error.osError?.errorCode == 13) { // EACCES
        return StorageError.permissionDenied(
          originalError: error,
          stackTrace: stackTrace,
        );
      }
      if (error.osError?.errorCode == 2) { // ENOENT
        return StorageError.fileNotFound(
          fileName: error.path,
          originalError: error,
          stackTrace: stackTrace,
        );
      }
      return StorageError.writeFailed(
        details: error.message,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (error is FormatException) {
      return BackupError.invalidBackupFile(
        details: error.message,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Generic fallback
    return AppError(
      code: ErrorCode.unknown,
      message: error.toString(),
      userMessage: 'An unexpected error occurred',
      recoverySuggestion: 'Please try again. If the problem persists, restart the app.',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Get user-friendly message from any error
  static String getUserMessage(dynamic error) {
    if (error is AppError) {
      return error.userMessage;
    }
    return fromException(error).userMessage;
  }

  /// Get recovery suggestion from any error
  static String? getRecoverySuggestion(dynamic error) {
    if (error is AppError) {
      return error.recoverySuggestion;
    }
    return fromException(error).recoverySuggestion;
  }

  /// Get error code from any error
  static String getErrorCode(dynamic error) {
    if (error is AppError) {
      return error.code.code;
    }
    return fromException(error).code.code;
  }
}
