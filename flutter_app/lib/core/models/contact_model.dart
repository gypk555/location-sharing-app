import 'package:hive/hive.dart';

part 'contact_model.g.dart';

@HiveType(typeId: 1)
class ContactModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String phone;

  @HiveField(3)
  final String? email;

  @HiveField(4)
  final String? relationship; // 'family', 'friend', 'emergency'

  @HiveField(5)
  final bool isSosContact; // Receives SOS alerts (notify_on_sos in DB)

  @HiveField(6)
  final bool isLocationSharing; // Can see live location (share_location in DB)

  @HiveField(7)
  final DateTime addedAt;

  @HiveField(8)
  final String? userId; // Foreign key to auth.users

  @HiveField(9)
  final bool isPrimary; // Primary emergency contact

  @HiveField(10)
  final bool isSynced; // Whether synced to Supabase

  /// Cached result of find_user_by_phone RPC: the profile.id of this
  /// contact if they are a registered app user. Null means either
  /// "not yet resolved" or "resolved and not registered" — distinguish
  /// using [resolvedAt].
  @HiveField(11)
  final String? resolvedUserId;

  /// When resolvedUserId was last checked. Null means never resolved.
  /// Callers treat this cache as stale after 24 hours.
  @HiveField(12)
  final DateTime? resolvedAt;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.relationship,
    this.isSosContact = true,
    this.isLocationSharing = false,
    required this.addedAt,
    this.userId,
    this.isPrimary = false,
    this.isSynced = false,
    this.resolvedUserId,
    this.resolvedAt,
  });

  /// Whether this contact is a registered app user (based on cached lookup).
  bool get isRegisteredUser => resolvedUserId != null;

  /// Whether the cached [resolvedUserId] should be refreshed.
  bool get resolutionIsStale {
    if (resolvedAt == null) return true;
    return DateTime.now().difference(resolvedAt!) > const Duration(hours: 24);
  }

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      relationship: json['relationship'] as String?,
      isSosContact: json['isSosContact'] as bool? ?? true,
      isLocationSharing: json['isLocationSharing'] as bool? ?? false,
      addedAt: DateTime.parse(json['addedAt'] as String),
      userId: json['userId'] as String?,
      isPrimary: json['isPrimary'] as bool? ?? false,
      isSynced: json['isSynced'] as bool? ?? false,
      resolvedUserId: json['resolvedUserId'] as String?,
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'] as String)
          : null,
    );
  }

  /// Create from Supabase row (different column names)
  factory ContactModel.fromSupabase(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?, // Include email from Supabase
      relationship: json['relationship'] as String?,
      isSosContact: json['notify_on_sos'] as bool? ?? true,
      isLocationSharing: json['share_location'] as bool? ?? false,
      addedAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      userId: json['user_id'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      isSynced: true, // If from Supabase, it's synced
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'relationship': relationship,
      'isSosContact': isSosContact,
      'isLocationSharing': isLocationSharing,
      'addedAt': addedAt.toIso8601String(),
      'userId': userId,
      'isPrimary': isPrimary,
      'isSynced': isSynced,
      'resolvedUserId': resolvedUserId,
      'resolvedAt': resolvedAt?.toIso8601String(),
    };
  }

  /// Convert to Supabase format (different column names)
  Map<String, dynamic> toSupabase(String currentUserId) {
    return {
      'id': id,
      'user_id': currentUserId,
      'name': name,
      'phone': phone,
      'email': email, // Include email to Supabase
      'relationship': relationship,
      'is_primary': isPrimary,
      'notify_on_sos': isSosContact,
      'share_location': isLocationSharing,
    };
  }

  ContactModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? relationship,
    bool? isSosContact,
    bool? isLocationSharing,
    DateTime? addedAt,
    String? userId,
    bool? isPrimary,
    bool? isSynced,
    String? resolvedUserId,
    DateTime? resolvedAt,
    bool clearResolution = false,
  }) {
    return ContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      relationship: relationship ?? this.relationship,
      isSosContact: isSosContact ?? this.isSosContact,
      isLocationSharing: isLocationSharing ?? this.isLocationSharing,
      addedAt: addedAt ?? this.addedAt,
      userId: userId ?? this.userId,
      isPrimary: isPrimary ?? this.isPrimary,
      isSynced: isSynced ?? this.isSynced,
      resolvedUserId:
          clearResolution ? null : (resolvedUserId ?? this.resolvedUserId),
      resolvedAt: clearResolution ? null : (resolvedAt ?? this.resolvedAt),
    );
  }
}
