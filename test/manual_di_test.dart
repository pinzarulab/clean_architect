import 'dart:io';

import 'package:clean_architect/clean_architect.dart';
import 'package:clean_architect/src/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory previousDirectory;
  late Directory directory;

  setUp(() {
    previousDirectory = Directory.current;
    directory = Directory.systemTemp.createTempSync('clean_architect_di_');
    Directory.current = directory;
    exitCode = 0;
  });

  tearDown(() {
    Directory.current = previousDirectory;
    directory.deleteSync(recursive: true);
    exitCode = 0;
  });

  test('manual DI follows ordered GetIt registration phases', () {
    final files = CleanArchitectGenerator(
      CleanArchitectConfig.defaults(),
    ).auth();
    final bootstrap = files.singleWhere(
      (file) => file.path == p.join('di', 'lib', 'di.dart'),
    );
    final authDi = files.singleWhere(
      (file) => file.path == p.join('di', 'lib', 'auth_di.dart'),
    );

    expect(bootstrap.content, contains('await initAuthData(get);'));
    expect(bootstrap.content, contains('initAuthDomain(get);'));
    expect(
      bootstrap.content.indexOf('initAuthData'),
      lessThan(bootstrap.content.indexOf('initAuthDomain')),
    );
    expect(
      authDi.content,
      contains('final localDataSource = await AuthLocalDataSourceImpl.init()'),
    );
    expect(authDi.content, contains('Dio(BaseOptions(baseUrl: \'\'))'));
    expect(authDi.content, contains('isRegistered<AuthRepository>'));
    expect(authDi.content, contains('isRegistered<LoginUseCase>'));
  });

  test('later features and operations patch manual DI idempotently', () {
    final cli = CleanArchitectCli();
    cli.run(['init']);
    cli.run(['create', 'architecture', '--no-flutter-create']);
    cli.run(['create', 'feature', 'orders', '--no-flutter-create']);
    cli.run(['create', 'auth', '--no-flutter-create']);
    cli.run([
      'create',
      'cached-function',
      'syncCatalog',
      '--feature',
      'orders',
    ]);

    final bootstrap = File(p.join('di', 'lib', 'di.dart')).readAsStringSync();
    final ordersDi = File(
      p.join('di', 'lib', 'orders_di.dart'),
    ).readAsStringSync();

    expect(_occurrences(bootstrap, 'await initOrdersData(get);'), 1);
    expect(_occurrences(bootstrap, 'await initAuthData(get);'), 1);
    expect(_occurrences(bootstrap, 'initOrdersDomain(get);'), 1);
    expect(_occurrences(bootstrap, 'initAuthDomain(get);'), 1);
    expect(ordersDi, contains('isRegistered<SyncCatalogUseCase>'));
    expect(ordersDi, contains('isRegistered<StreamCatalogUseCase>'));
  });

  test('vertical manual architecture patches the app bootstrap', () {
    File(CleanArchitectConfig.fileName).writeAsStringSync('''
clean_architect:
  config_version: 1
  structure: vertical_packages
  dependency_injection: manual
  flutter:
    create_presentation: false
  paths:
    app: app/lib
    core: packages/core/lib
    features: packages/features
''');

    final cli = CleanArchitectCli();
    cli.run(['create', 'architecture', '--no-flutter-create']);
    cli.run(['create', 'feature', 'orders', '--no-flutter-create']);

    final bootstrap = File(
      p.join('app', 'lib', 'di', 'bootstrap.dart'),
    ).readAsStringSync();
    expect(bootstrap, contains("import 'package:orders/orders.dart';"));
    expect(bootstrap, contains('await initOrdersData(get);'));
    expect(bootstrap, contains('initOrdersDomain(get);'));
  });
}

int _occurrences(String content, String value) {
  return value.allMatches(content).length;
}
