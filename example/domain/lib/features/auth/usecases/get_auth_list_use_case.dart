import '../entities/auth_entity.dart';
import '../repositories/auth_repository.dart';

class GetAuthListUseCase {
  const GetAuthListUseCase(this._repository);

  final AuthRepository _repository;

  Future<List<AuthEntity>> call() {
    return _repository.getAuthList();
  }
}
