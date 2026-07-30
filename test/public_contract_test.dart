import 'dart:io';

import 'package:clean_architect/clean_architect.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the 1.0 public Dart API remains available', () {
    const generatedFile = GeneratedFile(path: 'sample.dart', content: 'sample');
    const featurePaths = FeaturePaths(
      domain: 'domain',
      data: 'data',
      presentation: 'presentation',
      di: 'di',
    );
    const diagnostic = DoctorDiagnostic(DoctorLevel.success, 'healthy');
    const report = DoctorReport([diagnostic]);

    expect(packageVersion, '1.4.0');
    expect(generatedFile.path, 'sample.dart');
    expect(featurePaths.domain, 'domain');
    expect(report.hasErrors, isFalse);
    expect(OperationKind.values.map((value) => value.name), [
      'remote',
      'local',
      'cached',
    ]);

    final List<GeneratedFile> generated = CleanArchitectGenerator(
      CleanArchitectConfig.defaults(),
    ).operation('loadDetails', feature: 'orders', kind: OperationKind.remote);
    expect(generated, isNotEmpty);
  });

  test('configuration keys and accepted values are frozen', () {
    final root =
        (loadYaml(CleanArchitectConfig.defaultYaml())
                as YamlMap)['clean_architect']
            as YamlMap;

    expect(root.keys, [
      'config_version',
      'structure',
      'data_layout',
      'state_management',
      'network',
      'local_storage',
      'dependency_injection',
      'use_asset_generator',
      'use_either_failure',
      'flutter',
      'models',
      'paths',
    ]);
    expect((root['flutter'] as YamlMap).keys, [
      'create_presentation',
      'platforms',
    ]);
    expect((root['models'] as YamlMap).keys, [
      'use_freezed',
      'use_json_serializable',
    ]);
    expect((root['paths'] as YamlMap).keys, [
      'domain',
      'data',
      'presentation',
      'di',
      'app',
      'core',
      'features',
    ]);

    expect(ProjectStructure.values.map((value) => value.name), [
      'featureFirst',
      'layeredPackages',
      'verticalPackages',
    ]);
    expect(DataLayout.values.map((value) => value.name), [
      'sourceFirst',
      'typeFirst',
    ]);
    expect(StateManagement.values.map((value) => value.name), [
      'getx',
      'bloc',
      'provider',
      'none',
    ]);
    expect(NetworkClient.values.map((value) => value.name), [
      'dio',
      'abstract',
    ]);
    expect(LocalStorage.values.map((value) => value.name), [
      'secureStorage',
      'sharedPreferences',
      'hive',
      'objectbox',
      'abstract',
    ]);
    expect(DependencyInjection.values.map((value) => value.name), [
      'manual',
      'injectable',
    ]);
  });

  test('default and feature-first paths are frozen', () {
    final defaults = CleanArchitectConfig.defaults();
    expect(defaults.dataLayout, DataLayout.sourceFirst);
    expect(defaults.paths.domain, 'domain/lib');
    expect(defaults.paths.data, 'data/lib/features');
    expect(defaults.paths.presentation, 'presentation/lib');
    expect(defaults.paths.di, 'di/lib');
    expect(defaults.paths.app, 'app/lib');
    expect(defaults.paths.core, 'packages/core/lib');
    expect(defaults.paths.features, 'packages/features');

    final layered = PathResolver(defaults).resolve('user_profile');
    expect(layered.domain, p.join('domain', 'lib', 'features', 'user_profile'));
    expect(layered.data, p.join('data', 'lib', 'features', 'user_profile'));
    expect(layered.presentation, p.join('presentation', 'lib'));
    expect(layered.di, p.join('di', 'lib'));

    final featureFirst = PathResolver(
      CleanArchitectConfig(
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
      ),
    ).resolve('user_profile');
    expect(
      featureFirst.presentation,
      p.join('presentation', 'lib', 'features', 'user_profile'),
    );
    expect(featureFirst.di, p.join('di', 'lib', 'features', 'user_profile'));
  });

  test('canonical commands and compatibility aliases remain accepted', () {
    final root = Directory.current.path;
    final invocations = <List<String>>[
      ['--help'],
      ['init', '--help'],
      ['doctor', '--help'],
      ['scan', '--help'],
      ['create', 'architecture', '--help'],
      ['create', 'base', '--help'],
      ['create', 'auth', '--help'],
      ['create', 'feature', '--help'],
      ['create', 'usecase', '--help'],
      ['create', 'repository', '--help'],
      ['create', 'remote-function', '--help'],
      ['create', 'remote-method', '--help'],
      ['create', 'local-function', '--help'],
      ['create', 'local-method', '--help'],
      ['create', 'cached-function', '--help'],
      ['create', 'cached-method', '--help'],
    ];

    for (final arguments in invocations) {
      final result = Process.runSync(Platform.resolvedExecutable, [
        p.join(root, 'bin', 'clean_architect.dart'),
        ...arguments,
      ], workingDirectory: root);
      expect(
        result.exitCode,
        0,
        reason: 'Command failed: clean_architect ${arguments.join(' ')}',
      );
      expect(result.stdout, isNotEmpty);
    }
  });
}
