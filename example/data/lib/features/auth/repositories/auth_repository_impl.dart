import 'package:domain/features/auth/entities/auth_entity.dart';
import 'package:domain/features/auth/repositories/auth_repository.dart';
import '../mappers/auth_mapper.dart';
import '../local/auth_local_data_source.dart';
import '../remote/auth_remote_data_source.dart';


class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
  })  : _remoteDataSource = remoteDataSource,
        _localDataSource = localDataSource;

  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;

  @override
  Future<List<AuthEntity>> getAuthList() async {
    final items = await _remoteDataSource.getItems();
    await _localDataSource.cacheItems(items);
    return items.map((item) => item.toEntity()).toList(growable: false);
  }
}
