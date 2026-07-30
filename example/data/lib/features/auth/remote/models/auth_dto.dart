class AuthDto {
  const AuthDto({
    required this.id,
  });

  factory AuthDto.fromJson(Map<String, dynamic> json) {
    return AuthDto(id: json['id'] as String);
  }

  final String id;

  Map<String, dynamic> toJson() {
    return {'id': id};
  }
}
