import 'package:domain/features/auth/entities/auth_entity.dart';
import '../local/models/auth_box.dart';
import '../remote/models/auth_dto.dart';

extension AuthDtoMapper on AuthDto {
  AuthEntity toEntity() {
    return AuthEntity(remoteId: id);
  }

  AuthBox toBox() {
    return AuthBox(remoteId: id);
  }
}

extension AuthBoxMapper on AuthBox {
  AuthEntity toEntity() {
    return AuthEntity(remoteId: remoteId);
  }
}
