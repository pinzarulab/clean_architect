import 'package:path/path.dart' as p;

import '../case_utils.dart';
import '../config.dart';
import '../data_paths.dart';
import '../generated_file.dart';
import '../generator.dart';

const _sdkConstraint = '^3.11.0';
const _flutterConstraint = '>=3.27.0';
const _buildRunnerVersion = '^2.15.1';
const _freezedVersion = '^3.2.5';
const _freezedAnnotationVersion = '^3.1.0';
const _jsonAnnotationVersion = '^4.12.0';
const _jsonSerializableVersion = '^6.14.0';
const _injectableVersion = '^3.0.0';
const _injectableGeneratorVersion = '^3.0.2';
const _getItVersion = '^9.2.1';

List<GeneratedFile> packageTemplates(
  TemplateContext context, {
  required bool includePresentation,
  bool includeDataModule = true,
}) {
  if (context.config.structure == ProjectStructure.verticalPackages) {
    return _verticalPackageTemplates(
      context,
      includePresentation: includePresentation,
      includeDataModule: includeDataModule,
    );
  }

  final files = <GeneratedFile>[
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.domain), 'pubspec.yaml'),
      content: _domainPubspec(context),
    ),
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.data), 'pubspec.yaml'),
      content: _dataPubspec(context),
    ),
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.di), 'pubspec.yaml'),
      content: _diPubspec(context),
    ),
    ..._dependencyInjectionFiles(context, includeFeature: includeDataModule),
    if (includeDataModule) ..._dataModuleFiles(context),
  ];

  if (includePresentation) {
    files.addAll([
      GeneratedFile(
        path: p.join(_packageRoot(context.paths.presentation), 'pubspec.yaml'),
        content: _presentationPubspec(context),
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'assets',
          'images',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'assets',
          'icons',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'lib',
          'main.dart',
        ),
        content: _presentationMain(),
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'lib',
          'widgets',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'lib',
          'pages',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'lib',
          'utils',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'lib',
          'controllers',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'lib',
          'constants',
          '.gitkeep',
        ),
        content: '',
      ),
      GeneratedFile(
        path: p.join(
          _packageRoot(context.paths.presentation),
          'analysis_options.yaml',
        ),
        content: '''
include: package:flutter_lints/flutter.yaml
''',
      ),
    ]);
    if (context.config.useAssetGenerator) {
      files.add(
        GeneratedFile(
          path: p.join(
            _packageRoot(context.paths.presentation),
            'asset_generator_kit.yaml',
          ),
          content: _assetGeneratorKit(),
        ),
      );
    }
  }

  return files
      .map(
        (file) => GeneratedFile(
          path: file.path,
          content: file.content,
          skipIfExists: true,
        ),
      )
      .toList(growable: false);
}

List<GeneratedFile> _verticalPackageTemplates(
  TemplateContext context, {
  required bool includePresentation,
  required bool includeDataModule,
}) {
  final appRoot = _packageRoot(context.config.paths.app);
  final coreRoot = _packageRoot(context.config.paths.core);
  final featureRoot = _packageRoot(context.paths.domain);
  final featureLibrary = p.join(
    featureRoot,
    'lib',
    '${context.cases.snake}.dart',
  );
  final files = <GeneratedFile>[
    GeneratedFile(path: '.gitignore', content: _verticalGitignore()),
    GeneratedFile(
      path: 'ARCHITECTURE.md',
      content: _verticalArchitecture(context),
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'pubspec.yaml'),
      content: _verticalCorePubspec(context),
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'analysis_options.yaml'),
      content: 'include: package:lints/recommended.yaml\n',
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'lib', 'core.dart'),
      content: _verticalCoreLibrary(),
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'lib', 'src', 'failures', 'failure.dart'),
      content: _verticalFailure(),
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'lib', 'src', 'errors', 'app_exception.dart'),
      content: _verticalAppException(),
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'lib', 'src', 'usecases', 'use_case.dart'),
      content: _verticalUseCase(),
    ),
    GeneratedFile(
      path: p.join(coreRoot, 'lib', 'src', 'logging', 'app_logger.dart'),
      content: _verticalAppLogger(),
    ),
    GeneratedFile(
      path: p.join(featureRoot, 'pubspec.yaml'),
      content: _verticalFeaturePubspec(
        context,
        includePresentation: includePresentation,
      ),
    ),
    GeneratedFile(
      path: p.join(featureRoot, 'analysis_options.yaml'),
      content:
          includePresentation ||
              context.config.localStorage != LocalStorage.abstract
          ? 'include: package:flutter_lints/flutter.yaml\n'
          : 'include: package:lints/recommended.yaml\n',
    ),
    GeneratedFile(
      path: featureLibrary,
      content: _verticalFeatureLibrary(context),
    ),
    if (context.config.dependencyInjection == DependencyInjection.injectable)
      ..._verticalInjectableFiles(
        context,
        hasPreResolvedDependencies:
            includeDataModule &&
            (context.config.localStorage == LocalStorage.hive ||
                context.config.localStorage == LocalStorage.objectbox ||
                context.config.localStorage == LocalStorage.sharedPreferences),
      ),
    if (includeDataModule) ..._verticalDataModuleFiles(context),
  ];

  if (includePresentation) {
    files.addAll([
      GeneratedFile(
        path: p.join(appRoot, 'pubspec.yaml'),
        content: _verticalAppPubspec(context),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'analysis_options.yaml'),
        content: 'include: package:flutter_lints/flutter.yaml\n',
      ),
      GeneratedFile(
        path: p.join(appRoot, 'assets', 'images', '.gitkeep'),
        content: '',
      ),
      GeneratedFile(
        path: p.join(appRoot, 'assets', 'icons', '.gitkeep'),
        content: '',
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'main.dart'),
        content: _verticalMain(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'app.dart'),
        content: _verticalApp(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'routing', 'app_router.dart'),
        content: _verticalAppRouter(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'theme', 'app_theme.dart'),
        content: _verticalAppTheme(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'pages', 'home_page.dart'),
        content: _verticalHomePage(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'widgets', 'architecture_summary.dart'),
        content: _verticalArchitectureSummary(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'di', 'bootstrap.dart'),
        content: _verticalBootstrap(context, includeFeature: includeDataModule),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'constants', 'app_constants.dart'),
        content: _verticalAppConstants(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'utils', 'context_extensions.dart'),
        content: _verticalContextExtensions(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'lib', 'controllers', 'app_controller.dart'),
        content: _verticalAppController(),
      ),
      GeneratedFile(
        path: p.join(appRoot, 'test', 'app_smoke_test.dart'),
        content: _verticalAppTest(context),
      ),
      if (context.config.useAssetGenerator)
        GeneratedFile(
          path: p.join(appRoot, 'asset_generator_kit.yaml'),
          content: _assetGeneratorKit(),
        ),
    ]);
  }

  return files
      .map(
        (file) => GeneratedFile(
          path: file.path,
          content: file.content,
          skipIfExists: true,
        ),
      )
      .toList(growable: false);
}

String _verticalGitignore() {
  return '''
.dart_tool/
.idea/
.packages
build/
coverage/
**/*.g.dart
**/*.freezed.dart
''';
}

String _verticalArchitecture(TemplateContext context) {
  final appRoot = _packageRoot(context.config.paths.app);
  final coreRoot = _packageRoot(context.config.paths.core);
  final featuresRoot = context.config.paths.features;
  return '''
# Vertical Packages Architecture

The Flutter application lives in `$appRoot/`. Shared, feature-independent code
lives in `$coreRoot/`. Every business feature is an independently analyzable
package below `$featuresRoot/` and owns its domain, data, presentation, and
dependency-injection code under `lib/src/`.

Feature data files use the `${context.config.dataLayoutName}` layout selected
in `clean_architect.yaml`.

Dependency direction:

1. The app may depend on core and feature packages.
2. Feature presentation depends on its own domain use cases.
3. Feature data implements its own domain repository contracts.
4. A feature may depend on core, but features must not import one another.
5. Core must not depend on the app or any feature.

Run the project:

```sh
cd $appRoot
flutter pub get
flutter run
```

Generate code in a feature package when Freezed, Retrofit, Injectable, Hive, or
ObjectBox is enabled:

```sh
cd $featuresRoot/<feature>
dart run build_runner build --delete-conflicting-outputs
```
''';
}

String _verticalCorePubspec(TemplateContext context) {
  return '''
name: ${_packageName(context.config.paths.core)}
description: Shared application primitives generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint

dependencies:
  meta: ^1.18.0

dev_dependencies:
  lints: ^6.1.0
''';
}

String _verticalCoreLibrary() {
  return '''
export 'src/errors/app_exception.dart';
export 'src/failures/failure.dart';
export 'src/logging/app_logger.dart';
export 'src/usecases/use_case.dart';
''';
}

String _verticalFailure() {
  return '''
import 'package:meta/meta.dart';

@immutable
class Failure {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause});
}

final class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause});
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause});
}
''';
}

String _verticalAppException() {
  return '''
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException: \$message';
}
''';
}

String _verticalUseCase() {
  return '''
abstract interface class UseCase<Result, Params> {
  Future<Result> call(Params params);
}

final class NoParams {
  const NoParams();
}
''';
}

String _verticalAppLogger() {
  return '''
abstract interface class AppLogger {
  void debug(String message);

  void error(String message, {Object? error, StackTrace? stackTrace});
}
''';
}

String _verticalFeaturePubspec(
  TemplateContext context, {
  required bool includePresentation,
}) {
  final requiresFlutter =
      includePresentation ||
      context.config.localStorage != LocalStorage.abstract;
  final requiresBuildRunner =
      context.config.network == NetworkClient.dio ||
      context.config.models.useFreezed ||
      context.config.models.useJsonSerializable ||
      context.config.dependencyInjection == DependencyInjection.injectable ||
      context.config.localStorage == LocalStorage.hive ||
      context.config.localStorage == LocalStorage.objectbox;
  final featureRoot = _packageRoot(context.paths.domain);
  final coreRoot = _packageRoot(context.config.paths.core);
  final corePath = p.relative(coreRoot, from: featureRoot);
  final dependencies = <String>[
    if (requiresFlutter) '  flutter:\n    sdk: flutter',
    '  ${_packageName(context.config.paths.core)}:',
    '    path: ${p.posix.normalize(corePath.split(p.separator).join('/'))}',
    if (includePresentation) '  get_it: $_getItVersion',
  ];
  final devDependencies = <String>[
    if (requiresFlutter) '  flutter_test:\n    sdk: flutter',
    if (requiresFlutter) '  flutter_lints: ^6.0.0' else '  lints: ^6.1.0',
  ];

  if (context.config.useEitherFailure) {
    dependencies.add('  dartz: ^0.10.1');
  }
  if (context.config.network == NetworkClient.dio) {
    dependencies.add('  dio: ^5.10.0');
    dependencies.add('  retrofit: ^4.9.2');
    devDependencies.add('  retrofit_generator: ^10.2.8');
  }
  if (context.config.dependencyInjection == DependencyInjection.injectable) {
    dependencies.add('  injectable: $_injectableVersion');
    dependencies.add('  get_it: $_getItVersion');
    devDependencies.add('  injectable_generator: $_injectableGeneratorVersion');
  }
  if (context.config.localStorage == LocalStorage.secureStorage) {
    dependencies.add('  flutter_secure_storage: ^10.3.1');
  }
  if (context.config.localStorage == LocalStorage.sharedPreferences) {
    dependencies.add('  shared_preferences: ^2.5.5');
  }
  if (context.config.localStorage == LocalStorage.hive) {
    dependencies.add('  hive_ce: ^2.19.3');
    dependencies.add('  hive_ce_flutter: ^2.3.4');
    devDependencies.add('  hive_ce_generator: 1.11.1');
  }
  if (context.config.localStorage == LocalStorage.objectbox) {
    dependencies.add('  objectbox: ^5.3.2');
    dependencies.add('  objectbox_flutter_libs: ^5.3.2');
    dependencies.add('  path_provider: ^2.1.6');
    devDependencies.add('  objectbox_generator: ^5.3.2');
  }
  if (context.config.models.useFreezed) {
    dependencies.add('  freezed_annotation: $_freezedAnnotationVersion');
    devDependencies.add('  freezed: $_freezedVersion');
  }
  if (context.config.models.useJsonSerializable) {
    dependencies.add('  json_annotation: $_jsonAnnotationVersion');
    devDependencies.add('  json_serializable: $_jsonSerializableVersion');
  }
  if (includePresentation &&
      context.config.stateManagement == StateManagement.getx) {
    dependencies.add('  get: ^4.7.3');
  }
  if (includePresentation &&
      context.config.stateManagement == StateManagement.bloc) {
    dependencies.add('  flutter_bloc: ^9.1.1');
    dependencies.add('  equatable: ^2.1.0');
  }
  if (includePresentation &&
      context.config.stateManagement == StateManagement.provider) {
    dependencies.add('  provider: ^6.1.5+1');
  }
  if (requiresBuildRunner) {
    devDependencies.add('  build_runner: $_buildRunnerVersion');
  }

  return '''
name: ${context.cases.snake}
description: ${context.cases.title} vertical feature package generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint
${requiresFlutter ? "  flutter: '$_flutterConstraint'\n" : ''}
dependencies:
${dependencies.toSet().join('\n')}

dev_dependencies:
${devDependencies.toSet().join('\n')}
''';
}

String _verticalFeatureLibrary(TemplateContext context) {
  return '''
/// Public entry point for the ${context.cases.title} feature.
///
/// Export stable feature-facing APIs here as the feature evolves. Internal
/// implementation remains below `lib/src`.
library;
''';
}

List<GeneratedFile> _verticalInjectableFiles(
  TemplateContext context, {
  required bool hasPreResolvedDependencies,
}) {
  final returnType = hasPreResolvedDependencies ? 'Future<void>' : 'void';
  final asyncKeyword = hasPreResolvedDependencies ? ' async' : '';
  final initCall = hasPreResolvedDependencies
      ? '  await getIt.init();'
      : '  getIt.init();';
  return [
    GeneratedFile(
      path: p.join(context.paths.di, 'injector.dart'),
      content:
          '''
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injector.config.dart';

@InjectableInit()
$returnType configure${context.cases.pascal}Dependencies(GetIt getIt)$asyncKeyword {
$initCall
}
''',
    ),
  ];
}

List<GeneratedFile> _verticalDataModuleFiles(TemplateContext context) {
  if (context.config.dependencyInjection != DependencyInjection.injectable) {
    return const [];
  }
  if (context.config.network != NetworkClient.dio &&
      context.config.localStorage != LocalStorage.hive &&
      context.config.localStorage != LocalStorage.objectbox &&
      context.config.localStorage != LocalStorage.sharedPreferences) {
    return const [];
  }
  return [
    GeneratedFile(
      path: p.join(context.paths.di, 'data_module.dart'),
      content: _verticalDataModule(context),
    ),
  ];
}

String _verticalDataModule(TemplateContext context) {
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final boxImport = relativeDartImport(
    fromDirectory: context.paths.di,
    targetPath: p.join(
      dataPaths.localModels,
      '${context.cases.snake}_box.dart',
    ),
  );
  final imports = <String>[
    "import 'package:injectable/injectable.dart';",
    if (context.config.network == NetworkClient.dio)
      "import 'package:dio/dio.dart';",
    if (context.config.localStorage == LocalStorage.hive)
      "import 'package:hive_ce_flutter/hive_flutter.dart';",
    if (context.config.localStorage == LocalStorage.objectbox)
      "import 'package:path/path.dart' as p;",
    if (context.config.localStorage == LocalStorage.objectbox)
      "import 'package:path_provider/path_provider.dart';",
    if (context.config.localStorage == LocalStorage.sharedPreferences)
      "import 'package:shared_preferences/shared_preferences.dart';",
    if (context.config.localStorage == LocalStorage.hive ||
        context.config.localStorage == LocalStorage.objectbox)
      "import '$boxImport';",
    if (context.config.localStorage == LocalStorage.objectbox)
      "import '../../objectbox.g.dart';",
  ];
  final body = <String>[
    if (context.config.network == NetworkClient.dio) _dioProviders(),
    if (context.config.localStorage == LocalStorage.sharedPreferences)
      _sharedPreferencesProvider(),
    if (context.config.localStorage == LocalStorage.hive)
      _hiveProviders(context),
    if (context.config.localStorage == LocalStorage.objectbox)
      _objectBoxProviders(context),
  ].where((item) => item.trim().isNotEmpty).join('\n');

  return '''
${imports.toSet().join('\n')}

@module
abstract class DataModule {
$body
}
''';
}

String _verticalAppPubspec(TemplateContext context) {
  final appRoot = _packageRoot(context.config.paths.app);
  final coreRoot = _packageRoot(context.config.paths.core);
  final featureRoot = _packageRoot(context.paths.domain);
  final corePath = p.relative(coreRoot, from: appRoot);
  final featurePath = p.relative(featureRoot, from: appRoot);
  final devDependencies = <String>[
    '  flutter_test:\n    sdk: flutter',
    '  flutter_lints: ^6.0.0',
    if (context.config.useAssetGenerator)
      '  build_runner: $_buildRunnerVersion',
    if (context.config.useAssetGenerator) '  assets_generator_kit: ^0.1.0',
  ];
  return '''
name: ${_packageName(context.config.paths.app)}
description: Flutter application generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint
  flutter: '$_flutterConstraint'

dependencies:
  flutter:
    sdk: flutter
  get_it: $_getItVersion
  ${_packageName(context.config.paths.core)}:
    path: ${p.posix.normalize(corePath.split(p.separator).join('/'))}
  ${context.cases.snake}:
    path: ${p.posix.normalize(featurePath.split(p.separator).join('/'))}

dev_dependencies:
${devDependencies.join('\n')}

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
''';
}

String _verticalMain() {
  return '''
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'di/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();
  runApp(const App());
}
''';
}

String _verticalApp() {
  return '''
import 'package:flutter/material.dart';

import 'constants/app_constants.dart';
import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRouter.home,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
''';
}

String _verticalAppRouter() {
  return '''
import 'package:flutter/material.dart';

import '../pages/home_page.dart';

abstract final class AppRouter {
  static const home = '/';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const HomePage(),
    );
  }
}
''';
}

String _verticalAppTheme() {
  return '''
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF166534)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F5),
      useMaterial3: true,
    );
  }
}
''';
}

String _verticalHomePage() {
  return '''
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../widgets/architecture_summary.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
      body: const SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ArchitectureSummary(),
          ),
        ),
      ),
    );
  }
}
''';
}

String _verticalArchitectureSummary() {
  return '''
import 'package:flutter/material.dart';

class ArchitectureSummary extends StatelessWidget {
  const ArchitectureSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ready to build', style: textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'The app shell, shared core, and vertical feature packages are configured.',
            style: textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          const _ArchitectureRow(
            icon: Icons.phone_android,
            title: 'App',
            detail: 'Composition, routing, theme, and platform entry point',
          ),
          const _ArchitectureRow(
            icon: Icons.hub_outlined,
            title: 'Core',
            detail: 'Stable primitives shared by independent features',
          ),
          const _ArchitectureRow(
            icon: Icons.view_module_outlined,
            title: 'Features',
            detail: 'Domain, data, presentation, and DI owned together',
          ),
        ],
      ),
    );
  }
}

class _ArchitectureRow extends StatelessWidget {
  const _ArchitectureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
''';
}

String _verticalBootstrap(
  TemplateContext context, {
  required bool includeFeature,
}) {
  final manual =
      context.config.dependencyInjection == DependencyInjection.manual;
  final featureImport = manual && includeFeature
      ? "import 'package:${context.cases.snake}/${context.cases.snake}.dart';\n"
      : '';
  final featureData = manual && includeFeature
      ? '  await init${context.cases.pascal}Data(get);\n'
      : '';
  final featureDomain = manual && includeFeature
      ? '  init${context.cases.pascal}Domain(get);\n'
      : '';
  return '''
${manual ? "import 'package:get_it/get_it.dart';\n$featureImport" : ''}
Future<void> bootstrap() async {
${manual ? '  final get = GetIt.instance;\n$featureData  // clean_architect:data-registrations\n\n$featureDomain  // clean_architect:domain-registrations' : '  // Injectable feature containers initialize themselves when configured.'}
}
''';
}

String _verticalAppConstants() {
  return '''
abstract final class AppConstants {
  static const appName = 'Clean Architect';
}
''';
}

String _verticalContextExtensions() {
  return '''
import 'package:flutter/material.dart';

extension BuildContextX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;

  TextTheme get textStyles => Theme.of(this).textTheme;
}
''';
}

String _verticalAppController() {
  return '''
import 'package:flutter/material.dart';

class AppController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
  }
}
''';
}

String _verticalAppTest(TemplateContext context) {
  return '''
import 'package:flutter_test/flutter_test.dart';

import 'package:${_packageName(context.config.paths.app)}/app.dart';

void main() {
  testWidgets('renders the architecture shell', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Ready to build'), findsOneWidget);
  });
}
''';
}

List<GeneratedFile> _dataModuleFiles(TemplateContext context) {
  if (context.config.dependencyInjection != DependencyInjection.injectable) {
    return const [];
  }
  if (context.config.network != NetworkClient.dio &&
      context.config.localStorage != LocalStorage.hive &&
      context.config.localStorage != LocalStorage.objectbox &&
      context.config.localStorage != LocalStorage.sharedPreferences) {
    return const [];
  }

  return [
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.data), 'lib', 'data_module.dart'),
      content: _dataModule(context),
    ),
  ];
}

String _dataModule(TemplateContext context) {
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final dataLib = p.join(_packageRoot(context.paths.data), 'lib');
  final boxImport = relativeDartImport(
    fromDirectory: dataLib,
    targetPath: p.join(
      dataPaths.localModels,
      '${context.cases.snake}_box.dart',
    ),
  );
  final imports = <String>[
    "import 'package:injectable/injectable.dart';",
    if (context.config.network == NetworkClient.dio)
      "import 'package:dio/dio.dart';",
    if (context.config.localStorage == LocalStorage.hive)
      "import 'package:hive_ce_flutter/hive_flutter.dart';",
    if (context.config.localStorage == LocalStorage.objectbox)
      "import 'package:path/path.dart' as p;",
    if (context.config.localStorage == LocalStorage.objectbox)
      "import 'package:path_provider/path_provider.dart';",
    if (context.config.localStorage == LocalStorage.sharedPreferences)
      "import 'package:shared_preferences/shared_preferences.dart';",
    if (context.config.localStorage == LocalStorage.hive ||
        context.config.localStorage == LocalStorage.objectbox)
      "import '$boxImport';",
    if (context.config.localStorage == LocalStorage.objectbox)
      "import 'objectbox.g.dart';",
  ];
  final body = <String>[
    if (context.config.network == NetworkClient.dio) _dioProviders(),
    if (context.config.localStorage == LocalStorage.sharedPreferences)
      _sharedPreferencesProvider(),
    if (context.config.localStorage == LocalStorage.hive)
      _hiveProviders(context),
    if (context.config.localStorage == LocalStorage.objectbox)
      _objectBoxProviders(context),
  ].where((item) => item.trim().isNotEmpty).join('\n');

  return '''
${imports.toSet().join('\n')}

@module
abstract class DataModule {
$body
}
''';
}

String _dioProviders() {
  return '''
  @Named('auth_dio')
  @lazySingleton
  Dio authDio() {
    return Dio(BaseOptions(baseUrl: ''));
  }

  @Named('main_dio')
  @lazySingleton
  Dio mainDio() {
    return Dio(BaseOptions(baseUrl: ''));
  }
''';
}

String _sharedPreferencesProvider() {
  return '''
  @lazySingleton
  @preResolve
  Future<SharedPreferences> sharedPreferences() {
    return SharedPreferences.getInstance();
  }
''';
}

String _hiveProviders(TemplateContext context) {
  final boxClass = '${context.cases.pascal}Box';
  final boxName = '${context.cases.camel}Box';
  final typeId = stableHiveTypeId(context.cases.snake);
  return '''
  @lazySingleton
  @preResolve
  Future<Box<$boxClass>> $boxName() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered($typeId)) {
      Hive.registerAdapter(${boxClass}Adapter());
    }
    return Hive.openBox<$boxClass>('${context.cases.snake}_box');
  }
''';
}

String _objectBoxProviders(TemplateContext context) {
  final boxClass = '${context.cases.pascal}Box';
  final boxName = '${context.cases.camel}Box';
  return '''
  @lazySingleton
  @factoryMethod
  @preResolve
  Future<Store> asyncCreateStore() async {
    final directory = await getApplicationDocumentsDirectory();
    return openStore(directory: p.join(directory.path, 'objectbox'));
  }

  @lazySingleton
  Box<$boxClass> $boxName(Store store) => Box<$boxClass>(store);
''';
}

List<GeneratedFile> _dependencyInjectionFiles(
  TemplateContext context, {
  required bool includeFeature,
}) {
  if (context.config.dependencyInjection == DependencyInjection.manual) {
    if (context.config.structure == ProjectStructure.verticalPackages) {
      return const [];
    }
    final feature = context.cases;
    final featureImport = includeFeature
        ? "import '${feature.snake}_di.dart';\n"
        : '';
    final dataRegistration = includeFeature
        ? '  await init${feature.pascal}Data(get);\n'
        : '';
    final domainRegistration = includeFeature
        ? '  init${feature.pascal}Domain(get);\n'
        : '';
    return [
      GeneratedFile(
        path: p.join(_packageRoot(context.paths.di), 'lib', 'di.dart'),
        content:
            '''
import 'package:get_it/get_it.dart';

$featureImport
Future<void> initDi({required GetIt get}) async {
$dataRegistration
  // clean_architect:data-registrations

$domainRegistration
  // clean_architect:domain-registrations
}
''',
      ),
    ];
  }

  return [
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.domain), 'lib', 'injector.dart'),
      content: '''
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injector.config.dart';

@InjectableInit()
void configureDependencies(GetIt get) => get.init();
''',
    ),
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.data), 'lib', 'injector.dart'),
      content: '''
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injector.config.dart';

@InjectableInit()
Future<void> configureDependencies(GetIt get) async {
  await get.init();
}
''',
    ),
    GeneratedFile(
      path: p.join(_packageRoot(context.paths.di), 'lib', 'di.dart'),
      content: '''
import 'package:data/injector.dart' as data;
import 'package:domain/injector.dart' as domain;
import 'package:get_it/get_it.dart';

Future<void> initDi({required GetIt get}) async {
  await data.configureDependencies(get);
  domain.configureDependencies(get);
}
''',
    ),
  ];
}

String _domainPubspec(TemplateContext context) {
  final dependencies = <String>[];
  final devDependencies = <String>[];
  if (context.config.useEitherFailure) {
    dependencies.add('  dartz: ^0.10.1');
  }
  if (context.config.models.useFreezed) {
    dependencies.add('  freezed_annotation: $_freezedAnnotationVersion');
    devDependencies.add('  build_runner: $_buildRunnerVersion');
    devDependencies.add('  freezed: $_freezedVersion');
  }
  if (context.config.dependencyInjection == DependencyInjection.injectable) {
    dependencies.add('  injectable: $_injectableVersion');
    dependencies.add('  get_it: $_getItVersion');
    devDependencies.add('  build_runner: $_buildRunnerVersion');
    devDependencies.add('  injectable_generator: $_injectableGeneratorVersion');
  }

  return '''
name: ${_packageName(context.paths.domain)}
description: Domain layer generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint
${_section('dependencies', dependencies)}${_section('dev_dependencies', devDependencies)}''';
}

String _dataPubspec(TemplateContext context) {
  final dependencies = <String>[
    "  ${_packageName(context.paths.domain)}:",
    '    path: ../${_packageName(context.paths.domain)}',
  ];
  final devDependencies = <String>[];
  final requiresFlutter = context.config.localStorage != LocalStorage.abstract;
  final requiresBuildRunner =
      context.config.network == NetworkClient.dio ||
      context.config.models.useFreezed ||
      context.config.models.useJsonSerializable ||
      context.config.dependencyInjection == DependencyInjection.injectable ||
      context.config.localStorage == LocalStorage.hive ||
      context.config.localStorage == LocalStorage.objectbox;

  if (requiresFlutter) {
    dependencies.insert(0, '  flutter:\n    sdk: flutter');
  }

  if (context.config.useEitherFailure) {
    dependencies.add('  dartz: ^0.10.1');
  }
  if (context.config.network == NetworkClient.dio) {
    dependencies.add('  dio: ^5.10.0');
    dependencies.add('  retrofit: ^4.9.2');
    devDependencies.add('  retrofit_generator: ^10.2.8');
  }
  if (context.config.dependencyInjection == DependencyInjection.injectable) {
    dependencies.add('  injectable: $_injectableVersion');
    dependencies.add('  get_it: $_getItVersion');
    devDependencies.add('  injectable_generator: $_injectableGeneratorVersion');
  }
  if (context.config.localStorage == LocalStorage.secureStorage) {
    dependencies.add('  flutter_secure_storage: ^10.3.1');
  }
  if (context.config.localStorage == LocalStorage.sharedPreferences) {
    dependencies.add('  shared_preferences: ^2.5.5');
  }
  if (context.config.localStorage == LocalStorage.hive) {
    dependencies.add('  hive_ce: ^2.19.3');
    dependencies.add('  hive_ce_flutter: ^2.3.4');
    devDependencies.add('  hive_ce_generator: 1.11.1');
  }
  if (context.config.localStorage == LocalStorage.objectbox) {
    dependencies.add('  objectbox: ^5.3.2');
    dependencies.add('  objectbox_flutter_libs: ^5.3.2');
    dependencies.add('  path_provider: ^2.1.6');
    devDependencies.add('  objectbox_generator: ^5.3.2');
  }
  if (context.config.models.useFreezed) {
    dependencies.add('  freezed_annotation: $_freezedAnnotationVersion');
    devDependencies.add('  freezed: $_freezedVersion');
  }
  if (context.config.models.useJsonSerializable) {
    dependencies.add('  json_annotation: $_jsonAnnotationVersion');
    devDependencies.add('  json_serializable: $_jsonSerializableVersion');
  }
  if (requiresBuildRunner) {
    devDependencies.insert(0, '  build_runner: $_buildRunnerVersion');
  }

  return '''
name: ${_packageName(context.paths.data)}
description: Data layer generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint
${requiresFlutter ? "  flutter: '$_flutterConstraint'\n" : ''}

dependencies:
${dependencies.join('\n')}

${_section('dev_dependencies', devDependencies)}
''';
}

String _diPubspec(TemplateContext context) {
  final dependencies = <String>[
    '  ${_packageName(context.paths.domain)}:',
    '    path: ../${_packageName(context.paths.domain)}',
    '  ${_packageName(context.paths.data)}:',
    '    path: ../${_packageName(context.paths.data)}',
    '  get_it: $_getItVersion',
    if (context.config.network == NetworkClient.dio) '  dio: ^5.10.0',
    if (context.config.localStorage == LocalStorage.objectbox)
      '  objectbox: ^5.3.2',
  ];

  return '''
name: ${_packageName(context.paths.di)}
description: Dependency injection layer generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint

dependencies:
${dependencies.join('\n')}
''';
}

String _presentationPubspec(TemplateContext context) {
  final dependencies = <String>[
    '  flutter:',
    '    sdk: flutter',
    "  ${_packageName(context.paths.domain)}:",
    '    path: ../${_packageName(context.paths.domain)}',
    "  ${_packageName(context.paths.data)}:",
    '    path: ../${_packageName(context.paths.data)}',
    "  ${_packageName(context.paths.di)}:",
    '    path: ../${_packageName(context.paths.di)}',
    '  get_it: $_getItVersion',
  ];

  if (context.config.stateManagement == StateManagement.getx) {
    dependencies.add('  get: ^4.7.3');
  }
  if (context.config.stateManagement == StateManagement.bloc) {
    dependencies.add('  flutter_bloc: ^9.1.1');
    dependencies.add('  equatable: ^2.1.0');
  }
  if (context.config.stateManagement == StateManagement.provider) {
    dependencies.add('  provider: ^6.1.5+1');
  }
  final devDependencies = <String>[
    '  flutter_test:\n    sdk: flutter',
    '  flutter_lints: ^6.0.0',
    if (context.config.useAssetGenerator)
      '  build_runner: $_buildRunnerVersion',
    if (context.config.useAssetGenerator) '  assets_generator_kit: ^0.1.0',
  ];

  return '''
name: ${_packageName(context.paths.presentation)}
description: Flutter presentation layer generated by clean_architect.
publish_to: none

environment:
  sdk: $_sdkConstraint
  flutter: '$_flutterConstraint'

dependencies:
${dependencies.join('\n')}

dev_dependencies:
${devDependencies.join('\n')}
flutter:
  uses-material-design: true
''';
}

String _assetGeneratorKit() {
  return '''
assets_generator_kit:
  input:
    - assets/images
    - assets/icons

  output: lib/generated/assets.dart

  integrations:
    svg: true
    lottie: false
   ''';
}

String _presentationMain() {
  return '''
import 'package:di/di.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDi(get: GetIt.instance);
  runApp(const CleanArchitectApp());
}

class CleanArchitectApp extends StatelessWidget {
  const CleanArchitectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clean Architect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('Clean Architect')),
      ),
    );
  }
}
''';
}

String _packageRoot(String libPath) {
  final parts = p.split(p.normalize(libPath));
  final libIndex = parts.indexOf('lib');
  if (libIndex == -1) return libPath;
  return p.joinAll(parts.take(libIndex));
}

String _packageName(String libPath) {
  final parts = p.split(p.normalize(libPath));
  final libIndex = parts.indexOf('lib');
  if (libIndex > 0) return parts[libIndex - 1];
  return p.basename(libPath);
}

String _section(String name, Iterable<String> entries) {
  final uniqueEntries = entries.toSet();
  if (uniqueEntries.isEmpty) return '';
  return '\n$name:\n${uniqueEntries.join('\n')}\n';
}
