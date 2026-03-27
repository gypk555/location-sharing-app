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
  final bool isSosContact; // Receives SOS alerts

  @HiveField(6)
  final bool isLocationSharing; // Can see live location

  @HiveField(7)
  final DateTime addedAt;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.relationship,
    this.isSosContact = true,
    this.isLocationSharing = false,
    required this.addedAt,
  });

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
    );
  }
}
