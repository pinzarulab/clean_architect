import 'package:data/features/auth/repositories/auth_repository_impl.dart';
import 'package:data/features/auth/local/auth_local_data_source.dart';
import 'package:data/features/auth/remote/auth_remote_data_source.dart';
import 'package:domain/features/auth/repositories/auth_repository.dart';
import 'package:domain/features/auth/usecases/get_auth_list_use_case.dart';

class AuthDependencies {
  const AuthDependencies({
    required this.repository,
    required this.getAuthListUseCase,
  });

  final AuthRepository repository;
  final GetAuthListUseCase getAuthListUseCase;
}

AuthDependencies buildAuthDependencies({
  required AuthRemoteDataSource remoteDataSource,
  required AuthLocalDataSource localDataSource,
}) {
  final repository = AuthRepositoryImpl(
    remoteDataSource: remoteDataSource,
    localDataSource: localDataSource,
  );

  return AuthDependencies(
    repository: repository,
    getAuthListUseCase: GetAuthListUseCase(repository),
  );
}
