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
    directory = Directory.systemTemp.createTempSync('clean_architect_scan_');
    Directory.current = directory;
    exitCode = 0;
  });

  tearDown(() {
    Directory.current = previousDirectory;
    directory.deleteSync(recursive: true);
    exitCode = 0;
  });

  test('detects layered package paths and supported options', () {
    final defaults = CleanArchitectConfig.defaults();
    final config = CleanArchitectConfig(
      structure: ProjectStructure.layeredPackages,
      dataLayout: DataLayout.typeFirst,
      stateManagement: StateManagement.bloc,
      network: NetworkClient.dio,
      localStorage: LocalStorage.objectbox,
      dependencyInjection: DependencyInjection.injectable,
      models: const ModelConfig(useFreezed: true, useJsonSerializable: true),
      paths: defaults.paths,
      useAssetGenerator: false,
      useEitherFailure: true,
      flutter: const FlutterConfig(createPresentation: false, platforms: []),
    );
    _writeGenerated(CleanArchitectGenerator(config).feature('orders'));

    final result = ProjectScanner().scan();

    expect(result.canWrite, isTrue);
    expect(result.requiresForce, isFalse);
    expect(result.config?.structure, ProjectStructure.layeredPackages);
    expect(result.config?.dataLayout, DataLayout.typeFirst);
    expect(result.config?.stateManagement, StateManagement.bloc);
    expect(result.config?.localStorage, LocalStorage.objectbox);
    expect(result.config?.dependencyInjection, DependencyInjection.injectable);
    expect(result.config?.useEitherFailure, isTrue);
    expect(result.config?.paths.domain, 'domain/lib');
    expect(result.config?.paths.data, 'data/lib/features');
    expect(result.config?.paths.presentation, 'presentation/lib');
    expect(result.config?.paths.di, 'di/lib');
  });

  test('detects feature-first presentation and DI roots', () {
    final defaults = CleanArchitectConfig.defaults();
    final config = CleanArchitectConfig(
      structure: ProjectStructure.featureFirst,
      stateManagement: defaults.stateManagement,
      network: defaults.network,
      localStorage: defaults.localStorage,
      dependencyInjection: defaults.dependencyInjection,
      models: defaults.models,
      paths: defaults.paths,
      useAssetGenerator: defaults.useAssetGenerator,
      useEitherFailure: defaults.useEitherFailure,
      flutter: defaults.flutter,
    );
    _writeGenerated(CleanArchitectGenerator(config).feature('orders'));

    final result = ProjectScanner().scan();

    expect(result.config?.structure, ProjectStructure.featureFirst);
    expect(result.config?.paths.presentation, 'presentation/lib');
    expect(result.config?.paths.di, 'di/lib');
  });

  test('detects custom public layer paths', () {
    final defaults = CleanArchitectConfig.defaults();
    final config = CleanArchitectConfig(
      structure: ProjectStructure.layeredPackages,
      stateManagement: defaults.stateManagement,
      network: defaults.network,
      localStorage: defaults.localStorage,
      dependencyInjection: DependencyInjection.manual,
      models: defaults.models,
      paths: const PathConfig(
        domain: 'packages/business_domain/lib/modules',
        data: 'packages/persistence/lib/modules',
        presentation: 'apps/mobile/lib/app',
        di: 'packages/injection/lib/modules',
      ),
      useAssetGenerator: false,
      useEitherFailure: false,
      flutter: const FlutterConfig(createPresentation: false, platforms: []),
    );
    _writeGenerated(CleanArchitectGenerator(config).feature('orders'));

    final result = ProjectScanner().scan();

    expect(result.canWrite, isTrue);
    expect(result.requiresForce, isTrue);
    expect(result.config?.paths.domain, 'packages/business_domain/lib/modules');
    expect(result.config?.paths.data, 'packages/persistence/lib/modules');
    expect(result.config?.paths.presentation, 'apps/mobile/lib/app');
    expect(result.config?.paths.di, 'packages/injection/lib/modules');

    CleanArchitectCli().run(['scan', '--write']);
    expect(exitCode, 1);
    expect(File(CleanArchitectConfig.fileName).existsSync(), isFalse);

    exitCode = 0;
    CleanArchitectCli().run(['scan', '--write', '--force']);
    expect(exitCode, 0);
    final written = CleanArchitectConfig.fromFile(
      File(CleanArchitectConfig.fileName),
    );
    expect(written.paths.presentation, 'apps/mobile/lib/app');
    expect(written.paths.di, 'packages/injection/lib/modules');
  });

  test('detects vertical app, core, and features roots', () {
    final defaults = CleanArchitectConfig.defaults();
    final config = CleanArchitectConfig(
      structure: ProjectStructure.verticalPackages,
      dataLayout: DataLayout.typeFirst,
      stateManagement: StateManagement.provider,
      network: NetworkClient.dio,
      localStorage: LocalStorage.hive,
      dependencyInjection: DependencyInjection.injectable,
      models: defaults.models,
      paths: defaults.paths,
      useAssetGenerator: false,
      useEitherFailure: true,
      flutter: const FlutterConfig(createPresentation: false, platforms: []),
    );
    _writeGenerated(CleanArchitectGenerator(config).feature('orders'));

    final result = ProjectScanner().scan();

    expect(result.config?.structure, ProjectStructure.verticalPackages);
    expect(result.config?.paths.app, 'app/lib');
    expect(result.config?.paths.core, 'packages/core/lib');
    expect(result.config?.paths.features, 'packages/features');
    expect(result.config?.dataLayout, DataLayout.typeFirst);
    expect(result.config?.stateManagement, StateManagement.provider);
  });

  test('scan is read-only until write is requested', () {
    _writeGenerated(
      CleanArchitectGenerator(
        CleanArchitectConfig.defaults(),
      ).feature('orders'),
    );

    CleanArchitectCli().run(['scan']);

    expect(exitCode, 0);
    expect(File(CleanArchitectConfig.fileName).existsSync(), isFalse);

    CleanArchitectCli().run(['scan', '--write']);
    expect(exitCode, 0);
    expect(File(CleanArchitectConfig.fileName).existsSync(), isTrue);
    expect(
      CleanArchitectConfig.fromFile(
        File(CleanArchitectConfig.fileName),
      ).paths.data,
      'data/lib/features',
    );
  });

  test('write preserves comments and unknown configuration keys', () {
    _writeGenerated(
      CleanArchitectGenerator(
        CleanArchitectConfig.defaults(),
      ).feature('orders'),
    );
    final file = File(CleanArchitectConfig.fileName)
      ..writeAsStringSync('''
# project configuration
clean_architect:
  structure: feature_first # scanner should update this
  custom_option: keep_me
  flutter:
    create_presentation: true # user intent must be preserved
  paths:
    domain: old_domain/lib
    data: old_data/lib
    presentation: old_presentation/lib
    di: old_di/lib
''');

    CleanArchitectCli().run(['scan', '--write']);

    final content = file.readAsStringSync();
    expect(exitCode, 0);
    expect(content, contains('# project configuration'));
    expect(content, contains('custom_option: keep_me'));
    expect(content, contains('create_presentation: true'));
    expect(content, contains('structure: layered_packages'));
    expect(content, contains('domain: domain/lib'));
    expect(content, contains('data: data/lib/features'));
  });

  test('incomplete projects are reported and never written', () {
    File('pubspec.yaml').writeAsStringSync('name: incomplete\n');

    CleanArchitectCli().run(['scan', '--write', '--force']);

    expect(exitCode, 1);
    expect(File(CleanArchitectConfig.fileName).existsSync(), isFalse);
  });
}

void _writeGenerated(List<GeneratedFile> files) {
  for (final generated in files) {
    final file = File(p.normalize(generated.path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(generated.content);
  }
}
