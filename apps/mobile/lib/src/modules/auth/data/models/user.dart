import "dart:convert";

/// App-level user identity — derived from the backend profile + contributor response.
///
/// Fields map to the fpv-auth `GET /api/v1/auth/me` response:
///   { id, email, fullName, avatarUrl, platformRole, contributor }
class User {
  final String id; // profiles.id (UUID)
  final String? email;
  final String? phone;
  final String? name; // profiles.full_name
  final String? avatarUrl;
  final String? platformRole;
  final String? city;
  final String? country;
  final int? age;
  final bool isContributor; // contributor row exists (not null)
  final DateTime? createdAt;

  User({
    required this.id,
    required this.email,
    required this.phone,
    required this.name,
    required this.city,
    required this.country,
    required this.age,
    required this.isContributor,
    this.avatarUrl,
    this.platformRole,
    this.createdAt,
  });

  /// Parses both the backend response shape and the cached JSON shape.
  factory User.fromMap(Map<String, dynamic> map) {
    final bool isContributor;
    if (map.containsKey("contributor")) {
      isContributor = map["contributor"] != null;
    } else {
      isContributor = map["isContributor"] as bool? ?? false;
    }

    return User(
      id: map["id"] as String,
      email: map["email"] as String?,
      phone: map["phone"] as String?,
      name: map["fullName"] as String?,
      avatarUrl: map["avatarUrl"] as String?,
      platformRole: map["platformRole"] as String?,
      city: map["city"] as String?,
      country: map["country"] as String?,
      age: map["age"] as int?,
      isContributor: isContributor,
      createdAt: map["createdAt"] != null
          ? DateTime.parse(map["createdAt"] as String)
          : (map["contributor"] is Map<String, dynamic> &&
                (map["contributor"] as Map<String, dynamic>)["createdAt"] !=
                    null)
          ? DateTime.parse(
              (map["contributor"] as Map<String, dynamic>)["createdAt"]
                  as String,
            )
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "email": email,
      "phone": phone,
      "fullName": name,
      "avatarUrl": avatarUrl,
      "platformRole": platformRole,
      "city": city,
      "country": country,
      "age": age,
      "contributor": isContributor ? <String, dynamic>{} : null,
      if (createdAt != null) "createdAt": createdAt!.toIso8601String(),
    };
  }

  String toJson() => json.encode(toMap());

  factory User.fromJson(String source) => User.fromMap(json.decode(source));

  User copyWith({
    String? name,
    String? avatarUrl,
    String? platformRole,
    String? city,
    String? country,
    int? age,
    bool? isContributor,
  }) {
    return User(
      id: id,
      email: email,
      phone: phone,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      platformRole: platformRole ?? this.platformRole,
      city: city ?? this.city,
      country: country ?? this.country,
      age: age ?? this.age,
      isContributor: isContributor ?? this.isContributor,
      createdAt: createdAt,
    );
  }
}
