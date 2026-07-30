import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'case_utils.dart';
import 'config.dart';
import 'data_paths.dart';
import 'file_writer.dart';
import 'generator.dart';
import 'generated_file.dart';
import 'manual_di_patcher.dart';
import 'operation_patcher.dart';
import 'operation_kind.dart';
import 'path_resolver.dart';
import 'project_doctor.dart';
import 'project_scanner.dart';
import 'version.dart';

class CleanArchitectCli {
  CleanArchitectCli({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  void run(List<String> arguments) {
    final parser = _buildParser();
    late final ArgResults results;

    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      _usageError(error.message, parser.usage);
      return;
    }

    if (results['version'] == true) {
      _logger.info('clean_architect $packageVersion');
      return;
    }
    if (results['help'] == true || results.command == null) {
      _logger.info(_rootHelp(parser));
      return;
    }

    final command = results.command!;
    if (command['help'] == true) {
      _logger.info(_commandHelp(command.name ?? '', command.rest));
      return;
    }

    try {
      switch (command.name) {
        case 'init':
          _init(command);
        case 'create':
          _create(command);
        case 'doctor':
          _doctor();
        case 'scan':
          _scan(command);
        default:
          _usageError('Unknown command: ${command.name}', parser.usage);
      }
    } on FormatException catch (error) {
      _logger.err(error.message);
      exitCode = 64;
    } on FileSystemException catch (error) {
      _logger.err(error.message);
      exitCode = 74;
    }
  }

  ArgParser _buildParser() {
    final parser = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('version', negatable: false);

    parser.addCommand(
      'init',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addFlag('force', abbr: 'f', negatable: false)
        ..addFlag('dry-run', negatable: false),
    );

    parser.addCommand(
      'doctor',
      ArgParser()..addFlag('help', abbr: 'h', negatable: false),
    );

    parser.addCommand(
      'scan',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addFlag('write', negatable: false)
        ..addFlag('force', abbr: 'f', negatable: false)
        ..addFlag('json', negatable: false)
        ..addOption('root', defaultsTo: '.'),
    );

    parser.addCommand(
      'create',
      ArgParser()
        ..addFlag('help', abbr: 'h', negatable: false)
        ..addFlag('dry-run', negatable: false)
        ..addFlag('overwrite', negatable: false)
        ..addFlag('force', abbr: 'f', negatable: false)
        ..addFlag('skip-presentation', negatable: false)
        ..addFlag('flutter-create', negatable: true)
        ..addOption('platforms')
        ..addOption('state', allowed: ['getx', 'bloc', 'provider', 'none'])
        ..addOption('network', allowed: ['dio', 'abstract'])
        ..addOption(
          'storage',
          allowed: [
            'secure_storage',
            'shared_preferences',
            'hive',
            'objectbox',
            'abstract',
          ],
        )
        ..addOption(
          'dependency-injection',
          abbr: 'd',
          allowed: ['manual', 'injectable'],
        )
        ..addOption('di', allowed: ['manual', 'injectable'])
        ..addOption('feature')
        ..addFlag('use-either-failure', negatable: true),
    );

    return parser;
  }

  void _init(ArgResults results) {
    final file = File(CleanArchitectConfig.fileName);
    final force = results['force'] == true;
    final dryRun = results['dry-run'] == true;

    if (dryRun) {
      _logger.info('create ${CleanArchitectConfig.fileName}');
      return;
    }

    if (file.existsSync() && !force) {
      _logger.warn('${CleanArchitectConfig.fileName} already exists');
      return;
    }

    file.writeAsStringSync(CleanArchitectConfig.defaultYaml());
    _logger.success('created ${CleanArchitectConfig.fileName}');
  }

  void _create(ArgResults results) {
    final args = results.rest;
    if (args.isEmpty) {
      _usageError(
        'A create target is required.',
        _commandHelp('create', const []),
      );
      return;
    }

    final config = _configWithOverrides(results);
    final skipPresentation = results['skip-presentation'] == true;
    _validateCreateSettings(results, config, skipPresentation);

    final overwrite = results['overwrite'] == true || results['force'] == true;
    final requestedFeature = switch (args.first) {
      'auth' => 'auth',
      'feature' when args.length == 2 => args[1],
      _ => null,
    };
    if (requestedFeature != null) {
      _validateName('Feature', requestedFeature);
      _validateVerticalFeaturePackageName(config, requestedFeature);
    }
    if (!overwrite &&
        requestedFeature != null &&
        _featureGenerationComplete(
          config,
          requestedFeature,
          skipPresentation: skipPresentation,
          isAuth: args.first == 'auth',
        )) {
      _logger.info(
        'skip feature ${NameCases(requestedFeature).snake}; already exists',
      );
      return;
    }

    final generator = CleanArchitectGenerator(config);
    final operationKind = _operationKind(args);
    final featureOption = results['feature'] as String?;
    if (operationKind != null && featureOption != null) {
      _validateName('Feature', featureOption);
      _requireExistingFeature(config, featureOption);
    }
    if (config.structure == ProjectStructure.verticalPackages &&
        args.first == 'usecase' &&
        featureOption != null) {
      _requireExistingFeature(config, featureOption);
    }

    final generated = _filesForCreate(
      args,
      generator,
      skipPresentation,
      featureOption,
      operationKind,
    );
    if (generated == null) {
      exitCode = 64;
      return;
    }

    final files = <GeneratedFile>[...generated];
    final modulePatch = _planFeatureDataModulePatch(args, config);
    if (modulePatch != null) files.add(modulePatch);
    final appPubspecPatch = _planVerticalAppPubspecPatch(args, config);
    if (appPubspecPatch != null) files.add(appPubspecPatch);

    final manualDi = ManualDiPatcher(config);
    if (requestedFeature != null) {
      final bootstrapPatch = manualDi.planFeatureBootstrap(requestedFeature);
      if (bootstrapPatch != null) files.add(bootstrapPatch);
    }

    if (operationKind != null) {
      files.addAll(
        OperationPatcher(config: config).plan(
          kind: operationKind,
          featureName: featureOption!,
          operationName: args[1],
        ),
      );
      final diPatch = manualDi.planOperation(
        kind: operationKind,
        featureName: featureOption,
        operationName: args[1],
      );
      if (diPatch != null) files.add(diPatch);
    } else if (args.first == 'usecase' && featureOption != null) {
      final diPatch = manualDi.planUseCase(
        featureName: featureOption,
        useCaseName: args[1],
      );
      if (diPatch != null) files.add(diPatch);
    }

    final writer = FileWriter(
      logger: _logger,
      dryRun: results['dry-run'] == true,
      overwrite: overwrite,
    );
    if (!writer.writeAll(files)) {
      exitCode = 73;
      return;
    }

    if (_shouldRunFlutterCreate(
      args,
      config,
      skipPresentation: skipPresentation,
      operationKind: operationKind,
    )) {
      _runFlutterCreate(config, dryRun: results['dry-run'] == true);
    }
  }

  List<GeneratedFile>? _filesForCreate(
    List<String> args,
    CleanArchitectGenerator generator,
    bool skipPresentation,
    String? featureOption,
    OperationKind? operationKind,
  ) {
    switch (args.first) {
      case 'architecture':
      case 'base':
        if (!_hasArgumentCount(
          args,
          1,
          'clean_architect create ${args.first}',
        )) {
          return null;
        }
        return generator.architecture(skipPresentation: skipPresentation);
      case 'auth':
        if (!_hasArgumentCount(args, 1, 'clean_architect create auth')) {
          return null;
        }
        return generator.auth(skipPresentation: skipPresentation);
      case 'feature':
        if (!_hasArgumentCount(
          args,
          2,
          'clean_architect create feature <name>',
        )) {
          return null;
        }
        _validateName('Feature', args[1]);
        return generator.feature(args[1], skipPresentation: skipPresentation);
      case 'usecase':
        final feature = featureOption;
        if (args.length != 2 || feature == null || feature.isEmpty) {
          _logger.err(
            'Usage: clean_architect create usecase <name> --feature <feature>',
          );
          return null;
        }
        _validateName('Use case', args[1]);
        _validateName('Feature', feature);
        return generator.useCase(args[1], feature: feature);
      case 'remote-function':
      case 'remote-method':
      case 'local-function':
      case 'local-method':
      case 'cached-function':
      case 'cached-method':
        final feature = featureOption;
        if (args.length != 2 || feature == null || feature.isEmpty) {
          _logger.err(
            'Usage: clean_architect create ${args.first} <name> --feature <feature>',
          );
          return null;
        }
        _validateName('Operation', args[1]);
        _validateName('Feature', feature);
        return generator.operation(
          args[1],
          feature: feature,
          kind: operationKind!,
        );
      case 'repository':
        if (!_hasArgumentCount(
          args,
          2,
          'clean_architect create repository <feature>',
        )) {
          return null;
        }
        _validateName('Feature', args[1]);
        _validateVerticalFeaturePackageName(generator.config, args[1]);
        return generator.repository(args[1]);
      default:
        _logger.err('Unknown create target: ${args.first}');
        return null;
    }
  }

  OperationKind? _operationKind(List<String> args) {
    if (args.isEmpty) return null;
    return switch (args.first) {
      'remote-function' || 'remote-method' => OperationKind.remote,
      'local-function' || 'local-method' => OperationKind.local,
      'cached-function' || 'cached-method' => OperationKind.cached,
      _ => null,
    };
  }

  CleanArchitectConfig _configWithOverrides(ArgResults results) {
    final config = CleanArchitectConfig.fromFile(
      File(CleanArchitectConfig.fileName),
    );

    final overridden = CleanArchitectConfig(
      configVersion: config.configVersion,
      structure: config.structure,
      dataLayout: config.dataLayout,
      stateManagement:
          _stateOverride(results['state'] as String?) ?? config.stateManagement,
      network:
          _networkOverride(results['network'] as String?) ?? config.network,
      localStorage:
          _storageOverride(results['storage'] as String?) ??
          config.localStorage,
      useAssetGenerator: config.useAssetGenerator,
      useEitherFailure: results.wasParsed('use-either-failure')
          ? results['use-either-failure'] == true
          : config.useEitherFailure,
      flutter: FlutterConfig(
        createPresentation: results.wasParsed('flutter-create')
            ? results['flutter-create'] == true
            : config.flutter.createPresentation,
        platforms:
            _platformsOverride(results['platforms'] as String?) ??
            config.flutter.platforms,
      ),
      dependencyInjection:
          _dependencyInjectionOverride(
            results['dependency-injection'] as String? ??
                results['di'] as String?,
          ) ??
          config.dependencyInjection,
      models: config.models,
      paths: config.paths,
    );
    overridden.validate();
    return overridden;
  }

  List<String>? _platformsOverride(String? value) {
    if (value == null) return null;
    return value
        .split(',')
        .map((platform) => platform.trim())
        .where((platform) => platform.isNotEmpty)
        .toList(growable: false);
  }

  bool _shouldRunFlutterCreate(
    List<String> args,
    CleanArchitectConfig config, {
    required bool skipPresentation,
    required OperationKind? operationKind,
  }) {
    if (skipPresentation || !config.flutter.createPresentation) return false;
    if (operationKind != null || args.isEmpty) return false;
    return switch (args.first) {
      'architecture' || 'base' || 'auth' || 'feature' => true,
      _ => false,
    };
  }

  GeneratedFile? _planFeatureDataModulePatch(
    List<String> args,
    CleanArchitectConfig config,
  ) {
    if (args.isEmpty) return null;
    if (config.structure == ProjectStructure.verticalPackages) return null;
    if (config.dependencyInjection != DependencyInjection.injectable) {
      return null;
    }
    if (config.localStorage != LocalStorage.hive &&
        config.localStorage != LocalStorage.objectbox) {
      return null;
    }

    final featureName = switch (args.first) {
      'auth' => 'auth',
      'feature' when args.length >= 2 => args[1],
      _ => null,
    };
    if (featureName == null || featureName.isEmpty) return null;

    final feature = NameCases(featureName);
    final dataRoot = _packageRoot(config.paths.data);
    final dataLib = p.join(dataRoot, 'lib');
    final modulePath = p.join(dataLib, 'data_module.dart');
    final moduleFile = File(modulePath);
    if (!moduleFile.existsSync()) return null;

    final boxClass = '${feature.pascal}Box';
    final methodName = '${feature.camel}Box';
    var content = moduleFile.readAsStringSync();
    if (content.contains(' $methodName(')) return null;

    final featureDataPath = PathResolver(config).resolve(feature.snake).data;
    final dataPaths = DataPaths.resolve(config, featureDataPath);
    final boxPath = p.join(dataPaths.localModels, '${feature.snake}_box.dart');
    final boxImportPath = p
        .relative(boxPath, from: dataLib)
        .split(p.separator)
        .join('/');

    final imports = <String>["import '$boxImportPath';"];
    final snippet = config.localStorage == LocalStorage.hive
        ? '''
  @lazySingleton
  @preResolve
  Future<Box<$boxClass>> $methodName() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(${stableHiveTypeId(feature.snake)})) {
      Hive.registerAdapter(${boxClass}Adapter());
    }
    return Hive.openBox<$boxClass>('${feature.snake}_box');
  }
'''
        : '''
  @lazySingleton
  Box<$boxClass> $methodName(Store store) => Box<$boxClass>(store);
''';

    content = _ensureImports(content, imports);
    content = _insertBeforeClassEnd(
      content,
      'abstract class DataModule',
      snippet,
    );
    return GeneratedFile(path: modulePath, content: content, allowUpdate: true);
  }

  GeneratedFile? _planVerticalAppPubspecPatch(
    List<String> args,
    CleanArchitectConfig config,
  ) {
    if (config.structure != ProjectStructure.verticalPackages || args.isEmpty) {
      return null;
    }
    final featureName = switch (args.first) {
      'auth' => 'auth',
      'feature' when args.length >= 2 => args[1],
      _ => null,
    };
    if (featureName == null) return null;

    final feature = NameCases(featureName);
    final appRoot = _packageRoot(config.paths.app);
    final appPubspec = File(p.join(appRoot, 'pubspec.yaml'));
    if (!appPubspec.existsSync()) return null;

    var content = appPubspec.readAsStringSync();
    final dependencyPattern = RegExp(
      '^  ${RegExp.escape(feature.snake)}:\\s*\$',
      multiLine: true,
    );
    if (dependencyPattern.hasMatch(content)) return null;

    final featureRoot = p.join(config.paths.features, feature.snake);
    final relativePath = p
        .relative(featureRoot, from: appRoot)
        .split(p.separator)
        .join('/');
    final dependency =
        '''
  ${feature.snake}:
    path: $relativePath
''';
    final devDependencies = content.indexOf('\ndev_dependencies:');
    if (devDependencies == -1) {
      throw const FormatException(
        'The vertical app pubspec has no dev_dependencies section.',
      );
    }
    content = content.replaceRange(
      devDependencies,
      devDependencies,
      dependency,
    );
    return GeneratedFile(
      path: appPubspec.path,
      content: content,
      allowUpdate: true,
    );
  }

  String _ensureImports(String content, List<String> imports) {
    var result = content;
    for (final import in imports.toSet()) {
      if (result.contains(import)) continue;
      final lastImport = RegExp(
        r'''import '[^']+';|import "[^"]+";''',
      ).allMatches(result).lastOrNull;
      if (lastImport == null) {
        result = '$import\n\n$result';
      } else {
        result = result.replaceRange(
          lastImport.end,
          lastImport.end,
          '\n$import',
        );
      }
    }
    return result;
  }

  String _insertBeforeClassEnd(
    String content,
    String classNeedle,
    String snippet,
  ) {
    final classIndex = content.indexOf(classNeedle);
    if (classIndex == -1) return _insertBeforeLastBrace(content, snippet);
    final openBrace = content.indexOf('{', classIndex);
    if (openBrace == -1) return _insertBeforeLastBrace(content, snippet);

    var depth = 0;
    for (var index = openBrace; index < content.length; index++) {
      final char = content[index];
      if (char == '{') depth++;
      if (char == '}') depth--;
      if (depth == 0) {
        return '${content.substring(0, index)}$snippet${content.substring(index)}';
      }
    }

    return _insertBeforeLastBrace(content, snippet);
  }

  String _insertBeforeLastBrace(String content, String snippet) {
    final index = content.lastIndexOf('}');
    if (index == -1) return '$content$snippet';
    return '${content.substring(0, index)}$snippet${content.substring(index)}';
  }

  void _runFlutterCreate(CleanArchitectConfig config, {required bool dryRun}) {
    final presentationRoot = _packageRoot(
      config.structure == ProjectStructure.verticalPackages
          ? config.paths.app
          : config.paths.presentation,
    );
    final platforms = config.flutter.platforms;
    final args = [
      'create',
      '.',
      if (platforms.isNotEmpty) '--platforms=${platforms.join(',')}',
    ];

    if (_flutterScaffoldExists(presentationRoot, platforms)) {
      if (!dryRun) _removeFlutterTemplateTest(presentationRoot);
      _logger.info('skip flutter create; requested platforms already exist');
      return;
    }

    if (dryRun) {
      _logger.info('run (cd $presentationRoot && flutter ${args.join(' ')})');
      return;
    }

    try {
      final result = Process.runSync(
        'flutter',
        args,
        workingDirectory: presentationRoot,
      );
      if (result.exitCode == 0) {
        _removeFlutterTemplateTest(presentationRoot);
        _logger.success('ran flutter ${args.join(' ')} in $presentationRoot');
        return;
      }

      _logger.warn('flutter create failed in $presentationRoot');
      if (result.stderr.toString().trim().isNotEmpty) {
        _logger.err(result.stderr.toString().trim());
      }
      exitCode = result.exitCode;
    } on ProcessException catch (error) {
      _logger.warn(
        'flutter executable not found. Install Flutter or run manually:',
      );
      _logger.info('cd $presentationRoot && flutter ${args.join(' ')}');
      _logger.detail(error.message);
    }
  }

  void _removeFlutterTemplateTest(String presentationRoot) {
    final file = File(p.join(presentationRoot, "test", "widget_test.dart"));
    if (!file.existsSync()) return;

    final content = file.readAsStringSync();
    final isStockFlutterTest =
        content.contains("Counter increments smoke test") &&
        content.contains("pumpWidget(const MyApp())");
    if (isStockFlutterTest) file.deleteSync();
  }

  bool _flutterScaffoldExists(String root, List<String> platforms) {
    if (!File(p.join(root, '.metadata')).existsSync()) return false;
    if (platforms.isEmpty) return true;

    final directories = {
      'android': 'android',
      'ios': 'ios',
      'web': 'web',
      'windows': 'windows',
      'macos': 'macos',
      'linux': 'linux',
    };
    return platforms.every(
      (platform) =>
          Directory(p.join(root, directories[platform]!)).existsSync(),
    );
  }

  String _packageRoot(String libPath) {
    final parts = p.split(p.normalize(libPath));
    final libIndex = parts.indexOf('lib');
    if (libIndex == -1) return libPath;
    return p.joinAll(parts.take(libIndex));
  }

  StateManagement? _stateOverride(String? value) {
    return switch (value) {
      'getx' => StateManagement.getx,
      'bloc' => StateManagement.bloc,
      'provider' => StateManagement.provider,
      'none' => StateManagement.none,
      _ => null,
    };
  }

  NetworkClient? _networkOverride(String? value) {
    return switch (value) {
      'dio' => NetworkClient.dio,
      'abstract' => NetworkClient.abstract,
      _ => null,
    };
  }

  LocalStorage? _storageOverride(String? value) {
    return switch (value) {
      'secure_storage' => LocalStorage.secureStorage,
      'shared_preferences' => LocalStorage.sharedPreferences,
      'hive' => LocalStorage.hive,
      'objectbox' => LocalStorage.objectbox,
      'abstract' => LocalStorage.abstract,
      _ => null,
    };
  }

  DependencyInjection? _dependencyInjectionOverride(String? value) {
    return switch (value) {
      'manual' => DependencyInjection.manual,
      'injectable' => DependencyInjection.injectable,
      _ => null,
    };
  }

  void _validateCreateSettings(
    ArgResults results,
    CleanArchitectConfig config,
    bool skipPresentation,
  ) {
    final dependencyInjection = results['dependency-injection'] as String?;
    final di = results['di'] as String?;
    if (results.wasParsed('dependency-injection') &&
        results.wasParsed('di') &&
        dependencyInjection != di) {
      throw const FormatException(
        '--dependency-injection and --di must use the same value.',
      );
    }
    if (results.wasParsed('platforms') && config.flutter.platforms.isEmpty) {
      throw const FormatException(
        '--platforms must include at least one platform.',
      );
    }
    if (results.wasParsed('platforms') && !config.flutter.createPresentation) {
      throw const FormatException(
        '--platforms requires Flutter creation. Add --flutter-create or '
        'set flutter.create_presentation: true.',
      );
    }
    if (skipPresentation && config.flutter.createPresentation) {
      throw const FormatException(
        '--skip-presentation cannot be combined with Flutter creation. '
        'Add --no-flutter-create.',
      );
    }
  }

  bool _featureGenerationComplete(
    CleanArchitectConfig config,
    String featureName, {
    required bool skipPresentation,
    required bool isAuth,
  }) {
    if (!_featureExists(config, featureName)) return false;
    if (skipPresentation) return true;

    final feature = NameCases(featureName);
    final paths = PathResolver(config).resolve(feature.snake);
    final pageName = isAuth ? 'login_page.dart' : '${feature.snake}_page.dart';
    return File(
          p.join(
            paths.presentation,
            'controllers',
            '${feature.snake}_controller.dart',
          ),
        ).existsSync() &&
        File(p.join(paths.presentation, 'pages', pageName)).existsSync();
  }

  bool _featureExists(CleanArchitectConfig config, String featureName) {
    final feature = NameCases(featureName);
    final paths = PathResolver(config).resolve(feature.snake);
    return File(
          p.join(
            paths.domain,
            'repositories',
            '${feature.snake}_repository.dart',
          ),
        ).existsSync() &&
        File(
          p.join(
            paths.data,
            'repositories',
            '${feature.snake}_repository_impl.dart',
          ),
        ).existsSync();
  }

  void _requireExistingFeature(
    CleanArchitectConfig config,
    String featureName,
  ) {
    final feature = NameCases(featureName);
    final paths = PathResolver(config).resolve(feature.snake);
    final requiredFiles = [
      p.join(paths.domain, 'repositories', '${feature.snake}_repository.dart'),
      p.join(
        paths.data,
        'repositories',
        '${feature.snake}_repository_impl.dart',
      ),
    ];
    final missing = requiredFiles
        .where((path) => !File(path).existsSync())
        .toList(growable: false);
    if (missing.isEmpty) return;

    throw FormatException(
      'Feature "${feature.snake}" does not exist. '
      'Run "clean_architect create feature ${feature.snake}" first.',
    );
  }

  void _validateName(String label, String value) {
    final valid = RegExp(r'^[A-Za-z][A-Za-z0-9]*(?:[_-][A-Za-z0-9]+)*$');
    const reserved = {
      'abstract',
      'as',
      'assert',
      'async',
      'await',
      'break',
      'case',
      'catch',
      'class',
      'const',
      'continue',
      'default',
      'deferred',
      'do',
      'dynamic',
      'else',
      'enum',
      'export',
      'extends',
      'extension',
      'external',
      'factory',
      'false',
      'final',
      'finally',
      'for',
      'function',
      'get',
      'hide',
      'if',
      'implements',
      'import',
      'in',
      'interface',
      'is',
      'late',
      'library',
      'mixin',
      'new',
      'null',
      'of',
      'on',
      'operator',
      'part',
      'required',
      'rethrow',
      'return',
      'sealed',
      'set',
      'show',
      'static',
      'super',
      'switch',
      'sync',
      'this',
      'throw',
      'true',
      'try',
      'typedef',
      'var',
      'void',
      'when',
      'while',
      'with',
      'yield',
    };
    if (!valid.hasMatch(value) || reserved.contains(value.toLowerCase())) {
      throw FormatException(
        '$label name "$value" is invalid. Use letters, numbers, "_" or "-", '
        'starting with a letter.',
      );
    }
  }

  void _validateVerticalFeaturePackageName(
    CleanArchitectConfig config,
    String value,
  ) {
    if (config.structure != ProjectStructure.verticalPackages) return;
    final featureName = NameCases(value).snake;
    final reservedPackageNames = {
      p.basename(_packageRoot(config.paths.app)),
      p.basename(_packageRoot(config.paths.core)),
    };
    if (reservedPackageNames.contains(featureName)) {
      throw FormatException(
        'Feature "$featureName" conflicts with a vertical app or core '
        'package name.',
      );
    }
  }

  bool _hasArgumentCount(List<String> args, int count, String usage) {
    if (args.length == count) return true;
    _logger.err('Usage: $usage');
    return false;
  }

  void _usageError(String message, String usage) {
    _logger.err(message);
    _logger.info(usage);
    exitCode = 64;
  }

  String _rootHelp(ArgParser parser) {
    return '''
clean_architect $packageVersion

Usage: clean_architect <command> [arguments]

Commands:
  init      Create clean_architect.yaml.
  create    Generate architecture, features, or feature operations.
  scan      Detect architecture and optionally update configuration.
  doctor    Validate configuration and generated packages.

Global options:
  -h, --help       Show help.
      --version    Show the installed version.

${parser.usage}
''';
  }

  String _commandHelp(String command, List<String> rest) {
    if (command == 'init') {
      return '''
Usage: clean_architect init [options]

Creates clean_architect.yaml in the current directory.

Options:
  -f, --force      Replace an existing config.
      --dry-run    Print the planned change.
  -h, --help       Show this help.
''';
    }
    if (command == 'doctor') {
      return '''
Usage: clean_architect doctor

Validates layer pubspecs, dependencies, tools, package roots, and generated files.
''';
    }
    if (command == 'scan') {
      return '''
Usage: clean_architect scan [options]

Detects package roles, architecture paths, and supported configuration from an
existing Flutter or Dart project. Scanning is read-only unless --write is used.

Options:
      --write          Create or update clean_architect.yaml.
  -f, --force          Accept medium-confidence structural detections.
      --json           Print the structured scan result as JSON.
      --root <path>    Project root to inspect. Defaults to the current folder.
  -h, --help           Show this help.
''';
    }

    final target = rest.isEmpty ? null : rest.first;
    final usage = switch (target) {
      'architecture' ||
      'base' => 'clean_architect create architecture [options]',
      'auth' => 'clean_architect create auth [options]',
      'feature' => 'clean_architect create feature <name> [options]',
      'usecase' =>
        'clean_architect create usecase <name> --feature <feature> [options]',
      'repository' => 'clean_architect create repository <feature> [options]',
      'remote-function' || 'remote-method' =>
        'clean_architect create remote-function <name> --feature <feature> [options]',
      'local-function' || 'local-method' =>
        'clean_architect create local-function <name> --feature <feature> [options]',
      'cached-function' || 'cached-method' =>
        'clean_architect create cached-function <name> --feature <feature> [options]',
      _ => 'clean_architect create <target> [options]',
    };
    return '''
Usage: $usage

Targets:
  architecture                 Create the configured clean architecture.
  auth                         Create the auth feature.
  feature <name>               Create a generic feature.
  usecase <name>               Add a standalone use case.
  repository <feature>         Add a repository pair.
  remote-function <name>       Add a remote operation to an existing feature.
  local-function <name>        Add a local operation to an existing feature.
  cached-function <name>       Add remote sync and local stream operations.

Common options:
      --feature <name>          Existing feature for operation commands.
      --dry-run                 Print the complete plan without writing.
      --force, --overwrite      Replace conflicting generated files.
      --skip-presentation       Do not generate presentation files.
      --[no-]flutter-create     Enable or disable Flutter platform generation.
      --platforms <list>        Comma-separated Flutter platforms.
      --state <value>           getx, bloc, provider, or none.
      --network <value>         dio or abstract.
      --storage <value>         secure_storage, shared_preferences, hive,
                                objectbox, or abstract.
  -d, --dependency-injection   manual or injectable.
      --[no-]use-either-failure
  -h, --help                   Show this help.
''';
  }

  void _doctor() {
    final configFile = File(CleanArchitectConfig.fileName);
    if (!configFile.existsSync()) {
      _logger.err('clean_architect.yaml not found. Run clean_architect init.');
      exitCode = 1;
      return;
    }

    final config = CleanArchitectConfig.fromFile(configFile);
    final report = ProjectDoctor(config: config).run();
    for (final diagnostic in report.diagnostics) {
      switch (diagnostic.level) {
        case DoctorLevel.success:
          _logger.success(diagnostic.message);
        case DoctorLevel.warning:
          _logger.warn(diagnostic.message);
        case DoctorLevel.error:
          _logger.err(diagnostic.message);
      }
    }
    if (report.hasErrors) exitCode = 1;
  }

  void _scan(ArgResults results) {
    final rootValue = results['root'] as String;
    final root = p.normalize(p.absolute(rootValue));
    final result = ProjectScanner(projectRoot: root).scan();
    final json = results['json'] == true;

    if (json) {
      _logger.info(result.toPrettyJson());
    } else {
      _printScanResult(result, showWriteHint: results['write'] != true);
    }

    if (results['write'] != true) {
      if (result.config == null) exitCode = 1;
      return;
    }
    if (!result.canWrite || result.config == null) {
      _logger.err(
        'The scan did not identify a complete writable architecture.',
      );
      exitCode = 1;
      return;
    }
    if (result.requiresForce && results['force'] != true) {
      _logger.err(
        'Some structural paths have medium confidence. Review the report and '
        'rerun with --force to write them.',
      );
      exitCode = 1;
      return;
    }

    final target = File(p.join(root, CleanArchitectConfig.fileName));
    final existed = target.existsSync();
    const ScanConfigWriter().write(result, target);
    if (!json) {
      _logger.success('${existed ? 'updated' : 'created'} ${target.path}');
    }
  }

  void _printScanResult(
    ProjectScanResult result, {
    required bool showWriteHint,
  }) {
    final config = result.config;
    if (config != null) {
      _logger.info('Detected architecture: ${config.structureName}');
      _logger.info('Confidence: ${result.confidence.name}');
      _logger.info('');
      _logger.info('Paths:');
      final pathKeys = result.findings.keys.where(
        (key) => key.startsWith('paths.'),
      );
      for (final key in pathKeys) {
        final finding = result.findings[key]!;
        _logger.info(
          '  ${key.substring('paths.'.length)}: ${finding.value} '
          '(${finding.confidence.name})',
        );
      }
      _logger.info('');
      _logger.info('Options:');
      for (final key in result.findings.keys.where(
        (key) => !key.startsWith('paths.'),
      )) {
        final finding = result.findings[key]!;
        _logger.info('  $key: ${finding.value}');
      }
    }

    for (final diagnostic in result.diagnostics) {
      switch (diagnostic.level) {
        case ScanDiagnosticLevel.info:
          _logger.info(diagnostic.message);
        case ScanDiagnosticLevel.warning:
          _logger.warn(diagnostic.message);
        case ScanDiagnosticLevel.error:
          _logger.err(diagnostic.message);
      }
    }
    if (config != null && showWriteHint) {
      _logger.info('');
      _logger.info(
        result.requiresForce
            ? 'Review medium-confidence paths, then run clean_architect scan --write --force.'
            : 'Run clean_architect scan --write to apply this configuration.',
      );
    }
  }
}
