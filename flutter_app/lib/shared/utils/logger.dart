import 'package:flutter/foundation.dart';

/// Secure logger utility that only logs in debug mode.
/// This prevents sensitive information from being exposed in production.
class AppLogger {
  AppLogger._();

  /// Log a debug message (only in debug mode)
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// Log an info message (only in debug mode)
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('[INFO] $message');
    }
  }

  /// Log a warning message (only in debug mode)
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('[WARNING] $message');
    }
  }

  /// Log an error message (only in debug mode)
  /// In production, you could send this to a crash reporting service
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) {
        debugPrint('[ERROR] $error');
      }
      if (stackTrace != null) {
        debugPrint('[STACK] $stackTrace');
      }
    }
    // In production, send to crash reporting service like Firebase Crashlytics
    // if (!kDebugMode) {
    //   FirebaseCrashlytics.instance.recordError(error, stackTrace);
    // }
  }
}
