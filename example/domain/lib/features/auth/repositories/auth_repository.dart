import '../entities/auth_entity.dart';

abstract interface class AuthRepository {
  Future<List<AuthEntity>> getAuthList();
}
