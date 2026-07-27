import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'config.dart';
import 'generated_file.dart';
import 'generator.dart';

enum DoctorLevel { success, warning, error }

class DoctorDiagnostic {
  const DoctorDiagnostic(this.level, this.message);

  final DoctorLevel level;
  final String message;
}

class DoctorReport {
  const DoctorReport(this.diagnostics);

  final List<DoctorDiagnostic> diagnostics;

  bool get hasErrors =>
      diagnostics.any((diagnostic) => diagnostic.level == DoctorLevel.error);
}

typedef DoctorCommandRunner =
    ProcessResult Function(String executable, List<String> arguments);

class ProjectDoctor {
  ProjectDoctor({
    required this.config,
    String? projectRoot,
    DoctorCommandRunner? commandRunner,
    String? dartVersion,
  }) : projectRoot = p.normalize(projectRoot ?? Directory.current.path),
       _commandRunner = commandRunner ?? _runCommand,
       _dartVersion = dartVersion ?? Platform.version.split(' ').first;

  final CleanArchitectConfig config;
  final String projectRoot;
  final DoctorCommandRunner _commandRunner;
  final String _dartVersion;
  final List<DoctorDiagnostic> _diagnostics = [];

  DoctorReport run() {
    _diagnostics.clear();
    final layers = _layers();

    _checkDart();
    _checkNestedRoots(layers);

    final pubspecs = <String, _Pubspec>{};
    for (final layer in layers) {
      final pubspec = _readPubspec(layer);
      if (pubspec != null) pubspecs[layer.label] = pubspec;
    }

    final packageRoots = <String, String>{
      for (final entry in pubspecs.entries)
        if (entry.value.name != null) entry.value.name!: entry.value.layer.root,
    };

    for (final entry in pubspecs.entries) {
      final expected = _expectedPubspec(entry.value.layer);
      if (expected == null) continue;
      _checkEnvironment(entry.value, expected);
      _checkDependencies(entry.value, expected, packageRoots);
      _checkBuildRunner(entry.value, expected);
    }

    _checkFlutter(pubspecs.values);
    _checkGeneratedParts(layers, packageRoots);

    if (!_diagnostics.any((item) => item.level == DoctorLevel.error)) {
      _success('Project validation passed.');
    }
    return DoctorReport(List.unmodifiable(_diagnostics));
  }

  List<_Layer> _layers() {
    if (config.structure == ProjectStructure.verticalPackages) {
      final layers = <_Layer>[
        _layer('app', config.paths.app),
        _layer('core', config.paths.core),
      ];
      final featuresRoot = Directory(
        p.join(projectRoot, config.paths.features),
      );
      if (!featuresRoot.existsSync()) {
        _error('Features package root does not exist: ${featuresRoot.path}.');
        return layers;
      }

      final featureDirectories =
          featuresRoot
              .listSync()
              .whereType<Directory>()
              .where(
                (directory) =>
                    File(p.join(directory.path, 'pubspec.yaml')).existsSync(),
              )
              .toList(growable: false)
            ..sort((left, right) => left.path.compareTo(right.path));
      if (featureDirectories.isEmpty) {
        _error('No feature packages were found in ${featuresRoot.path}.');
      }
      for (final directory in featureDirectories) {
        final relativeRoot = p.relative(directory.path, from: projectRoot);
        layers.add(
          _layer(
            'feature:${p.basename(directory.path)}',
            p.join(relativeRoot, 'lib'),
          ),
        );
      }
      return layers;
    }

    return [
      _layer('domain', config.paths.domain),
      _layer('data', config.paths.data),
      _layer('presentation', config.paths.presentation),
      _layer('di', config.paths.di),
    ];
  }

  _Layer _layer(String label, String configuredPath) {
    final parts = p.split(p.normalize(configuredPath));
    final libIndex = parts.indexOf('lib');
    final relativeRoot = p.joinAll(parts.take(libIndex));
    return _Layer(
      label: label,
      configuredPath: p.join(projectRoot, configuredPath),
      relativeRoot: relativeRoot,
      root: p.normalize(p.join(projectRoot, relativeRoot)),
    );
  }

  void _checkDart() {
    try {
      final version = Version.parse(_dartVersion);
      _success('Dart $version is available.');
    } on FormatException {
      _error('Unable to determine the Dart SDK version: $_dartVersion.');
    }
  }

  void _checkNestedRoots(List<_Layer> layers) {
    for (var left = 0; left < layers.length; left++) {
      for (var right = left + 1; right < layers.length; right++) {
        final first = layers[left];
        final second = layers[right];
        if (p.isWithin(first.root, second.root) ||
            p.isWithin(second.root, first.root)) {
          _error(
            'Configured package roots ${first.label} and ${second.label} '
            'must not be nested.',
          );
        }
      }
    }
  }

  _Pubspec? _readPubspec(_Layer layer) {
    final root = Directory(layer.root);
    if (!root.existsSync()) {
      _error('${layer.label} package root does not exist: ${layer.root}.');
      return null;
    }

    final expectedLib = p.join(layer.root, 'lib');
    if (p.normalize(layer.configuredPath) != p.normalize(expectedLib) &&
        !p.isWithin(expectedLib, layer.configuredPath)) {
      _error(
        '${layer.label} path is outside its package lib directory: '
        '${layer.configuredPath}.',
      );
      return null;
    }
    if (!Directory(layer.configuredPath).existsSync()) {
      _error(
        '${layer.label} configured path does not exist: '
        '${layer.configuredPath}.',
      );
    }

    final file = File(p.join(layer.root, 'pubspec.yaml'));
    if (!file.existsSync()) {
      _error('${layer.label} pubspec.yaml is missing at ${file.path}.');
      return null;
    }

    final YamlMap document;
    try {
      final value = loadYaml(file.readAsStringSync());
      if (value is! YamlMap) {
        _error('${layer.label} pubspec.yaml must contain a map.');
        return null;
      }
      document = value;
    } on FormatException catch (error) {
      _error('${layer.label} pubspec.yaml is invalid: ${error.message}');
      return null;
    }

    final name = document['name'];
    if (name is! String || name.trim().isEmpty) {
      _error('${layer.label} pubspec.yaml has no valid package name.');
    } else if (name != p.basename(layer.root)) {
      _error(
        '${layer.label} package name "$name" must match package root '
        '"${p.basename(layer.root)}".',
      );
    }

    _success('${layer.label} pubspec.yaml loaded.');
    return _Pubspec(
      layer: layer,
      document: document,
      name: name is String ? name : null,
    );
  }

  YamlMap? _expectedPubspec(_Layer layer) {
    final generator = CleanArchitectGenerator(config);
    final files = config.structure == ProjectStructure.verticalPackages
        ? _verticalExpectedFiles(generator, layer)
        : generator.architecture();
    final expectedPath = p.normalize(
      p.join(layer.relativeRoot, 'pubspec.yaml'),
    );
    final generated = files.where(
      (file) => p.normalize(file.path) == expectedPath,
    );
    if (generated.isEmpty) {
      _error('No expected pubspec template found for ${layer.label}.');
      return null;
    }
    final value = loadYaml(generated.single.content);
    return value is YamlMap ? value : null;
  }

  List<GeneratedFile> _verticalExpectedFiles(
    CleanArchitectGenerator generator,
    _Layer layer,
  ) {
    if (layer.label.startsWith('feature:')) {
      return generator.feature(layer.label.substring('feature:'.length));
    }
    if (layer.label == 'app') {
      final feature = _layers()
          .where((item) => item.label.startsWith('feature:'))
          .map((item) => item.label.substring('feature:'.length))
          .firstOrNull;
      if (feature != null) return generator.feature(feature);
    }
    return generator.architecture();
  }

  void _checkEnvironment(_Pubspec actual, YamlMap expected) {
    final actualEnvironment = _map(actual.document['environment']);
    final expectedEnvironment = _map(expected['environment']);
    for (final key in ['sdk', 'flutter']) {
      final expectedValue = expectedEnvironment?[key];
      if (expectedValue is! String) continue;
      final actualValue = actualEnvironment?[key];
      if (actualValue is! String) {
        _error('${actual.layer.label} is missing environment.$key.');
        continue;
      }
      _checkConstraint(
        actual.layer.label,
        'environment.$key',
        actualValue,
        expectedValue,
      );
      if (key == 'sdk') {
        try {
          final constraint = VersionConstraint.parse(actualValue);
          final running = Version.parse(_dartVersion);
          if (!constraint.allows(running)) {
            _error(
              '${actual.layer.label} requires Dart $actualValue, but '
              'the active SDK is $running.',
            );
          }
        } on FormatException {
          // The malformed constraint is reported by _checkConstraint.
        }
      }
    }
  }

  void _checkDependencies(
    _Pubspec actual,
    YamlMap expected,
    Map<String, String> packageRoots,
  ) {
    for (final section in ['dependencies', 'dev_dependencies']) {
      final expectedDependencies = _map(expected[section]);
      if (expectedDependencies == null) continue;
      final actualDependencies = _map(actual.document[section]);

      for (final dependency in expectedDependencies.keys.whereType<String>()) {
        final expectedValue = expectedDependencies[dependency];
        final actualValue = actualDependencies?[dependency];
        if (actualValue == null) {
          _error(
            '${actual.layer.label} is missing $section dependency '
            '"$dependency".',
          );
          continue;
        }
        _checkDependencyValue(
          actual,
          section,
          dependency,
          actualValue,
          expectedValue,
          packageRoots,
        );
      }
    }
  }

  void _checkDependencyValue(
    _Pubspec pubspec,
    String section,
    String dependency,
    Object actual,
    Object? expected,
    Map<String, String> packageRoots,
  ) {
    if (expected is String) {
      final actualConstraint = _hostedConstraint(actual);
      if (actualConstraint == null) {
        _error(
          '${pubspec.layer.label} $section dependency "$dependency" '
          'must use a hosted version constraint.',
        );
        return;
      }
      _checkConstraint(
        pubspec.layer.label,
        '$section.$dependency',
        actualConstraint,
        expected,
      );
      return;
    }

    final expectedMap = _map(expected);
    final actualMap = _map(actual);
    if (expectedMap?['sdk'] != null) {
      if (actualMap?['sdk'] != expectedMap!['sdk']) {
        _error(
          '${pubspec.layer.label} $section dependency "$dependency" '
          'must use sdk: ${expectedMap['sdk']}.',
        );
      }
      return;
    }

    if (expectedMap?['path'] != null) {
      final pathValue = actualMap?['path'];
      if (pathValue is! String) {
        _error(
          '${pubspec.layer.label} $section dependency "$dependency" '
          'must be a path dependency.',
        );
        return;
      }
      final expectedRoot = packageRoots[dependency];
      final resolved = p.normalize(p.absolute(pubspec.layer.root, pathValue));
      if (expectedRoot == null || resolved != p.normalize(expectedRoot)) {
        _error(
          '${pubspec.layer.label} dependency "$dependency" points to '
          '"$resolved" instead of the configured package root.',
        );
      }
    }
  }

  void _checkConstraint(
    String layer,
    String field,
    String actual,
    String expected,
  ) {
    try {
      final actualConstraint = VersionConstraint.parse(actual);
      final expectedConstraint = VersionConstraint.parse(expected);
      if (!actualConstraint.allowsAny(expectedConstraint)) {
        _error(
          '$layer $field constraint "$actual" is incompatible with '
          'the supported constraint "$expected".',
        );
      }
    } on FormatException catch (error) {
      _error(
        '$layer $field has an invalid version constraint: ${error.message}',
      );
    }
  }

  void _checkBuildRunner(_Pubspec pubspec, YamlMap expected) {
    final expectedDev = _map(expected['dev_dependencies']);
    if (expectedDev?['build_runner'] == null) return;

    final packageConfig = File(
      p.join(pubspec.layer.root, '.dart_tool', 'package_config.json'),
    );
    if (!packageConfig.existsSync()) {
      _error(
        'build_runner is unavailable in ${pubspec.layer.label}; '
        'run "dart pub get" in ${pubspec.layer.root}.',
      );
      return;
    }

    try {
      final value = jsonDecode(packageConfig.readAsStringSync());
      final packages = value is Map<String, dynamic> ? value['packages'] : null;
      final available =
          packages is List &&
          packages.whereType<Map<String, dynamic>>().any(
            (package) => package['name'] == 'build_runner',
          );
      if (!available) {
        _error(
          'build_runner is not resolved in ${pubspec.layer.label}; '
          'run "dart pub get" in ${pubspec.layer.root}.',
        );
      } else {
        _success('build_runner is available in ${pubspec.layer.label}.');
      }
    } on FormatException {
      _error(
        '${pubspec.layer.label} .dart_tool/package_config.json is invalid.',
      );
    }
  }

  void _checkFlutter(Iterable<_Pubspec> pubspecs) {
    final requiresFlutter = pubspecs.any((pubspec) {
      final environment = _map(pubspec.document['environment']);
      final dependencies = _map(pubspec.document['dependencies']);
      return environment?['flutter'] != null ||
          _map(dependencies?['flutter'])?['sdk'] == 'flutter';
    });
    if (!requiresFlutter) return;

    ProcessResult result;
    try {
      result = _commandRunner('flutter', const ['--version', '--machine']);
    } on ProcessException {
      _error('Flutter is required but the flutter executable was not found.');
      return;
    }
    if (result.exitCode != 0) {
      _error('Flutter is required but "flutter --version" failed.');
      return;
    }

    try {
      final value = jsonDecode(result.stdout.toString());
      final versionText = value is Map<String, dynamic>
          ? value['frameworkVersion']
          : null;
      if (versionText is! String) {
        _error('Unable to determine the installed Flutter version.');
        return;
      }
      final version = Version.parse(versionText);
      _success('Flutter $version is available.');
      for (final pubspec in pubspecs) {
        final environment = _map(pubspec.document['environment']);
        final constraintText = environment?['flutter'];
        if (constraintText is! String) continue;
        try {
          final constraint = VersionConstraint.parse(constraintText);
          if (!constraint.allows(version)) {
            _error(
              '${pubspec.layer.label} requires Flutter $constraintText, '
              'but the installed version is $version.',
            );
          }
        } on FormatException {
          // The malformed constraint is reported by _checkEnvironment.
        }
      }
    } on FormatException {
      _error('Unable to parse the installed Flutter version.');
    }
  }

  void _checkGeneratedParts(
    List<_Layer> layers,
    Map<String, String> packageRoots,
  ) {
    final directive = RegExp(
      r'''(?:part|import)\s+['"]([^'"]+\.g\.dart)['"]\s*;''',
    );
    final missing = <String>{};
    for (final layer in layers) {
      final lib = Directory(p.join(layer.root, 'lib'));
      if (!lib.existsSync()) continue;
      for (final source in lib.listSync(recursive: true).whereType<File>()) {
        if (!source.path.endsWith('.dart') || source.path.endsWith('.g.dart')) {
          continue;
        }
        final content = source.readAsStringSync();
        for (final match in directive.allMatches(content)) {
          final reference = match.group(1)!;
          final generated = reference.startsWith('package:')
              ? _resolvePackageReference(reference, packageRoots)
              : p.normalize(p.join(source.parent.path, reference));
          if (generated == null) continue;
          if (!File(generated).existsSync()) missing.add(generated);
        }
      }
    }

    for (final path in missing) {
      _error('Generated file is missing: $path. Run build_runner.');
    }
    if (missing.isEmpty) {
      _success('Generated .g.dart files are present.');
    }
  }

  String? _resolvePackageReference(
    String reference,
    Map<String, String> packageRoots,
  ) {
    final packagePath = reference.substring('package:'.length);
    final separator = packagePath.indexOf('/');
    if (separator == -1) return null;
    final packageName = packagePath.substring(0, separator);
    final packageRoot = packageRoots[packageName];
    if (packageRoot == null) return null;
    return p.normalize(
      p.join(packageRoot, 'lib', packagePath.substring(separator + 1)),
    );
  }

  String? _hostedConstraint(Object value) {
    if (value is String) return value;
    final map = _map(value);
    final version = map?['version'];
    return version is String ? version : null;
  }

  YamlMap? _map(Object? value) => value is YamlMap ? value : null;

  void _success(String message) {
    _diagnostics.add(DoctorDiagnostic(DoctorLevel.success, message));
  }

  void _error(String message) {
    _diagnostics.add(DoctorDiagnostic(DoctorLevel.error, message));
  }

  static ProcessResult _runCommand(String executable, List<String> arguments) {
    return Process.runSync(executable, arguments);
  }
}

class _Layer {
  const _Layer({
    required this.label,
    required this.configuredPath,
    required this.relativeRoot,
    required this.root,
  });

  final String label;
  final String configuredPath;
  final String relativeRoot;
  final String root;
}

class _Pubspec {
  const _Pubspec({
    required this.layer,
    required this.document,
    required this.name,
  });

  final _Layer layer;
  final YamlMap document;
  final String? name;
}
