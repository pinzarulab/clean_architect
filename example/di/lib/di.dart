import 'package:get_it/get_it.dart';

import 'catalog_di.dart';

Future<void> initDi({required GetIt get}) async {
  await initCatalogData(get);
  // clean_architect:data-registrations

  initCatalogDomain(get);
  // clean_architect:domain-registrations
}
