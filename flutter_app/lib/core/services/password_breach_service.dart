import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Result status for password breach check
enum BreachCheckStatus {
  safe,
  breached,
  offline,
  timeout,
  error,
}

/// Result of password breach check
class PasswordBreachResult {
  final BreachCheckStatus status;
  final int breachCount;
  final String? errorMessage;

  const PasswordBreachResult._({
    required this.status,
    this.breachCount = 0,
    this.errorMessage,
  });

  factory PasswordBreachResult.safe() =>
      const PasswordBreachResult._(status: BreachCheckStatus.safe);

  factory PasswordBreachResult.breached(int count) =>
      PasswordBreachResult._(status: BreachCheckStatus.breached, breachCount: count);

  factory PasswordBreachResult.offline() =>
      const PasswordBreachResult._(status: BreachCheckStatus.offline);

  factory PasswordBreachResult.timeout() =>
      const PasswordBreachResult._(status: BreachCheckStatus.timeout);

  factory PasswordBreachResult.error(String message) =>
      PasswordBreachResult._(status: BreachCheckStatus.error, errorMessage: message);

  bool get isBreached => status == BreachCheckStatus.breached;
  bool get isSafe => status == BreachCheckStatus.safe;
  bool get isOffline => status == BreachCheckStatus.offline;
  bool get hasError => status == BreachCheckStatus.error || status == BreachCheckStatus.timeout;
}

/// Service to check passwords against HaveIBeenPwned breach database.
/// Uses k-anonymity model - only sends first 5 chars of SHA-1 hash.
///
/// Security guarantees:
/// - Password never leaves device unhashed
/// - Full hash never sent to API (k-anonymity)
/// - Only 5-char prefix sent, making reverse lookup infeasible
class PasswordBreachService {
  final Dio _dio;
  final Connectivity _connectivity;
  final bool _ownsDio;

  // Rate limiting: prevent API abuse (max 2 checks per second)
  DateTime? _lastCheckTime;
  static const _minCheckInterval = Duration(milliseconds: 500);

  // LRU cache for recent password checks (stores hash prefix+suffix, not password)
  final _cache = <String, PasswordBreachResult>{};
  static const _maxCacheSize = 10;
  static const _apiBaseUrl = 'https://api.pwnedpasswords.com/range/';

  PasswordBreachService({Dio? dio, Connectivity? connectivity})
      : _dio = dio ?? Dio(),
        _connectivity = connectivity ?? Connectivity(),
        _ownsDio = dio == null;

  /// Dispose resources owned by this service.
  /// Call this when the service is no longer needed.
  void dispose() {
    if (_ownsDio) {
      _dio.close(force: true);
    }
    _cache.clear();
  }

  /// Check if password exists in HIBP breach database using k-anonymity.
  ///
  /// How it works:
  /// 1. SHA-1 hash the password locally
  /// 2. Send only first 5 chars of hash to HIBP
  /// 3. HIBP returns all hash suffixes matching that prefix (~800 entries)
  /// 4. Check if our full hash suffix exists in response
  /// 5. If found, password is breached
  Future<PasswordBreachResult> checkPassword(String password) async {
    // Rate limiting: prevent API abuse
    if (_lastCheckTime != null) {
      final elapsed = DateTime.now().difference(_lastCheckTime!);
      if (elapsed < _minCheckInterval) {
        await Future.delayed(_minCheckInterval - elapsed);
      }
    }
    _lastCheckTime = DateTime.now();

    // 1. Check connectivity FIRST (proactive offline detection)
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return PasswordBreachResult.offline();
    }

    // 2. Generate SHA-1 hash of password (client-side only)
    final hash = _sha1Hash(password).toUpperCase();
    final prefix = hash.substring(0, 5);
    final suffix = hash.substring(5);

    // 3. Check cache first (key is hash, not password - secure)
    final cacheKey = '$prefix$suffix';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 4. Call HIBP API with only the prefix (k-anonymity)
    try {
      final response = await _dio.get(
        '$_apiBaseUrl$prefix',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'User-Agent': 'SafetyApp-Flutter/1.0',
            'Add-Padding': 'true', // Extra k-anonymity protection
          },
        ),
      );

      if (response.statusCode != 200) {
        // Don't expose HTTP status codes to users (security best practice)
        return PasswordBreachResult.error('Service temporarily unavailable');
      }

      // 5. Search response for our suffix
      final result = _parseResponse(response.data as String, suffix);

      // 6. Cache the result (keyed by hash, not password)
      _addToCache(cacheKey, result);

      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return PasswordBreachResult.timeout();
      }
      // Don't expose internal error details
      return PasswordBreachResult.error('Network error');
    } catch (_) {
      return PasswordBreachResult.error('Unexpected error');
    }
  }

  /// Parse HIBP response to find if our hash suffix exists.
  /// Response format: "SUFFIX:COUNT\r\nSUFFIX:COUNT\r\n..."
  PasswordBreachResult _parseResponse(String body, String suffix) {
    final lines = body.split('\n');
    for (final line in lines) {
      final parts = line.split(':');
      if (parts.length == 2) {
        final hashSuffix = parts[0].trim().toUpperCase();
        final count = int.tryParse(parts[1].trim()) ?? 0;

        if (hashSuffix == suffix) {
          return PasswordBreachResult.breached(count);
        }
      }
    }
    return PasswordBreachResult.safe();
  }

  /// Generate SHA-1 hash of input string.
  /// SHA-1 is used because HIBP API uses SHA-1 (not for security, just for lookup).
  String _sha1Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha1.convert(bytes);
    return digest.toString();
  }

  /// Add result to cache with LRU eviction.
  void _addToCache(String key, PasswordBreachResult result) {
    // Simple LRU: remove oldest if at capacity
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  /// Clear the cache (useful for testing)
  void clearCache() => _cache.clear();
}
