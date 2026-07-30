import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _selectionVariable = 'CLEAN_ARCHITECT_INTEGRATION';
const _keepVariable = 'CLEAN_ARCHITECT_KEEP_INTEGRATION_PROJECTS';

void main() {
  final selection = Platform.environment[_selectionVariable] ?? '';

  for (final scenario in _scenarios) {
    final enabled = selection == 'all' || selection == scenario.name;

    test(
      'generated project: ${scenario.name}',
      () => _runScenario(scenario),
      skip: enabled
          ? false
          : 'Set $_selectionVariable=${scenario.name} or all to run.',
      timeout: const Timeout(Duration(minutes: 30)),
    );
  }
}

Future<void> _runScenario(_Scenario scenario) async {
  final repository = Directory.current.absolute;
  final project = await Directory.systemTemp.createTemp(
    'clean_architect_${scenario.name}_',
  );
  var succeeded = false;

  try {
    await File(
      p.join(project.path, 'clean_architect.yaml'),
    ).writeAsString(scenario.yaml);
    final generationCommands = scenario.vertical
        ? <List<String>>[
            ['create', 'architecture', '--flutter-create', '--platforms=web'],
            ..._generationCommands.skip(1),
          ]
        : _generationCommands;

    for (final arguments in generationCommands) {
      await _run(
        Platform.resolvedExecutable,
        [
          '--packages=${p.join(repository.path, '.dart_tool', 'package_config.json')}',
          p.join(repository.path, 'bin', 'clean_architect.dart'),
          ...arguments,
        ],
        workingDirectory: project.path,
        label: 'clean_architect ${arguments.join(' ')}',
      );
    }

    final executable = p.join(repository.path, 'bin', 'clean_architect.dart');
    final packageConfig =
        '--packages=${p.join(repository.path, '.dart_tool', 'package_config.json')}';
    await _run(
      Platform.resolvedExecutable,
      [packageConfig, executable, 'scan', '--json'],
      workingDirectory: project.path,
      label: 'clean_architect scan --json',
    );
    await _run(
      Platform.resolvedExecutable,
      [packageConfig, executable, 'scan', '--write', '--force'],
      workingDirectory: project.path,
      label: 'clean_architect scan --write',
    );
    final afterScanWrite = _sourceSnapshot(project);
    await _run(
      Platform.resolvedExecutable,
      [packageConfig, executable, 'scan', '--write', '--force'],
      workingDirectory: project.path,
      label: 'rerun clean_architect scan --write',
    );
    expect(
      _sourceSnapshot(project),
      afterScanWrite,
      reason: 'scan --write changed files when rerun.',
    );

    final beforeRerun = _sourceSnapshot(project);
    for (final arguments in generationCommands) {
      await _run(
        Platform.resolvedExecutable,
        [
          '--packages=${p.join(repository.path, '.dart_tool', 'package_config.json')}',
          p.join(repository.path, 'bin', 'clean_architect.dart'),
          ...arguments,
        ],
        workingDirectory: project.path,
        label: 'rerun clean_architect command',
      );
    }
    expect(
      _sourceSnapshot(project),
      beforeRerun,
      reason: 'Generation commands changed files when rerun.',
    );

    final packages = _packageDirectories(project, scenario);
    for (final package in packages) {
      final directory = p.join(project.path, package);
      final usesFlutter = _usesFlutter(directory);
      await _run(
        usesFlutter ? 'flutter' : Platform.resolvedExecutable,
        ['pub', 'get'],
        workingDirectory: directory,
        label: '$package: pub get',
      );
    }

    for (final package in packages) {
      final directory = p.join(project.path, package);
      if (!_hasBuildRunner(directory)) continue;
      await _run(
        Platform.resolvedExecutable,
        ['run', 'build_runner', 'build'],
        workingDirectory: directory,
        label: '$package: build_runner',
      );
    }

    for (final package in packages) {
      final directory = p.join(project.path, package);
      final usesFlutter = _usesFlutter(directory);
      await _run(
        usesFlutter ? 'flutter' : Platform.resolvedExecutable,
        ['analyze'],
        workingDirectory: directory,
        label: '$package: analyze',
      );
    }

    if (scenario.vertical) {
      final appDirectory = p.join(project.path, 'app');
      await _run(
        'flutter',
        const ['test'],
        workingDirectory: appDirectory,
        label: 'app: flutter test',
      );
      await _run(
        'flutter',
        const ['build', 'web'],
        workingDirectory: appDirectory,
        label: 'app: flutter build web',
      );
    }

    await _run(
      Platform.resolvedExecutable,
      [
        '--packages=${p.join(repository.path, '.dart_tool', 'package_config.json')}',
        p.join(repository.path, 'bin', 'clean_architect.dart'),
        'doctor',
      ],
      workingDirectory: project.path,
      label: 'clean_architect doctor',
    );

    succeeded = true;
  } finally {
    final keep = Platform.environment[_keepVariable] == 'true';
    if (succeeded && !keep) {
      await project.delete(recursive: true);
    } else {
      stdout.writeln('Integration project kept at ${project.path}');
    }
  }
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String label,
}) async {
  stdout.writeln('[$label]');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: const {'CI': 'true'},
    includeParentEnvironment: true,
  );
  final stdoutResult = process.stdout.transform(systemEncoding.decoder).join();
  final stderrResult = process.stderr.transform(systemEncoding.decoder).join();

  late final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(minutes: 10));
  } on TimeoutException {
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }

    final capturedStdout = await stdoutResult;
    final capturedStderr = await stderrResult;
    fail('''
$label timed out after 10 minutes.
Working directory: $workingDirectory
Command: $executable ${arguments.join(' ')}

stdout:
$capturedStdout

stderr:
$capturedStderr
''');
  }

  final capturedStdout = await stdoutResult;
  final capturedStderr = await stderrResult;

  if (exitCode == 0) return;

  fail('''
$label failed with exit code $exitCode.
Working directory: $workingDirectory
Command: $executable ${arguments.join(' ')}

stdout:
$capturedStdout

stderr:
$capturedStderr
''');
}

Map<String, ({String content, int modified})> _sourceSnapshot(
  Directory project,
) {
  final files = project.listSync(recursive: true).whereType<File>().toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  return {
    for (final file in files)
      p.relative(file.path, from: project.path): (
        content: base64Encode(file.readAsBytesSync()),
        modified: file.lastModifiedSync().microsecondsSinceEpoch,
      ),
  };
}

bool _usesFlutter(String packageDirectory) {
  final pubspec = File(
    p.join(packageDirectory, 'pubspec.yaml'),
  ).readAsStringSync();
  return pubspec.contains('sdk: flutter');
}

bool _hasBuildRunner(String packageDirectory) {
  final pubspec = File(
    p.join(packageDirectory, 'pubspec.yaml'),
  ).readAsStringSync();
  return pubspec.contains('build_runner:');
}

List<String> _packageDirectories(Directory project, _Scenario scenario) {
  if (!scenario.vertical) return _packages;

  final packages = <String>['app', p.join('packages', 'core')];
  final features = Directory(p.join(project.path, 'packages', 'features'));
  final featurePackages =
      features
          .listSync()
          .whereType<Directory>()
          .where(
            (directory) =>
                File(p.join(directory.path, 'pubspec.yaml')).existsSync(),
          )
          .map((directory) => p.relative(directory.path, from: project.path))
          .toList(growable: false)
        ..sort();
  packages.addAll(featurePackages);
  return packages;
}

const _packages = ['domain', 'data', 'di', 'presentation'];

const _generationCommands = <List<String>>[
  ['create', 'architecture', '--no-flutter-create'],
  ['create', 'auth', '--no-flutter-create'],
  ['create', 'feature', 'orders', '--no-flutter-create'],
  ['create', 'usecase', 'refreshSession', '--feature', 'orders'],
  ['create', 'repository', 'billing'],
  ['create', 'remote-function', 'fetchReceipt', '--feature', 'orders'],
  ['create', 'local-function', 'readDraft', '--feature', 'orders'],
  ['create', 'cached-function', 'syncCatalog', '--feature', 'orders'],
];

class _Scenario {
  const _Scenario({
    required this.name,
    required this.yaml,
    this.vertical = false,
  });

  final String name;
  final String yaml;
  final bool vertical;
}

const _scenarios = <_Scenario>[
  _Scenario(
    name: 'default_getx_manual_dio_secure',
    yaml: '''
clean_architect:
  structure: layered_packages
  state_management: getx
  network: dio
  local_storage: secure_storage
  dependency_injection: manual
  use_asset_generator: true
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'bloc_injectable_hive_feature_first',
    yaml: '''
clean_architect:
  structure: feature_first
  state_management: bloc
  network: dio
  local_storage: hive
  dependency_injection: injectable
  use_asset_generator: false
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'provider_injectable_objectbox',
    yaml: '''
clean_architect:
  structure: layered_packages
  data_layout: type_first
  state_management: provider
  network: dio
  local_storage: objectbox
  dependency_injection: injectable
  use_asset_generator: false
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'getx_manual_objectbox',
    yaml: '''
clean_architect:
  structure: layered_packages
  data_layout: type_first
  state_management: getx
  network: dio
  local_storage: objectbox
  dependency_injection: manual
  use_asset_generator: false
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'none_abstract_plain_feature_first',
    yaml: '''
clean_architect:
  structure: feature_first
  state_management: none
  network: abstract
  local_storage: abstract
  dependency_injection: manual
  use_asset_generator: false
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: false
    use_json_serializable: false
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'either_enabled',
    yaml: '''
clean_architect:
  structure: layered_packages
  state_management: getx
  network: dio
  local_storage: secure_storage
  dependency_injection: manual
  use_asset_generator: false
  use_either_failure: true
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'shared_preferences_json_only_custom_paths',
    yaml: '''
clean_architect:
  structure: layered_packages
  state_management: getx
  network: abstract
  local_storage: shared_preferences
  dependency_injection: manual
  use_asset_generator: false
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [web, linux]
  models:
    use_freezed: false
    use_json_serializable: true
  paths:
    domain: domain/lib/modules
    data: data/lib/modules
    presentation: presentation/lib/app
    di: di/lib/modules
''',
  ),
  _Scenario(
    name: 'freezed_without_json',
    yaml: '''
clean_architect:
  structure: feature_first
  state_management: none
  network: abstract
  local_storage: secure_storage
  dependency_injection: injectable
  use_asset_generator: false
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms: [macos, windows]
  models:
    use_freezed: true
    use_json_serializable: false
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
''',
  ),
  _Scenario(
    name: 'vertical_bloc_injectable_hive_either',
    vertical: true,
    yaml: '''
clean_architect:
  structure: vertical_packages
  data_layout: type_first
  state_management: bloc
  network: dio
  local_storage: hive
  dependency_injection: injectable
  use_asset_generator: false
  use_either_failure: true
  flutter:
    create_presentation: false
    platforms: [android, ios]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    app: app/lib
    core: packages/core/lib
    features: packages/features
''',
  ),
];
