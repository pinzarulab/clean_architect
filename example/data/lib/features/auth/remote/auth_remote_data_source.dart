import 'models/auth_dto.dart';

abstract interface class AuthRemoteDataSource {
  Future<List<AuthDto>> getItems();
}
