import 'models/auth_box.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheItems(List<Object> items);
}


class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  const AuthLocalDataSourceImpl();

  static Future<AuthLocalDataSource> init() async {
    return const AuthLocalDataSourceImpl();
  }

  @override
  Future<void> cacheItems(List<Object> items) async {
    final placeholder = const AuthBox();
    // TODO: Cache auth items using your local storage. Remove placeholder when implemented.
    placeholder.id;
  }
}
