import 'dart:io';

import 'package:clean_architect/src/cli.dart';
import 'package:clean_architect/src/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String repositoryRoot;
  late Directory previousDirectory;
  late Directory directory;

  setUp(() {
    repositoryRoot = Directory.current.path;
    previousDirectory = Directory.current;
    directory = Directory.systemTemp.createTempSync(
      'clean_architect_stability_',
    );
    Directory.current = directory;
    exitCode = 0;
  });

  tearDown(() {
    Directory.current = previousDirectory;
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    exitCode = 0;
  });

  test('prints package version and command-specific help', () {
    final version = _runCli(repositoryRoot, ['--version'], directory.path);
    final help = _runCli(repositoryRoot, [
      'create',
      'feature',
      '--help',
    ], directory.path);

    expect(version.exitCode, 0);
    expect(version.stdout, contains('clean_architect 1.3.0'));
    expect(help.exitCode, 0);
    expect(
      help.stdout,
      contains('clean_architect create feature <name> [options]'),
    );
    expect(help.stdout, contains('--skip-presentation'));
  });

  test('malformed YAML is reported without a stack trace', () {
    File(CleanArchitectConfig.fileName).writeAsStringSync('''
clean_architect:
  paths: [
''');

    final result = _runCli(repositoryRoot, [
      'create',
      'architecture',
      '--no-flutter-create',
    ], directory.path);
    final output = '${result.stdout}\n${result.stderr}';

    expect(result.exitCode, 64);
    expect(output, contains('Invalid clean_architect.yaml'));
    expect(output, isNot(contains('Unhandled exception')));
    expect(output, isNot(contains('#0')));
  });

  test('config_version is generated and future versions are rejected', () {
    expect(
      CleanArchitectConfig.defaultYaml(),
      contains('config_version: $currentConfigVersion'),
    );

    final file = File(CleanArchitectConfig.fileName)
      ..writeAsStringSync('''
clean_architect:
  config_version: 999
''');

    expect(
      () => CleanArchitectConfig.fromFile(file),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported config_version 999'),
        ),
      ),
    );
  });

  test('validates names, platforms, paths, and incompatible flags', () {
    final cli = CleanArchitectCli();

    cli.run(['create', 'feature', '../orders', '--no-flutter-create']);
    expect(exitCode, 64);
    expect(Directory('domain').existsSync(), isFalse);

    exitCode = 0;
    cli.run([
      'create',
      'architecture',
      '--platforms=android',
      '--no-flutter-create',
    ]);
    expect(exitCode, 64);
    expect(Directory('presentation').existsSync(), isFalse);

    final invalidPath = File(CleanArchitectConfig.fileName)
      ..writeAsStringSync('''
clean_architect:
  paths:
    domain: ../domain/lib
''');
    expect(
      () => CleanArchitectConfig.fromFile(invalidPath),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('must not contain ".."'),
        ),
      ),
    );

    invalidPath.writeAsStringSync('''
clean_architect:
  paths:
    domain: domain/lib/src
''');
    expect(
      () => CleanArchitectConfig.fromFile(invalidPath),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('reserved lib/src'),
        ),
      ),
    );

    invalidPath.writeAsStringSync('''
clean_architect:
  flutter:
    platforms: [android, fuchsia]
''');
    expect(
      () => CleanArchitectConfig.fromFile(invalidPath),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported Flutter platform'),
        ),
      ),
    );
  });

  test('preflights every conflict before writing any files', () {
    final conflict = File(
      'domain/lib/features/orders/entities/orders_entity.dart',
    );
    conflict.parent.createSync(recursive: true);
    conflict.writeAsStringSync('// user-owned\n');

    CleanArchitectCli().run([
      'create',
      'feature',
      'orders',
      '--no-flutter-create',
    ]);

    expect(exitCode, 73);
    expect(conflict.readAsStringSync(), '// user-owned\n');
    expect(File('data/pubspec.yaml').existsSync(), isFalse);
    expect(
      File(
        'data/lib/features/orders/remote/models/orders_dto.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('rerun can add presentation to a domain-only feature', () {
    final cli = CleanArchitectCli();
    cli.run([
      'create',
      'feature',
      'orders',
      '--skip-presentation',
      '--no-flutter-create',
    ]);
    expect(exitCode, 0);
    expect(
      File('presentation/lib/pages/orders_page.dart').existsSync(),
      isFalse,
    );

    cli.run(['create', 'feature', 'orders', '--no-flutter-create']);

    expect(exitCode, 0);
    expect(
      File('presentation/lib/pages/orders_page.dart').existsSync(),
      isTrue,
    );
  });

  test('operation commands require an existing feature', () {
    CleanArchitectCli().run([
      'create',
      'cached-function',
      'syncCatalog',
      '--feature',
      'orders',
    ]);

    expect(exitCode, 64);
    expect(
      File(
        'domain/lib/features/orders/entities/sync_catalog_entity.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('repeated feature and operation commands are idempotent', () {
    final cli = CleanArchitectCli();
    cli.run(['create', 'feature', 'orders', '--no-flutter-create']);
    expect(exitCode, 0);

    cli.run([
      'create',
      'cached-function',
      'syncCatalog',
      '--feature',
      'orders',
    ]);
    expect(exitCode, 0);

    final before = _snapshot(directory);

    cli.run(['create', 'feature', 'orders', '--no-flutter-create']);
    expect(exitCode, 0);
    cli.run([
      'create',
      'cached-function',
      'syncCatalog',
      '--feature',
      'orders',
    ]);
    expect(exitCode, 0);

    expect(_snapshot(directory), before);
  });
}

ProcessResult _runCli(
  String repositoryRoot,
  List<String> arguments,
  String workingDirectory,
) {
  return Process.runSync(Platform.resolvedExecutable, [
    p.join(repositoryRoot, 'bin', 'clean_architect.dart'),
    ...arguments,
  ], workingDirectory: workingDirectory);
}

Map<String, ({String content, DateTime modified})> _snapshot(
  Directory directory,
) {
  final files = directory.listSync(recursive: true).whereType<File>().toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  return {
    for (final file in files)
      p.relative(file.path, from: directory.path): (
        content: file.readAsStringSync(),
        modified: file.lastModifiedSync(),
      ),
  };
}
