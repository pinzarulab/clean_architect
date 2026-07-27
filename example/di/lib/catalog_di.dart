import 'package:data/features/catalog/local/catalog_local_data_source.dart';
import 'package:data/features/catalog/remote/catalog_remote_data_source.dart';
import 'package:data/features/catalog/repositories/catalog_repository_impl.dart';
import 'package:domain/features/catalog/repositories/catalog_repository.dart';
import 'package:domain/features/catalog/usecases/get_catalog_list_use_case.dart';
import 'package:get_it/get_it.dart';

Future<void> initCatalogData(GetIt get) async {
  if (!get.isRegistered<CatalogLocalDataSource>()) {
    final localDataSource = await CatalogLocalDataSourceImpl.init();
    get.registerLazySingleton<CatalogLocalDataSource>(() => localDataSource);
  }

  // Register CatalogRemoteDataSource before resolving the repository.

  if (!get.isRegistered<CatalogRepository>()) {
    get.registerLazySingleton<CatalogRepository>(
      () => CatalogRepositoryImpl(
        remoteDataSource: get<CatalogRemoteDataSource>(),
        localDataSource: get<CatalogLocalDataSource>(),
      ),
    );
  }
}

void initCatalogDomain(GetIt get) {
  if (!get.isRegistered<GetCatalogListUseCase>()) {
    get.registerLazySingleton<GetCatalogListUseCase>(
      () => GetCatalogListUseCase(get<CatalogRepository>()),
    );
  }
  // clean_architect:domain-registrations
}
