import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'config.dart';

enum ScanConfidence {
  low(0.35),
  medium(0.7),
  high(0.95);

  const ScanConfidence(this.score);

  final double score;
}

enum ScanDiagnosticLevel { info, warning, error }

class ScanDiagnostic {
  const ScanDiagnostic(this.level, this.message);

  final ScanDiagnosticLevel level;
  final String message;
}

class ScanFinding {
  const ScanFinding({
    required this.key,
    required this.value,
    required this.confidence,
    required this.evidence,
  });

  final String key;
  final Object value;
  final ScanConfidence confidence;
  final List<String> evidence;

  Map<String, Object> toJson() => {
    'value': value,
    'confidence': confidence.name,
    'score': confidence.score,
    'evidence': evidence,
  };
}

class ProjectScanResult {
  const ProjectScanResult({
    required this.projectRoot,
    required this.config,
    required this.findings,
    required this.diagnostics,
    required this.canWrite,
    required this.requiresForce,
  });

  final String projectRoot;
  final CleanArchitectConfig? config;
  final Map<String, ScanFinding> findings;
  final List<ScanDiagnostic> diagnostics;
  final bool canWrite;
  final bool requiresForce;

  ScanConfidence get confidence {
    if (config == null || findings.isEmpty) return ScanConfidence.low;
    if (requiresForce) return ScanConfidence.medium;
    return ScanConfidence.high;
  }

  Map<String, Object?> toJson() => {
    'project_root': projectRoot,
    'confidence': confidence.name,
    'can_write': canWrite,
    'requires_force': requiresForce,
    'findings': findings.map((key, finding) => MapEntry(key, finding.toJson())),
    'diagnostics': [
      for (final diagnostic in diagnostics)
        {'level': diagnostic.level.name, 'message': diagnostic.message},
    ],
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class ProjectScanner {
  ProjectScanner({String? projectRoot})
    : projectRoot = p.normalize(
        p.absolute(projectRoot ?? Directory.current.path),
      );

  final String projectRoot;

  ProjectScanResult scan() {
    final diagnostics = <ScanDiagnostic>[];
    final packages = _discoverPackages(diagnostics);
    if (packages.isEmpty) {
      diagnostics.add(
        const ScanDiagnostic(
          ScanDiagnosticLevel.error,
          'No pubspec.yaml files were found below the scan root.',
        ),
      );
      return ProjectScanResult(
        projectRoot: projectRoot,
        config: null,
        findings: const {},
        diagnostics: diagnostics,
        canWrite: false,
        requiresForce: false,
      );
    }

    final verticalFeatures = packages
        .where(
          (package) =>
              package.hasDirectory('lib/src/domain') &&
              package.hasDirectory('lib/src/data'),
        )
        .toList(growable: false);
    if (verticalFeatures.isNotEmpty) {
      return _scanVertical(packages, verticalFeatures, diagnostics);
    }
    return _scanLayered(packages, diagnostics);
  }

  ProjectScanResult _scanLayered(
    List<_PackageInfo> packages,
    List<ScanDiagnostic> diagnostics,
  ) {
    final selections = <String, _RoleSelection>{};
    final usedRoots = <String>{};
    for (final role in const ['domain', 'data', 'presentation', 'di']) {
      final selection = _selectRole(role, packages, usedRoots, diagnostics);
      if (selection != null) {
        selections[role] = selection;
        usedRoots.add(selection.package.root);
      }
    }

    if (selections.length != 4) {
      diagnostics.add(
        const ScanDiagnostic(
          ScanDiagnosticLevel.error,
          'Could not identify four distinct domain, data, presentation, and DI packages.',
        ),
      );
      return ProjectScanResult(
        projectRoot: projectRoot,
        config: null,
        findings: const {},
        diagnostics: diagnostics,
        canWrite: false,
        requiresForce: false,
      );
    }

    final domain = selections['domain']!.package;
    final data = selections['data']!.package;
    final presentation = selections['presentation']!.package;
    final di = selections['di']!.package;
    final domainFeatures = domain.featureRoots(_FeatureRole.domain);
    final dataFeatures = data.featureRoots(_FeatureRole.data);
    final presentationFeatures = presentation.featureRoots(
      _FeatureRole.presentation,
    );
    final featureFirst = presentationFeatures.any(
      (path) => p
          .split(p.relative(path, from: presentation.libRoot))
          .contains('features'),
    );
    final structure = featureFirst
        ? ProjectStructure.featureFirst
        : ProjectStructure.layeredPackages;
    final dataLayout = _detectDataLayout(data);
    final paths = PathConfig(
      domain: _domainBase(domain, domainFeatures),
      data: _configuredFeatureBase(data, dataFeatures),
      presentation: featureFirst
          ? _baseBeforeFeatures(presentation, presentationFeatures)
          : _presentationBase(presentation, presentationFeatures),
      di: featureFirst
          ? _baseBeforeNamedDirectory(di, 'features')
          : _diBase(di),
    );
    final options = _detectOptions([
      domain,
      data,
      presentation,
      di,
    ], presentation);
    final config = CleanArchitectConfig(
      structure: structure,
      dataLayout: dataLayout,
      stateManagement: options.stateManagement,
      network: options.network,
      localStorage: options.localStorage,
      dependencyInjection: options.dependencyInjection,
      models: options.models,
      paths: paths,
      useAssetGenerator: options.useAssetGenerator,
      useEitherFailure: options.useEitherFailure,
      flutter: options.flutter,
    );

    final findings = <String, ScanFinding>{
      'structure': _finding(
        'structure',
        config.structureName,
        ScanConfidence.high,
        featureFirst
            ? ['Presentation features are grouped below a features directory.']
            : ['Business layers are separate packages.'],
      ),
      'data_layout': _finding(
        'data_layout',
        config.dataLayoutName,
        ScanConfidence.high,
        ['Detected from local/remote model and data-source directories.'],
      ),
      ..._optionFindings(config, options),
      'paths.domain': _pathFinding(
        'paths.domain',
        paths.domain,
        selections['domain']!,
      ),
      'paths.data': _pathFinding('paths.data', paths.data, selections['data']!),
      'paths.presentation': _pathFinding(
        'paths.presentation',
        paths.presentation,
        selections['presentation']!,
      ),
      'paths.di': _pathFinding('paths.di', paths.di, selections['di']!),
    };
    final required = [
      findings['paths.domain']!,
      findings['paths.data']!,
      findings['paths.presentation']!,
      findings['paths.di']!,
    ];
    final validConfig = _validateDetectedConfig(config, diagnostics);
    final canWrite =
        validConfig &&
        required.every((finding) => finding.confidence != ScanConfidence.low);
    final requiresForce = required.any(
      (finding) => finding.confidence == ScanConfidence.medium,
    );
    return ProjectScanResult(
      projectRoot: projectRoot,
      config: config,
      findings: findings,
      diagnostics: diagnostics,
      canWrite: canWrite,
      requiresForce: requiresForce,
    );
  }

  ProjectScanResult _scanVertical(
    List<_PackageInfo> packages,
    List<_PackageInfo> featurePackages,
    List<ScanDiagnostic> diagnostics,
  ) {
    final featureParent = _commonParent(
      featurePackages
          .map((package) => p.dirname(package.root))
          .toList(growable: false),
    );
    final outsideFeatures = packages
        .where((package) => !p.isWithin(featureParent, package.root))
        .toList(growable: false);
    final appSelection = _selectRole(
      'presentation',
      outsideFeatures,
      const {},
      diagnostics,
    );
    final coreCandidates = outsideFeatures
        .where((package) => package.root != appSelection?.package.root)
        .toList(growable: false);
    coreCandidates.sort(
      (left, right) => _coreScore(right).compareTo(_coreScore(left)),
    );
    if (appSelection == null || coreCandidates.isEmpty) {
      diagnostics.add(
        const ScanDiagnostic(
          ScanDiagnosticLevel.error,
          'Vertical feature packages were found, but app or core could not be identified.',
        ),
      );
      return ProjectScanResult(
        projectRoot: projectRoot,
        config: null,
        findings: const {},
        diagnostics: diagnostics,
        canWrite: false,
        requiresForce: false,
      );
    }

    final app = appSelection.package;
    final core = coreCandidates.first;
    final representativeFeature = featurePackages.first;
    final options = _detectOptions([...featurePackages, app, core], app);
    final dataLayout = _detectDataLayout(representativeFeature);
    final paths = PathConfig(
      domain: 'domain/lib',
      data: 'data/lib/features',
      presentation: 'presentation/lib',
      di: 'di/lib',
      app: app.relativeLib,
      core: core.relativeLib,
      features: _relative(featureParent),
    );
    final config = CleanArchitectConfig(
      structure: ProjectStructure.verticalPackages,
      dataLayout: dataLayout,
      stateManagement: options.stateManagement,
      network: options.network,
      localStorage: options.localStorage,
      dependencyInjection: options.dependencyInjection,
      models: options.models,
      paths: paths,
      useAssetGenerator: options.useAssetGenerator,
      useEitherFailure: options.useEitherFailure,
      flutter: options.flutter,
    );
    final coreConfidence = _coreScore(core) >= 5
        ? ScanConfidence.high
        : ScanConfidence.medium;
    final findings = <String, ScanFinding>{
      'structure': _finding(
        'structure',
        config.structureName,
        ScanConfidence.high,
        ['Feature packages contain lib/src/domain and lib/src/data.'],
      ),
      'data_layout': _finding(
        'data_layout',
        config.dataLayoutName,
        ScanConfidence.high,
        ['Detected inside ${representativeFeature.relativeRoot}.'],
      ),
      ..._optionFindings(config, options),
      'paths.app': _finding(
        'paths.app',
        paths.app,
        appSelection.confidence,
        appSelection.evidence,
      ),
      'paths.core': _finding('paths.core', paths.core, coreConfidence, [
        'Selected ${core.relativeRoot} as the shared core package.',
      ]),
      'paths.features': _finding(
        'paths.features',
        paths.features,
        ScanConfidence.high,
        [
          '${featurePackages.length} vertical feature package(s) share this parent.',
        ],
      ),
    };
    final requiresForce =
        appSelection.confidence == ScanConfidence.medium ||
        coreConfidence == ScanConfidence.medium;
    final validConfig = _validateDetectedConfig(config, diagnostics);
    return ProjectScanResult(
      projectRoot: projectRoot,
      config: config,
      findings: findings,
      diagnostics: diagnostics,
      canWrite: validConfig,
      requiresForce: requiresForce,
    );
  }

  List<_PackageInfo> _discoverPackages(List<ScanDiagnostic> diagnostics) {
    final root = Directory(projectRoot);
    if (!root.existsSync()) {
      diagnostics.add(
        ScanDiagnostic(
          ScanDiagnosticLevel.error,
          'Scan root does not exist: $projectRoot.',
        ),
      );
      return const [];
    }
    final pubspecs = <File>[];
    _walkForPubspecs(root, pubspecs, depth: 0);
    final packages = <_PackageInfo>[];
    for (final file in pubspecs) {
      try {
        final document = loadYaml(file.readAsStringSync());
        if (document is! YamlMap) continue;
        packages.add(_PackageInfo.fromPubspec(projectRoot, file, document));
      } on FormatException catch (error) {
        diagnostics.add(
          ScanDiagnostic(
            ScanDiagnosticLevel.warning,
            'Ignored invalid ${p.relative(file.path, from: projectRoot)}: ${error.message}',
          ),
        );
      }
    }
    packages.sort((left, right) => left.root.compareTo(right.root));
    return packages;
  }

  void _walkForPubspecs(
    Directory directory,
    List<File> output, {
    required int depth,
  }) {
    if (depth > 6) return;
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) output.add(pubspec);
    for (final child
        in directory.listSync(followLinks: false).whereType<Directory>()) {
      final name = p.basename(child.path);
      if (_ignoredDirectories.contains(name)) continue;
      _walkForPubspecs(child, output, depth: depth + 1);
    }
  }

  _RoleSelection? _selectRole(
    String role,
    List<_PackageInfo> packages,
    Set<String> usedRoots,
    List<ScanDiagnostic> diagnostics,
  ) {
    final candidates =
        packages
            .where((package) => !usedRoots.contains(package.root))
            .map(
              (package) => (package: package, score: _roleScore(role, package)),
            )
            .where((candidate) => candidate.score >= 3)
            .toList(growable: false)
          ..sort((left, right) => right.score.compareTo(left.score));
    if (candidates.isEmpty) return null;
    final winner = candidates.first;
    final tied = candidates.length > 1 && candidates[1].score == winner.score;
    final confidence = tied || winner.score < 7
        ? ScanConfidence.medium
        : ScanConfidence.high;
    if (tied) {
      diagnostics.add(
        ScanDiagnostic(
          ScanDiagnosticLevel.warning,
          'Multiple packages scored equally for $role; selected ${winner.package.relativeRoot}.',
        ),
      );
    }
    return _RoleSelection(
      package: winner.package,
      confidence: confidence,
      evidence: [
        '${winner.package.relativeRoot} matched the $role role with score ${winner.score}.',
      ],
    );
  }

  int _roleScore(String role, _PackageInfo package) {
    final basename = p.basename(package.root);
    final named = package.name == role || basename == role;
    return switch (role) {
      'domain' =>
        (named ? 6 : 0) +
            (package.hasDirectoryNamed('entities') ? 2 : 0) +
            (package.hasDirectoryNamed('usecases') ? 2 : 0) +
            (package.hasDirectoryNamed('repositories') ? 1 : 0),
      'data' =>
        (named ? 6 : 0) +
            (package.hasDirectoryNamed('models') ? 2 : 0) +
            (package.hasDirectoryNamed('mappers') ? 2 : 0) +
            (package.dependencies.any(_dataDependencies.contains) ? 2 : 0),
      'presentation' =>
        ((package.name == 'presentation' || basename == 'presentation')
                ? 6
                : 0) +
            (package.isFlutter ? 2 : 0) +
            (package.hasFile('lib/main.dart') ? 3 : 0) +
            (package.hasDirectoryNamed('pages') ? 1 : 0) +
            (package.hasDirectoryNamed('controllers') ? 1 : 0),
      'di' =>
        (named ? 6 : 0) +
            (package.dependencies.contains('get_it') ? 2 : 0) +
            (package.dependencies.contains('injectable') ? 2 : 0) +
            (package.hasFileNamed('di.dart') ||
                    package.hasFileNamed('injector.dart')
                ? 2
                : 0),
      _ => 0,
    };
  }

  int _coreScore(_PackageInfo package) {
    final basename = p.basename(package.root);
    return (package.name == 'core' || basename == 'core' ? 6 : 0) +
        (package.hasFile('lib/core.dart') ? 3 : 0) +
        (package.hasDirectory('lib/src/failures') ? 1 : 0);
  }

  DataLayout _detectDataLayout(_PackageInfo package) {
    final typeFirst =
        package.hasPathSegments(['models', 'remote']) ||
        package.hasPathSegments(['data_sources', 'remote']);
    return typeFirst ? DataLayout.typeFirst : DataLayout.sourceFirst;
  }

  _DetectedOptions _detectOptions(
    List<_PackageInfo> packages,
    _PackageInfo presentation,
  ) {
    final dependencies = packages
        .expand((package) => package.dependencies)
        .toSet();
    final source = packages.map((package) => package.sourceText).join('\n');
    final state = dependencies.contains('flutter_bloc')
        ? StateManagement.bloc
        : dependencies.contains('provider')
        ? StateManagement.provider
        : dependencies.contains('get')
        ? StateManagement.getx
        : StateManagement.none;
    final network =
        dependencies.contains('dio') || dependencies.contains('retrofit')
        ? NetworkClient.dio
        : NetworkClient.abstract;
    final storage = dependencies.contains('objectbox')
        ? LocalStorage.objectbox
        : dependencies.contains('hive_ce') || dependencies.contains('hive')
        ? LocalStorage.hive
        : dependencies.contains('flutter_secure_storage')
        ? LocalStorage.secureStorage
        : dependencies.contains('shared_preferences')
        ? LocalStorage.sharedPreferences
        : LocalStorage.abstract;
    final injectable =
        dependencies.contains('injectable') ||
        source.contains('@InjectableInit') ||
        source.contains('@lazySingleton');
    final platforms = _supportedPlatforms
        .where(
          (platform) =>
              Directory(p.join(presentation.root, platform)).existsSync(),
        )
        .toList(growable: false);
    return _DetectedOptions(
      stateManagement: state,
      network: network,
      localStorage: storage,
      dependencyInjection: injectable
          ? DependencyInjection.injectable
          : DependencyInjection.manual,
      models: ModelConfig(
        useFreezed:
            dependencies.contains('freezed_annotation') ||
            source.contains('@freezed'),
        useJsonSerializable: dependencies.contains('json_annotation'),
      ),
      useAssetGenerator: dependencies.contains('assets_generator_kit'),
      useEitherFailure:
          dependencies.contains('dartz') && source.contains('Either<Failure'),
      flutter: FlutterConfig(createPresentation: false, platforms: platforms),
    );
  }

  Map<String, ScanFinding> _optionFindings(
    CleanArchitectConfig config,
    _DetectedOptions options,
  ) => {
    'state_management': _finding(
      'state_management',
      config.stateManagementName,
      ScanConfidence.high,
      ['Detected from presentation dependencies.'],
    ),
    'network': _finding('network', config.networkName, ScanConfidence.high, [
      'Detected from Dio/Retrofit dependencies and imports.',
    ]),
    'local_storage': _finding(
      'local_storage',
      config.localStorageName,
      ScanConfidence.high,
      ['Detected from storage package dependencies.'],
    ),
    'dependency_injection': _finding(
      'dependency_injection',
      config.dependencyInjectionName,
      ScanConfidence.high,
      ['Detected from GetIt/Injectable dependencies and annotations.'],
    ),
    'use_asset_generator': _finding(
      'use_asset_generator',
      options.useAssetGenerator,
      ScanConfidence.medium,
      ['Detected from package dependencies.'],
    ),
    'use_either_failure': _finding(
      'use_either_failure',
      options.useEitherFailure,
      ScanConfidence.high,
      ['Detected from dartz and Either<Failure, T> usage.'],
    ),
    'models.use_freezed': _finding(
      'models.use_freezed',
      options.models.useFreezed,
      ScanConfidence.high,
      ['Detected from dependencies and model annotations.'],
    ),
    'models.use_json_serializable': _finding(
      'models.use_json_serializable',
      options.models.useJsonSerializable,
      ScanConfidence.high,
      ['Detected from dependencies and JSON factories.'],
    ),
    'flutter.create_presentation': _finding(
      'flutter.create_presentation',
      options.flutter.createPresentation,
      ScanConfidence.low,
      [
        'Whether future commands should run flutter create is user intent and cannot be inferred.',
      ],
    ),
    'flutter.platforms': _finding(
      'flutter.platforms',
      options.flutter.platforms,
      ScanConfidence.high,
      ['Detected platform directories in the presentation package.'],
    ),
  };

  ScanFinding _pathFinding(String key, String value, _RoleSelection selection) {
    return _finding(key, value, selection.confidence, selection.evidence);
  }

  bool _validateDetectedConfig(
    CleanArchitectConfig config,
    List<ScanDiagnostic> diagnostics,
  ) {
    try {
      config.validate();
      return true;
    } on FormatException catch (error) {
      diagnostics.add(
        ScanDiagnostic(
          ScanDiagnosticLevel.error,
          'Detected configuration is not writable: ${error.message}',
        ),
      );
      return false;
    }
  }

  ScanFinding _finding(
    String key,
    Object value,
    ScanConfidence confidence,
    List<String> evidence,
  ) => ScanFinding(
    key: key,
    value: value,
    confidence: confidence,
    evidence: List.unmodifiable(evidence),
  );

  String _configuredFeatureBase(
    _PackageInfo package,
    List<String> featureRoots,
  ) {
    if (featureRoots.isEmpty) return package.relativeLib;
    final parent = _commonParent(
      featureRoots.map(p.dirname).toList(growable: false),
    );
    return _relative(parent);
  }

  String _domainBase(_PackageInfo package, List<String> featureRoots) {
    final detected = _configuredFeatureBase(package, featureRoots);
    if (p.basename(p.normalize(detected)) == 'features') {
      return p.dirname(detected).split(p.separator).join('/');
    }
    return detected;
  }

  String _baseBeforeFeatures(_PackageInfo package, List<String> featureRoots) {
    if (featureRoots.isEmpty) return package.relativeLib;
    return _baseBeforeNamedDirectory(package, 'features');
  }

  String _presentationBase(
    _PackageInfo package,
    List<String> presentationRoots,
  ) {
    if (presentationRoots.isEmpty) return package.relativeLib;
    return _relative(_commonParent(presentationRoots));
  }

  String _diBase(_PackageInfo package) {
    final registrationFiles = package.files
        .where((path) => p.basename(path).endsWith('_di.dart'))
        .toList(growable: false);
    if (registrationFiles.isEmpty) return package.relativeLib;
    return _relative(
      _commonParent(registrationFiles.map(p.dirname).toList(growable: false)),
    );
  }

  String _baseBeforeNamedDirectory(_PackageInfo package, String name) {
    final searchRoot = Directory(package.libRoot);
    final named = searchRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<Directory>()
        .where((directory) => p.basename(directory.path) == name)
        .map((directory) => p.split(directory.path))
        .firstOrNull;
    if (named == null) return package.relativeLib;
    return _relative(p.joinAll(named.take(named.length - 1)));
  }

  String _relative(String absolutePath) =>
      p.relative(absolutePath, from: projectRoot).split(p.separator).join('/');

  String _commonParent(List<String> paths) {
    if (paths.isEmpty) return projectRoot;
    var parts = p.split(p.normalize(paths.first));
    for (final path in paths.skip(1)) {
      final next = p.split(p.normalize(path));
      var shared = 0;
      while (shared < parts.length &&
          shared < next.length &&
          parts[shared] == next[shared]) {
        shared++;
      }
      parts = parts.take(shared).toList(growable: false);
    }
    return p.joinAll(parts);
  }
}

class ScanConfigWriter {
  const ScanConfigWriter();

  String render(ProjectScanResult result, {String? existingYaml}) {
    final config = result.config;
    if (config == null) {
      throw const FormatException(
        'Scan did not produce a writable configuration.',
      );
    }
    final values = _configValues(config);
    if (existingYaml == null || existingYaml.trim().isEmpty) {
      final editor = YamlEditor('');
      editor.update([], {'clean_architect': values});
      return '${editor.toString().trimRight()}\n';
    }

    final document = loadYaml(existingYaml);
    if (document is! YamlMap) {
      throw const FormatException('clean_architect.yaml must contain a map.');
    }
    final editor = YamlEditor(existingYaml);
    if (document['clean_architect'] is! YamlMap) {
      editor.update(['clean_architect'], values);
      return '${editor.toString().trimRight()}\n';
    }

    var current = document['clean_architect'] as YamlMap;
    for (final section in const ['flutter', 'models', 'paths']) {
      if (current[section] is! YamlMap) {
        editor.update(['clean_architect', section], <String, Object>{});
        current = loadYaml(editor.toString())['clean_architect'] as YamlMap;
      }
    }
    editor.update(['clean_architect', 'config_version'], config.configVersion);
    for (final finding in result.findings.values) {
      if (finding.confidence == ScanConfidence.low) continue;
      editor.update([
        'clean_architect',
        ...finding.key.split('.'),
      ], finding.value);
    }
    return '${editor.toString().trimRight()}\n';
  }

  void write(ProjectScanResult result, File target) {
    final existing = target.existsSync() ? target.readAsStringSync() : null;
    final rendered = render(result, existingYaml: existing);
    if (existing == rendered) return;
    final temporary = File('${target.path}.scan.tmp');
    final backup = File('${target.path}.scan.backup');
    temporary.writeAsStringSync(rendered);
    CleanArchitectConfig.fromFile(temporary);

    if (backup.existsSync()) backup.deleteSync();
    if (target.existsSync()) target.renameSync(backup.path);
    try {
      temporary.renameSync(target.path);
      if (backup.existsSync()) backup.deleteSync();
    } catch (_) {
      if (target.existsSync()) target.deleteSync();
      if (backup.existsSync()) backup.renameSync(target.path);
      rethrow;
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  Map<String, Object> _configValues(CleanArchitectConfig config) => {
    'config_version': config.configVersion,
    'structure': config.structureName,
    'data_layout': config.dataLayoutName,
    'state_management': config.stateManagementName,
    'network': config.networkName,
    'local_storage': config.localStorageName,
    'dependency_injection': config.dependencyInjectionName,
    'use_asset_generator': config.useAssetGenerator,
    'use_either_failure': config.useEitherFailure,
    'flutter': <String, Object>{
      'create_presentation': config.flutter.createPresentation,
      'platforms': config.flutter.platforms,
    },
    'models': <String, Object>{
      'use_freezed': config.models.useFreezed,
      'use_json_serializable': config.models.useJsonSerializable,
    },
    'paths': <String, Object>{
      'domain': config.paths.domain,
      'data': config.paths.data,
      'presentation': config.paths.presentation,
      'di': config.paths.di,
      'app': config.paths.app,
      'core': config.paths.core,
      'features': config.paths.features,
    },
  };
}

enum _FeatureRole { domain, data, presentation }

class _RoleSelection {
  const _RoleSelection({
    required this.package,
    required this.confidence,
    required this.evidence,
  });

  final _PackageInfo package;
  final ScanConfidence confidence;
  final List<String> evidence;
}

class _DetectedOptions {
  const _DetectedOptions({
    required this.stateManagement,
    required this.network,
    required this.localStorage,
    required this.dependencyInjection,
    required this.models,
    required this.useAssetGenerator,
    required this.useEitherFailure,
    required this.flutter,
  });

  final StateManagement stateManagement;
  final NetworkClient network;
  final LocalStorage localStorage;
  final DependencyInjection dependencyInjection;
  final ModelConfig models;
  final bool useAssetGenerator;
  final bool useEitherFailure;
  final FlutterConfig flutter;
}

class _PackageInfo {
  _PackageInfo({
    required this.projectRoot,
    required this.root,
    required this.name,
    required this.dependencies,
    required this.isFlutter,
  });

  factory _PackageInfo.fromPubspec(
    String projectRoot,
    File pubspec,
    YamlMap document,
  ) {
    final dependencies = <String>{};
    for (final section in ['dependencies', 'dev_dependencies']) {
      final value = document[section];
      if (value is YamlMap) dependencies.addAll(value.keys.whereType<String>());
    }
    final root = pubspec.parent.path;
    final flutterDependency = document['dependencies'] is YamlMap
        ? (document['dependencies'] as YamlMap)['flutter']
        : null;
    return _PackageInfo(
      projectRoot: projectRoot,
      root: root,
      name: document['name'] is String
          ? document['name'] as String
          : p.basename(root),
      dependencies: dependencies,
      isFlutter: flutterDependency != null,
    );
  }

  final String projectRoot;
  final String root;
  final String name;
  final Set<String> dependencies;
  final bool isFlutter;
  String? _sourceText;
  List<String>? _directories;
  List<String>? _files;

  String get libRoot => p.join(root, 'lib');
  String get relativeRoot => p.relative(root, from: projectRoot);
  String get relativeLib =>
      p.relative(libRoot, from: projectRoot).split(p.separator).join('/');

  List<String> get directories =>
      _directories ??= Directory(libRoot).existsSync()
      ? Directory(libRoot)
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .map((directory) => p.normalize(directory.path))
            .toList(growable: false)
      : const [];

  List<String> get files => _files ??= Directory(libRoot).existsSync()
      ? Directory(libRoot)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => p.normalize(file.path))
            .toList(growable: false)
      : const [];

  String get sourceText => _sourceText ??= files
      .where((path) => path.endsWith('.dart'))
      .map((path) {
        final file = File(path);
        return file.lengthSync() <= 1024 * 1024 ? file.readAsStringSync() : '';
      })
      .join('\n');

  bool hasDirectory(String relative) =>
      Directory(p.join(root, relative)).existsSync();
  bool hasFile(String relative) => File(p.join(root, relative)).existsSync();
  bool hasDirectoryNamed(String name) =>
      directories.any((directory) => p.basename(directory) == name);
  bool hasFileNamed(String name) =>
      files.any((file) => p.basename(file) == name);
  bool hasPathSegments(List<String> segments) => directories.any((directory) {
    final parts = p.split(p.relative(directory, from: libRoot));
    for (var index = 0; index <= parts.length - segments.length; index++) {
      if (parts.sublist(index, index + segments.length).join('/') ==
          segments.join('/')) {
        return true;
      }
    }
    return false;
  });

  List<String> featureRoots(_FeatureRole role) {
    return directories
        .where((directory) {
          bool child(String name) =>
              Directory(p.join(directory, name)).existsSync();
          return switch (role) {
            _FeatureRole.domain =>
              child('entities') && child('repositories') && child('usecases'),
            _FeatureRole.data =>
              child('repositories') &&
                  ((child('remote') && child('local')) ||
                      (child('data_sources') && child('models'))),
            _FeatureRole.presentation => child('controllers') && child('pages'),
          };
        })
        .toList(growable: false);
  }
}

const _ignoredDirectories = {
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'coverage',
  'node_modules',
};

const _dataDependencies = {
  'dio',
  'retrofit',
  'objectbox',
  'hive',
  'hive_ce',
  'flutter_secure_storage',
  'shared_preferences',
};

const _supportedPlatforms = [
  'android',
  'ios',
  'web',
  'windows',
  'macos',
  'linux',
];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
