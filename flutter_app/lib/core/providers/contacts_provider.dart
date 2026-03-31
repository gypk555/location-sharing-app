import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/contact_model.dart';
import '../services/contacts_backup_service.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/errors/app_errors.dart';
import '../../shared/utils/logger.dart';
import '../../shared/utils/validators.dart';

final contactsProvider =
    StateNotifierProvider<ContactsNotifier, ContactsState>((ref) {
  return ContactsNotifier();
});

/// Result of a sync operation
class SyncResult {
  final bool success;
  final String? error;
  final String? recoverySuggestion;
  final String? errorCode;
  final int syncedCount;
  final int failedCount;
  final bool wasOffline;

  const SyncResult({
    required this.success,
    this.error,
    this.recoverySuggestion,
    this.errorCode,
    this.syncedCount = 0,
    this.failedCount = 0,
    this.wasOffline = false,
  });

  /// Create a successful result
  factory SyncResult.ok({int syncedCount = 0}) {
    return SyncResult(
      success: true,
      syncedCount: syncedCount,
    );
  }

  /// Create a failed result from an AppError
  factory SyncResult.fromError(
    AppError error, {
    int syncedCount = 0,
    int failedCount = 0,
    bool wasOffline = false,
  }) {
    return SyncResult(
      success: false,
      error: error.userMessage,
      recoverySuggestion: error.recoverySuggestion,
      errorCode: error.code.code,
      syncedCount: syncedCount,
      failedCount: failedCount,
      wasOffline: wasOffline,
    );
  }
}

class ContactsState {
  final List<ContactModel> contacts;
  final bool isLoading;
  final String? error;
  final List<String> pendingDeletes; // IDs pending deletion from Supabase
  final bool isSyncing;

  const ContactsState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
    this.pendingDeletes = const [],
    this.isSyncing = false,
  });

  List<ContactModel> get sosContacts =>
      contacts.where((c) => c.isSosContact).toList();

  List<ContactModel> get locationSharingContacts =>
      contacts.where((c) => c.isLocationSharing).toList();

  /// Get contacts that failed to sync
  List<ContactModel> get unsyncedContacts =>
      contacts.where((c) => !c.isSynced).toList();

  ContactsState copyWith({
    List<ContactModel>? contacts,
    bool? isLoading,
    String? error,
    List<String>? pendingDeletes,
    bool? isSyncing,
  }) {
    return ContactsState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      pendingDeletes: pendingDeletes ?? this.pendingDeletes,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

class ContactsNotifier extends StateNotifier<ContactsState> {
  final _uuid = const Uuid();

  /// Timeout for sync operations (20 seconds - more forgiving for rural areas)
  static const _syncTimeout = Duration(seconds: 20);

  /// Timeout for connectivity check
  static const _connectivityTimeout = Duration(seconds: 3);

  /// Maximum contacts per batch for Supabase bulk operations
  static const _batchSize = 50;

  /// Cached Hive box to avoid repeated opens (performance optimization)
  Box<ContactModel>? _contactsBox;

  /// Mutex lock for Hive operations to prevent race conditions
  Completer<void>? _hiveLock;

  /// Track consecutive sync failures for exponential backoff
  int _consecutiveFailures = 0;

  DateTime? _lastSyncAttempt;

  /// Debounce timer for toggle operations
  Timer? _debounceTimer;

  /// Connectivity stream subscription (listen instead of poll)
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Cached connectivity status
  bool _isConnected = true;

  /// Track if notifier has been disposed (prevents callbacks after disposal)
  bool _disposed = false;

  /// Rate limiting for import operations
  DateTime? _lastImportAttempt;
  static const _importCooldown = Duration(seconds: 10);

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      return null;
    }
  }

  String? get _currentUserId => _supabase?.auth.currentUser?.id;

  /// Get cached Hive box (performance: avoid reopening on every operation)
  Future<Box<ContactModel>> get _box async {
    if (_contactsBox == null || !_contactsBox!.isOpen) {
      _contactsBox = await Hive.openBox<ContactModel>(AppConstants.contactsBoxName);
    }
    return _contactsBox!;
  }

  /// Acquire mutex lock for Hive operations (prevents race conditions)
  Future<void> _acquireHiveLock() async {
    while (_hiveLock != null) {
      await _hiveLock!.future;
    }
    _hiveLock = Completer<void>();
  }

  /// Release mutex lock for Hive operations
  void _releaseHiveLock() {
    final lock = _hiveLock;
    _hiveLock = null;
    lock?.complete();
  }

  /// Execute a Hive operation with mutex protection
  Future<T> _withHiveLock<T>(Future<T> Function() operation) async {
    await _acquireHiveLock();
    try {
      return await operation();
    } finally {
      _releaseHiveLock();
    }
  }

  ContactsNotifier() : super(const ContactsState(isLoading: true)) {
    // Schedule load for next microtask to avoid blocking constructor
    Future.microtask(() => _loadContacts());
    // Initialize connectivity listener (more efficient than polling)
    _initConnectivityListener();
  }

  /// Initialize connectivity stream listener
  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        // Don't process if disposed (prevents callbacks after disposal)
        if (_disposed) return;

        final wasConnected = _isConnected;
        _isConnected = !results.contains(ConnectivityResult.none);

        // Auto-sync when coming back online
        if (!wasConnected && _isConnected) {
          AppLogger.info('Back online - triggering sync');
          _consecutiveFailures = 0; // Reset backoff

          // Check if sync is already in progress (prevents race condition)
          if (!state.isSyncing) {
            syncToSupabase();
          } else {
            AppLogger.info('Sync already in progress, skipping auto-sync');
          }
        }
      },
      onError: (e) {
        AppLogger.warning('Connectivity listener error: $e');
      },
      cancelOnError: false, // Continue listening even after errors
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Check if device is online
  /// Uses cached connectivity status from stream listener (more efficient)
  /// Falls back to direct check if needed
  Future<bool> _isOnline() async {
    // Use cached status if connectivity listener is active
    if (_connectivitySubscription != null) {
      return _isConnected;
    }

    // Fallback to direct check with timeout
    try {
      final connectivityResult = await Connectivity()
          .checkConnectivity()
          .timeout(_connectivityTimeout);
      _isConnected = !connectivityResult.contains(ConnectivityResult.none);
      return _isConnected;
    } on TimeoutException catch (_) {
      AppLogger.warning('Connectivity check timed out');
      return true; // Assume online if check times out
    } catch (e) {
      AppLogger.warning('Could not check connectivity');
      return true; // Assume online if check fails
    }
  }

  /// Secure random generator for jitter (security: prevents predictable timing)
  final _random = Random.secure();

  /// Calculate backoff duration based on consecutive failures (exponential backoff with jitter)
  /// Jitter prevents thundering herd problem when multiple devices retry simultaneously
  Duration _getBackoffDuration() {
    final baseSeconds = switch (_consecutiveFailures) {
      0 => 2,
      1 => 4,
      2 => 8,
      _ => 16, // Max backoff for 3+ failures
    };

    // Add jitter: random value between 0-25% of base duration
    // Minimum jitter of 1ms to prevent nextInt(0) edge case
    final jitterMs = _random.nextInt((baseSeconds * 250).clamp(1, 5000));
    return Duration(seconds: baseSeconds, milliseconds: jitterMs);
  }

  /// Check if enough time has passed since last sync attempt (with exponential backoff)
  bool _canAttemptSync() {
    if (_lastSyncAttempt == null) return true;
    final backoff = _getBackoffDuration();
    return DateTime.now().difference(_lastSyncAttempt!) >= backoff;
  }

  /// Load contacts from local storage first, then sync with Supabase in background.
  /// Uses non-blocking startup pattern: show local data immediately, sync in background.
  Future<void> _loadContacts() async {
    try {
      // First load from local Hive using cached box
      final box = await _box;
      final localContacts = box.values.toList();

      // Show local contacts immediately and mark as ready (non-blocking startup)
      state = ContactsState(
        contacts: localContacts,
        isLoading: false, // UI is ready NOW - critical for emergency access
      );

      // Sync in background without blocking UI
      unawaited(_backgroundSync(localContacts));
    } on HiveError catch (e, stackTrace) {
      AppLogger.error('Hive error loading contacts', e);
      final appError = StorageError.readFailed(
        details: 'Local database error',
        originalError: e,
        stackTrace: stackTrace,
      );
      state = ContactsState(
        isLoading: false,
        error: appError.userMessage,
      );
    } catch (e, stackTrace) {
      AppLogger.error('Error loading contacts', e);
      final appError = ErrorHandler.fromException(e, stackTrace);
      state = ContactsState(
        isLoading: false,
        error: appError.userMessage,
      );
    }
  }

  /// Background sync operation - doesn't block UI
  Future<void> _backgroundSync(List<ContactModel> localContacts) async {
    // Check if online first to avoid wasted attempts
    final online = await _isOnline();
    if (!online) {
      AppLogger.info('Offline - skipping background sync');
      return;
    }

    state = state.copyWith(isSyncing: true);

    try {
      // First push any unsynced local contacts to Supabase
      await _pushUnsyncedToSupabase(localContacts);

      // Then pull and merge from Supabase
      await _syncFromSupabase();

      _consecutiveFailures = 0; // Reset on success
    } on SocketException catch (_) {
      AppLogger.warning('Network error during background sync');
      _consecutiveFailures++;
    } catch (e) {
      AppLogger.warning('Background sync failed');
      _consecutiveFailures++;
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  /// Push unsynced local contacts to Supabase before pulling (batch operation)
  Future<void> _pushUnsyncedToSupabase(List<ContactModel> localContacts) async {
    if (_supabase == null || _currentUserId == null) return;

    final unsyncedContacts = localContacts.where((c) => !c.isSynced).toList();
    if (unsyncedContacts.isEmpty) return;

    // Batch insert for better performance (fewer HTTP requests = less battery drain)
    // Process in chunks to avoid payload size limits
    for (var i = 0; i < unsyncedContacts.length; i += _batchSize) {
      final batch = unsyncedContacts.skip(i).take(_batchSize).toList();
      final batchData = batch.map((c) => c.toSupabase(_currentUserId!)).toList();

      try {
        // Use upsert to handle both new and existing contacts
        await _supabase!
            .from('emergency_contacts')
            .upsert(batchData, onConflict: 'id');
        AppLogger.info('Batch pushed ${batch.length} contacts');
      } catch (e) {
        // Fallback to individual inserts if batch fails
        AppLogger.warning('Batch push failed, falling back to individual inserts');
        for (final contact in batch) {
          try {
            await _supabase!
                .from('emergency_contacts')
                .upsert(contact.toSupabase(_currentUserId!), onConflict: 'id');
          } catch (e) {
            AppLogger.warning('Could not push contact ${contact.id}');
          }
        }
      }
    }
  }

  /// Sync contacts from Supabase to local storage (merge, not replace)
  /// Uses mutex to prevent race conditions during box clear/repopulate
  Future<void> _syncFromSupabase() async {
    if (_supabase == null || _currentUserId == null) return;

    try {
      final response = await _supabase!
          .from('emergency_contacts')
          .select()
          .eq('user_id', _currentUserId!);

      // Supabase returns List<Map<String, dynamic>> - filter to ensure type safety
      final supabaseContacts = response
          .whereType<Map<String, dynamic>>()
          .map((json) => ContactModel.fromSupabase(json))
          .toList();

      // Use mutex to protect critical Hive operations (prevents race conditions)
      final mergedContacts = await _withHiveLock(() async {
        final box = await _box;
        final localContacts = box.values.toList();

        // Find local-only contacts (not in Supabase, failed to sync)
        final supabaseIds = supabaseContacts.map((c) => c.id).toSet();
        final localOnlyContacts = localContacts
            .where((c) => !c.isSynced && !supabaseIds.contains(c.id))
            .toList();

        // Merge: Supabase contacts + local-only contacts
        final merged = [...supabaseContacts, ...localOnlyContacts];

        // Save merged contacts to local storage (atomic operation with mutex)
        await box.clear();
        for (final contact in merged) {
          await box.add(contact);
        }

        return merged;
      });

      state = state.copyWith(contacts: mergedContacts);
      AppLogger.info(
          'Synced ${supabaseContacts.length} from Supabase, kept ${mergedContacts.length - supabaseContacts.length} local-only');
    } catch (e) {
      AppLogger.error('Error syncing from Supabase', e);
      // Keep local contacts if sync fails
    }
  }

  /// Sync unsynced contacts to Supabase and retry pending deletes
  /// Returns a SyncResult indicating success/failure
  Future<SyncResult> syncToSupabase() async {
    // Check rate limiting
    if (!_canAttemptSync()) {
      AppLogger.warning('Sync attempted too quickly, waiting...');
      return SyncResult.fromError(SyncError.rateLimited());
    }

    // Check if online
    final online = await _isOnline();
    if (!online) {
      AppLogger.warning('Device is offline, cannot sync');
      return SyncResult.fromError(
        NetworkError.offline(),
        wasOffline: true,
      );
    }

    if (_supabase == null || _currentUserId == null) {
      return SyncResult.fromError(AuthError.notLoggedIn());
    }

    _lastSyncAttempt = DateTime.now();
    state = state.copyWith(isSyncing: true);

    int syncedCount = 0;
    int failedCount = 0;

    try {
      // First, retry pending deletes with timeout
      await retryPendingDeletes().timeout(_syncTimeout);

      // Then sync unsynced contacts
      final unsyncedContacts = state.contacts.where((c) => !c.isSynced).toList();

      for (final contact in unsyncedContacts) {
        try {
          // Check if contact exists in Supabase already
          final isNew = contact.userId == null || contact.userId != _currentUserId;
          await _syncContactToSupabase(contact, isNew: isNew)
              .timeout(_syncTimeout);
          syncedCount++;
        } on TimeoutException catch (e) {
          // Security: Log ID only, never PII like name/phone
          AppLogger.error('Timeout syncing contact ${contact.id}', e);
          failedCount++;
        } on SocketException catch (e) {
          AppLogger.error('Network error syncing contact ${contact.id}', e);
          failedCount++;
        } on PostgrestException catch (e) {
          AppLogger.error('Database error syncing contact ${contact.id}: ${e.message}', e);
          failedCount++;
        } catch (e) {
          AppLogger.error('Failed to sync contact ${contact.id}', e);
          failedCount++;
        }
      }

      state = state.copyWith(isSyncing: false);

      final allSynced = failedCount == 0 && state.unsyncedContacts.isEmpty;
      if (allSynced) {
        return SyncResult.ok(syncedCount: syncedCount);
      }

      return SyncResult.fromError(
        SyncError.failed(
          syncedCount: syncedCount,
          failedCount: failedCount,
        ),
        syncedCount: syncedCount,
        failedCount: failedCount,
      );
    } on TimeoutException catch (e, stackTrace) {
      state = state.copyWith(isSyncing: false);
      AppLogger.error('Sync timed out', e);
      return SyncResult.fromError(
        SyncError.timeout(originalError: e, stackTrace: stackTrace),
        syncedCount: syncedCount,
        failedCount: failedCount,
      );
    } on SocketException catch (e, stackTrace) {
      state = state.copyWith(isSyncing: false);
      AppLogger.error('Network error during sync', e);
      return SyncResult.fromError(
        NetworkError.offline(originalError: e, stackTrace: stackTrace),
        syncedCount: syncedCount,
        failedCount: failedCount,
        wasOffline: true,
      );
    } on PostgrestException catch (e, stackTrace) {
      state = state.copyWith(isSyncing: false);
      AppLogger.error('Database error during sync: ${e.message}', e);
      return SyncResult.fromError(
        NetworkError.serverError(
          details: e.message,
          originalError: e,
          stackTrace: stackTrace,
        ),
        syncedCount: syncedCount,
        failedCount: failedCount,
      );
    } catch (e, stackTrace) {
      state = state.copyWith(isSyncing: false);
      AppLogger.error('Sync failed', e);
      return SyncResult.fromError(
        SyncError.failed(
          details: e.toString(),
          originalError: e,
          stackTrace: stackTrace,
        ),
        syncedCount: syncedCount,
        failedCount: failedCount,
      );
    }
  }

  Future<void> addContact(ContactModel contact) async {
    // Security validation - check for SQL injection / XSS
    final nameSecurityError = Validators.validateSecureInput(contact.name, fieldName: 'Name');
    if (nameSecurityError != null) {
      state = state.copyWith(error: nameSecurityError);
      return;
    }

    // Validate and sanitize name
    final sanitizedName = Validators.sanitizeName(contact.name);
    final nameError = Validators.validateName(sanitizedName);
    if (nameError != null) {
      state = state.copyWith(error: nameError);
      return;
    }

    // Validate phone is E.164 format
    final normalizedPhone = Validators.normalizePhone(contact.phone);
    if (!Validators.isValidE164(normalizedPhone)) {
      state = state.copyWith(
          error: 'Invalid phone format. Use +91XXXXXXXXXX');
      return;
    }

    // Validate email if provided
    if (contact.email != null && contact.email!.isNotEmpty) {
      final emailError = Validators.validateEmail(contact.email);
      if (emailError != null) {
        state = state.copyWith(error: emailError);
        return;
      }
    }

    // Sanitize relationship field if provided
    final sanitizedRelationship = contact.relationship != null
        ? Validators.sanitizeForDatabase(contact.relationship!)
        : null;

    final contactWithSanitizedData = contact.copyWith(
      name: sanitizedName,
      phone: normalizedPhone,
      email: contact.email?.trim().toLowerCase(),
      relationship: sanitizedRelationship,
    );

    try {
      // Save to local storage first using cached box with mutex protection
      await _withHiveLock(() async {
        final box = await _box;
        await box.add(contactWithSanitizedData);
      });
      state = state.copyWith(contacts: [...state.contacts, contactWithSanitizedData]);

      // Then sync to Supabase
      await _syncContactToSupabase(contactWithSanitizedData);
    } on HiveError catch (e, stackTrace) {
      AppLogger.error('Hive error adding contact', e);
      final appError = StorageError.writeFailed(
        details: 'Failed to save contact locally',
        originalError: e,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: appError.userMessage);
    } catch (e, stackTrace) {
      AppLogger.error('Error adding contact', e);
      final appError = ErrorHandler.fromException(e, stackTrace);
      state = state.copyWith(error: appError.userMessage);
    }
  }

  Future<void> _syncContactToSupabase(ContactModel contact, {bool isNew = true}) async {
    if (_supabase == null || _currentUserId == null) {
      AppLogger.warning('Cannot sync to Supabase: not logged in');
      return;
    }

    try {
      final data = contact.toSupabase(_currentUserId!);

      if (isNew) {
        // For new contacts, use insert
        await _supabase!.from('emergency_contacts').insert(data);
      } else {
        // For existing contacts, use update
        await _supabase!
            .from('emergency_contacts')
            .update(data)
            .eq('id', contact.id)
            .eq('user_id', _currentUserId!);
      }

      // Mark as synced
      final synced = contact.copyWith(isSynced: true, userId: _currentUserId);
      await _updateLocalContact(synced);
      // Security: Log ID only, never PII
      AppLogger.info('Contact synced to Supabase: ${contact.id}');
    } catch (e) {
      AppLogger.error('Error syncing contact to Supabase', e);
      // Contact remains unsynced, will retry later
    }
  }

  Future<void> _updateLocalContact(ContactModel contact) async {
    final stateIndex = state.contacts.indexWhere((c) => c.id == contact.id);

    if (stateIndex != -1) {
      // Use mutex to protect Hive operation
      await _withHiveLock(() async {
        final box = await _box;
        // Recalculate index inside mutex to prevent race condition
        // Box contents may have changed between finding stateIndex and acquiring lock
        final boxIndex = box.values.toList().indexWhere((c) => c.id == contact.id);

        if (boxIndex >= 0 && boxIndex < box.length) {
          await box.putAt(boxIndex, contact);
        } else {
          // Contact not found in box - add as new entry
          AppLogger.warning('Contact not found in box during update, adding as new');
          await box.add(contact);
        }
      });
      final updatedContacts = [...state.contacts];
      updatedContacts[stateIndex] = contact;
      state = state.copyWith(contacts: updatedContacts);
    }
  }

  Future<void> addContactByFields({
    required String name,
    required String phone,
    String? email,
    String? relationship,
    bool isSosContact = true,
    bool isLocationSharing = false,
    bool isPrimary = false,
  }) async {
    final contact = ContactModel(
      id: _uuid.v4(),
      name: name,
      phone: phone,
      email: email,
      relationship: relationship,
      isSosContact: isSosContact,
      isLocationSharing: isLocationSharing,
      addedAt: DateTime.now(),
      userId: _currentUserId,
      isPrimary: isPrimary,
      isSynced: false,
    );
    await addContact(contact);
  }

  Future<void> removeContact(String id) async {
    await deleteContact(id);
  }

  Future<void> updateContact(ContactModel contact) async {
    try {
      // Validate phone if changed
      final normalizedPhone = Validators.normalizePhone(contact.phone);
      if (!Validators.isValidE164(normalizedPhone)) {
        final validationError = ValidationError.invalidFormat(
          fieldName: 'phone number',
          expected: '+91XXXXXXXXXX',
        );
        state = state.copyWith(error: validationError.userMessage);
        return;
      }

      final contactWithPhone = contact.copyWith(
        phone: normalizedPhone,
        isSynced: false, // Mark for re-sync
      );

      await _updateLocalContact(contactWithPhone);

      // Sync to Supabase (existing contact, not new)
      await _syncContactToSupabase(contactWithPhone, isNew: false);
    } on HiveError catch (e, stackTrace) {
      AppLogger.error('Hive error updating contact', e);
      final appError = StorageError.writeFailed(
        details: 'Failed to update contact locally',
        originalError: e,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: appError.userMessage);
    } catch (e, stackTrace) {
      AppLogger.error('Error updating contact', e);
      final appError = ErrorHandler.fromException(e, stackTrace);
      state = state.copyWith(error: appError.userMessage);
    }
  }

  Future<void> deleteContact(String id) async {
    try {
      // Check if contact exists in state
      final stateIndex = state.contacts.indexWhere((c) => c.id == id);

      if (stateIndex != -1) {
        // Delete from local storage using cached box with mutex
        await _withHiveLock(() async {
          final box = await _box;
          // Recalculate index inside mutex to prevent race condition
          // Box contents may have changed between finding stateIndex and acquiring lock
          final boxIndex = box.values.toList().indexWhere((c) => c.id == id);

          if (boxIndex >= 0 && boxIndex < box.length) {
            await box.deleteAt(boxIndex);
          } else {
            AppLogger.warning('Contact not found in box during delete: $id');
          }
        });

        final updatedContacts =
            state.contacts.where((c) => c.id != id).toList();
        state = state.copyWith(contacts: updatedContacts);

        // Delete from Supabase - track as pending if fails
        final deleted = await _deleteFromSupabase(id);
        if (!deleted) {
          // Add to pending deletes for retry when online
          state = state.copyWith(
            pendingDeletes: [...state.pendingDeletes, id],
          );
        }
      }
    } on HiveError catch (e, stackTrace) {
      AppLogger.error('Hive error deleting contact', e);
      final appError = StorageError.writeFailed(
        details: 'Failed to delete contact locally',
        originalError: e,
        stackTrace: stackTrace,
      );
      state = state.copyWith(error: appError.userMessage);
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting contact', e);
      final appError = ErrorHandler.fromException(e, stackTrace);
      state = state.copyWith(error: appError.userMessage);
    }
  }

  /// Returns true if successfully deleted from Supabase
  Future<bool> _deleteFromSupabase(String id) async {
    if (_supabase == null || _currentUserId == null) {
      AppLogger.warning('Cannot delete from Supabase: not logged in');
      return false;
    }

    try {
      await _supabase!
          .from('emergency_contacts')
          .delete()
          .eq('id', id)
          .eq('user_id', _currentUserId!);
      AppLogger.info('Contact deleted from Supabase: $id');
      return true;
    } catch (e) {
      AppLogger.error('Error deleting from Supabase', e);
      return false;
    }
  }

  /// Retry pending delete operations
  Future<void> retryPendingDeletes() async {
    if (_supabase == null || _currentUserId == null) return;
    if (state.pendingDeletes.isEmpty) return;

    final successfulDeletes = <String>[];

    for (final id in state.pendingDeletes) {
      final deleted = await _deleteFromSupabase(id);
      if (deleted) {
        successfulDeletes.add(id);
      }
    }

    if (successfulDeletes.isNotEmpty) {
      final remainingDeletes = state.pendingDeletes
          .where((id) => !successfulDeletes.contains(id))
          .toList();
      state = state.copyWith(pendingDeletes: remainingDeletes);
      AppLogger.info('Retried ${successfulDeletes.length} pending deletes');
    }
  }

  /// Debounce duration for toggle operations (prevents rapid sync calls)
  static const _toggleDebounce = Duration(milliseconds: 500);

  /// Pending toggle operations (debounced)
  final Map<String, ContactModel> _pendingToggles = {};

  Future<void> toggleSosContact(String id) async {
    final contact = _findContactById(id);
    if (contact == null) {
      AppLogger.warning('toggleSosContact: Contact not found: $id');
      return;
    }
    final updated = contact.copyWith(isSosContact: !contact.isSosContact);
    await _debouncedUpdate(updated);
  }

  Future<void> toggleLocationSharing(String id) async {
    final contact = _findContactById(id);
    if (contact == null) {
      AppLogger.warning('toggleLocationSharing: Contact not found: $id');
      return;
    }
    final updated =
        contact.copyWith(isLocationSharing: !contact.isLocationSharing);
    await _debouncedUpdate(updated);
  }

  /// Debounced update to prevent rapid sync calls on toggle operations
  Future<void> _debouncedUpdate(ContactModel contact) async {
    // Update local state immediately for responsive UI
    await _updateLocalContact(contact.copyWith(isSynced: false));

    // Queue for debounced sync
    _pendingToggles[contact.id] = contact;

    // Cancel existing timer and start new one
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_toggleDebounce, () async {
      // Don't process if disposed (prevents callbacks after disposal)
      if (_disposed) return;

      // Sync all pending toggles
      final toSync = Map<String, ContactModel>.from(_pendingToggles);
      _pendingToggles.clear();

      for (final entry in toSync.entries) {
        // Check disposed again before each sync (long-running operation)
        if (_disposed) return;

        // Verify contact still exists before syncing (may have been deleted)
        final currentContact = _findContactById(entry.key);
        if (currentContact == null) {
          AppLogger.warning('Contact ${entry.key} no longer exists, skipping sync');
          continue;
        }

        await _syncContactToSupabase(currentContact, isNew: false);
      }
    });
  }

  Future<void> setPrimaryContact(String id) async {
    // First, unset all other primary contacts
    for (final contact in state.contacts) {
      if (contact.isPrimary && contact.id != id) {
        final updated = contact.copyWith(isPrimary: false);
        await updateContact(updated);
      }
    }

    // Set the new primary contact
    final contact = _findContactById(id);
    if (contact == null) {
      AppLogger.warning('setPrimaryContact: Contact not found: $id');
      return;
    }
    final updated = contact.copyWith(isPrimary: true);
    await updateContact(updated);
  }

  /// Helper to find contact by ID without throwing (returns null if not found)
  ContactModel? _findContactById(String id) {
    try {
      return state.contacts.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Force refresh from Supabase
  /// Note: syncToSupabase handles pushing local changes, _syncFromSupabase pulls remote changes
  /// These are complementary operations, not duplicates
  Future<void> refresh() async {
    // Check connectivity first to avoid wasted operations
    final online = await _isOnline();
    if (!online) {
      AppLogger.info('Offline - refresh skipped');
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      // Push local changes first (including pending deletes)
      await syncToSupabase();

      // Then pull latest from Supabase (merges remote changes)
      await _syncFromSupabase();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Clear all contacts (called on logout)
  /// Uses mutex to prevent race conditions
  Future<void> clearAll() async {
    try {
      await _withHiveLock(() async {
        final box = await _box;
        await box.clear();
      });

      state = const ContactsState();
      AppLogger.info('All contacts cleared');
    } catch (e) {
      AppLogger.error('Error clearing contacts', e);
    }
  }

  /// Export contacts and share the file
  Future<BackupResult> exportContacts() async {
    return ContactsBackupService.instance.exportAndShare(state.contacts);
  }

  /// Import contacts from a file
  /// Uses mutex to prevent race conditions during batch import
  /// Rate limited to prevent DoS attacks
  Future<ImportResult> importContactsFromFile() async {
    // Rate limiting check (security: prevent DoS via repeated imports)
    if (_lastImportAttempt != null) {
      final timeSinceLastImport = DateTime.now().difference(_lastImportAttempt!);
      if (timeSinceLastImport < _importCooldown) {
        final waitSeconds = (_importCooldown - timeSinceLastImport).inSeconds;
        return ImportResult.fromError(
          BackupError.importFailed(
            details: 'Please wait $waitSeconds seconds before importing again.',
          ),
        );
      }
    }

    _lastImportAttempt = DateTime.now();

    final result = await ContactsBackupService.instance.importFromFile();

    if (result.success && result.contacts.isNotEmpty) {
      // Prepare all new contacts first
      final newContacts = result.contacts.map((contact) => contact.copyWith(
        id: _uuid.v4(), // Generate new ID
        isSynced: false, // Will need to sync
        userId: _currentUserId,
      )).toList();

      // Use mutex for batch Hive operation
      await _withHiveLock(() async {
        final box = await _box;
        for (final newContact in newContacts) {
          await box.add(newContact);
        }
      });

      // Update state with all imported contacts at once (more efficient)
      state = state.copyWith(contacts: [...state.contacts, ...newContacts]);

      AppLogger.info('Imported ${result.contacts.length} contacts');

      // Try to sync imported contacts (uses batch operations)
      await syncToSupabase();
    }

    return result;
  }

  /// Check if device is currently online
  Future<bool> isOnline() => _isOnline();
}
