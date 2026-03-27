import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String? phone;

  @HiveField(2)
  final String? email;

  @HiveField(3)
  final String? name;

  @HiveField(4)
  final String? photoUrl;

  @HiveField(5)
  final String authProvider; // 'phone', 'email', 'google', 'apple'

  @HiveField(6)
  final DateTime createdAt;

  UserModel({
    required this.id,
    this.phone,
    this.email,
    this.name,
    this.photoUrl,
    required this.authProvider,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      name: json['name'] as String?,
      photoUrl: json['photoUrl'] as String?,
      authProvider: json['authProvider'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'name': name,
      'photoUrl': photoUrl,
      'authProvider': authProvider,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? phone,
    String? email,
    String? name,
    String? photoUrl,
    String? authProvider,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      authProvider: authProvider ?? this.authProvider,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
