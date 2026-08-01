class Users {
  final String id;
  final String name;
  String? nickName;

  /// Quando o apelido foi trocado pela última vez. `null` = nunca trocou,
  /// ainda é o gerado no primeiro login.
  String? nickNameChangedAt;
  final String? birthDate;
  final String? cpf;
  final String email;
  final String? phone;
  String? photoUrl;
  final String createdAt;
  String? updatedAt;

  Users({
    required this.id,
    required this.name,
    required this.email,
    this.nickName,
    this.nickNameChangedAt,
    this.birthDate,
    this.cpf,
    this.phone,
    this.photoUrl,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'nickName': nickName,
      'nickNameChangedAt': nickNameChangedAt,
      'birthDate': birthDate,
      'cpf': cpf,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory Users.fromMap(Map<String, dynamic> map) {
    return Users(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      nickName: map['nickName'],
      nickNameChangedAt: map['nickNameChangedAt'],
      birthDate: map['birthDate'],
      cpf: map['cpf'],
      email: map['email'] ?? '',
      phone: map['phone'],
      photoUrl: map['photoUrl'],
      createdAt: map['createdAt'] ?? '',
      updatedAt: map['updatedAt'],
    );
  }
}
