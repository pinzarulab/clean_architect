import 'dart:convert';
import 'dart:io';

import 'package:clean_architect/src/config.dart';
import 'package:clean_architect/src/generator.dart';
import 'package:clean_architect/src/project_doctor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late CleanArchitectConfig config;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('clean_architect_doctor_');
    config = CleanArchitectConfig.defaults();
    _writeGeneratedArchitecture(directory, config);
    _writeBuildRunnerPackageConfigs(directory);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    exitCode = 0;
  });

  test('passes a valid generated project', () {
    final report = _doctor(directory, config).run();

    expect(report.hasErrors, isFalse, reason: _errors(report).join('\n'));
    expect(
      report.diagnostics.map((item) => item.message),
      contains('Project validation passed.'),
    );
  });

  test('reports missing and incompatible dependencies', () {
    final pubspec = File(p.join(directory.path, 'data', 'pubspec.yaml'));
    final content = pubspec
        .readAsStringSync()
        .replaceFirst('  dio: ^5.10.0\n', '')
        .replaceFirst('  retrofit: ^4.9.2', '  retrofit: ^3.0.0');
    pubspec.writeAsStringSync(content);

    final report = _doctor(directory, config).run();
    final errors = _errors(report);

    expect(report.hasErrors, isTrue);
    expect(errors, contains(contains('missing dependencies dependency "dio"')));
    expect(errors, contains(contains('retrofit')));
    expect(errors, contains(contains('incompatible')));
  });

  test('reports unavailable tools and unresolved build_runner', () {
    Directory(
      p.join(directory.path, 'domain', '.dart_tool'),
    ).deleteSync(recursive: true);

    final doctor = ProjectDoctor(
      config: config,
      projectRoot: directory.path,
      dartVersion: 'not-a-version',
      commandRunner: (executable, arguments) {
        throw ProcessException(executable, arguments);
      },
    );
    final errors = _errors(doctor.run());

    expect(errors, contains(contains('Unable to determine the Dart SDK')));
    expect(errors, contains(contains('flutter executable was not found')));
    expect(errors, contains(contains('build_runner is unavailable in domain')));
  });

  test('reports missing generated g.dart files', () {
    final source = File(
      p.join(directory.path, 'data', 'lib', 'features', 'sample.dart'),
    );
    source.parent.createSync(recursive: true);
    source.writeAsStringSync("part 'sample.g.dart';\n");

    final report = _doctor(directory, config).run();

    expect(_errors(report), contains(contains('Generated file is missing:')));
    expect(_errors(report), contains(contains('sample.g.dart')));
  });

  test('resolves generated files imported from another package', () {
    final generated = File(
      p.join(directory.path, 'data', 'lib', 'objectbox.g.dart'),
    )..writeAsStringSync('// generated\n');
    final source = File(p.join(directory.path, 'di', 'lib', 'feature_di.dart'));
    source.parent.createSync(recursive: true);
    source.writeAsStringSync("import 'package:data/objectbox.g.dart';\n");

    final report = _doctor(directory, config).run();

    expect(generated.existsSync(), isTrue);
    expect(report.hasErrors, isFalse, reason: _errors(report).join('\n'));
  });

  test('reports invalid configured package roots', () {
    final pubspec = File(p.join(directory.path, 'domain', 'pubspec.yaml'));
    pubspec.writeAsStringSync(
      pubspec.readAsStringSync().replaceFirst('name: domain', 'name: wrong'),
    );

    final report = _doctor(directory, config).run();

    expect(
      _errors(report),
      contains(contains('must match package root "domain"')),
    );
  });

  test('doctor CLI returns a nonzero exit code when validation fails', () {
    final repositoryRoot = Directory.current.path;
    File(
      p.join(directory.path, CleanArchitectConfig.fileName),
    ).writeAsStringSync(CleanArchitectConfig.defaultYaml());
    Directory(
      p.join(directory.path, 'data', '.dart_tool'),
    ).deleteSync(recursive: true);

    // The unresolved build_runner check fails before tool availability can
    // produce a false success.
    final result = Process.runSync(Platform.resolvedExecutable, [
      p.join(repositoryRoot, 'bin', 'clean_architect.dart'),
      'doctor',
    ], workingDirectory: directory.path);

    expect(result.exitCode, 1);
  });
}

ProjectDoctor _doctor(Directory directory, CleanArchitectConfig config) {
  return ProjectDoctor(
    config: config,
    projectRoot: directory.path,
    dartVersion: '3.11.0',
    commandRunner: (executable, arguments) =>
        ProcessResult(1, 0, jsonEncode({'frameworkVersion': '3.38.0'}), ''),
  );
}

void _writeGeneratedArchitecture(
  Directory directory,
  CleanArchitectConfig config,
) {
  for (final generated in CleanArchitectGenerator(config).architecture()) {
    final file = File(p.join(directory.path, generated.path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      generated.content.endsWith('\n')
          ? generated.content
          : '${generated.content}\n',
    );
  }
}

void _writeBuildRunnerPackageConfigs(Directory directory) {
  for (final package in ['domain', 'data', 'presentation']) {
    final file = File(
      p.join(directory.path, package, '.dart_tool', 'package_config.json'),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'build_runner',
            'rootUri': 'file:///build_runner',
            'packageUri': 'lib/',
            'languageVersion': '3.0',
          },
        ],
      }),
    );
  }
}

List<String> _errors(DoctorReport report) {
  return report.diagnostics
      .where((item) => item.level == DoctorLevel.error)
      .map((item) => item.message)
      .toList(growable: false);
}
