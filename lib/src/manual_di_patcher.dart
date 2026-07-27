import 'dart:io';

import 'package:path/path.dart' as p;

import 'case_utils.dart';
import 'config.dart';
import 'generated_file.dart';
import 'operation_kind.dart';
import 'path_resolver.dart';

class ManualDiPatcher {
  const ManualDiPatcher(this.config);

  final CleanArchitectConfig config;

  GeneratedFile? planFeatureBootstrap(String featureName) {
    if (config.dependencyInjection != DependencyInjection.manual) return null;

    final feature = NameCases(featureName);
    final path = config.structure == ProjectStructure.verticalPackages
        ? p.join(_packageRoot(config.paths.app), 'lib', 'di', 'bootstrap.dart')
        : p.join(_packageRoot(config.paths.di), 'lib', 'di.dart');
    final file = File(path);
    if (!file.existsSync()) return null;

    var content = file.readAsStringSync();
    final dataCall = '  await init${feature.pascal}Data(get);';
    final domainCall = '  init${feature.pascal}Domain(get);';
    if (content.contains(dataCall) && content.contains(domainCall)) return null;

    final import = config.structure == ProjectStructure.verticalPackages
        ? "import 'package:${feature.snake}/${feature.snake}.dart';"
        : "import '${feature.snake}_di.dart';";
    content = _ensureImport(content, import);
    content = _insertBeforeMarker(
      content,
      '  // clean_architect:data-registrations',
      '$dataCall\n',
    );
    content = _insertBeforeMarker(
      content,
      '  // clean_architect:domain-registrations',
      '$domainCall\n',
    );
    return GeneratedFile(path: path, content: content, allowUpdate: true);
  }

  GeneratedFile? planOperation({
    required String featureName,
    required String operationName,
    required OperationKind kind,
  }) {
    final operation = NameCases(operationName);
    final useCases = kind == OperationKind.cached
        ? [
            NameCases('sync${_cachedSubject(operation)}'),
            NameCases('stream${_cachedSubject(operation)}'),
          ]
        : [operation];
    return _planUseCases(featureName, useCases, repositoryBacked: true);
  }

  GeneratedFile? planUseCase({
    required String featureName,
    required String useCaseName,
  }) {
    return _planUseCases(featureName, [
      NameCases(useCaseName),
    ], repositoryBacked: false);
  }

  GeneratedFile? _planUseCases(
    String featureName,
    List<NameCases> useCases, {
    required bool repositoryBacked,
  }) {
    if (config.dependencyInjection != DependencyInjection.manual) return null;

    final feature = NameCases(featureName);
    final paths = PathResolver(config).resolve(feature.snake);
    final path = p.join(paths.di, '${feature.snake}_di.dart');
    final file = File(path);
    if (!file.existsSync()) return null;

    var content = file.readAsStringSync();
    for (final useCase in useCases) {
      final className = '${useCase.pascal}UseCase';
      if (content.contains('isRegistered<$className>')) continue;
      content = _ensureImport(
        content,
        "import '${_packageImport(paths.domain, 'usecases/${useCase.snake}_use_case.dart')}';",
      );
      final constructor = repositoryBacked
          ? '$className(get<${feature.pascal}Repository>())'
          : 'const $className()';
      final registration =
          '''
  if (!get.isRegistered<$className>()) {
    get.registerLazySingleton<$className>(
      () => $constructor,
    );
  }
''';
      content = _insertBeforeMarker(
        content,
        '  // clean_architect:domain-registrations',
        registration,
      );
    }
    return GeneratedFile(path: path, content: content, allowUpdate: true);
  }
}

String _ensureImport(String content, String import) {
  if (content.contains(import)) return content;
  final imports = RegExp(
    r'''import '[^']+';|import "[^"]+";''',
  ).allMatches(content).toList(growable: false);
  if (imports.isEmpty) return '$import\n\n$content';
  final last = imports.last;
  return content.replaceRange(last.end, last.end, '\n$import');
}

String _insertBeforeMarker(String content, String marker, String value) {
  final index = content.indexOf(marker);
  if (index == -1) {
    throw FormatException('Manual DI file is missing marker: $marker');
  }
  return content.replaceRange(index, index, value);
}

String _cachedSubject(NameCases operation) {
  final name = operation.pascal;
  if (name.startsWith('Sync') && name.length > 4) return name.substring(4);
  if (name.startsWith('Stream') && name.length > 6) return name.substring(6);
  return name;
}

String _packageRoot(String libPath) {
  final parts = p.split(p.normalize(libPath));
  final libIndex = parts.indexOf('lib');
  if (libIndex == -1) return libPath;
  return p.joinAll(parts.take(libIndex));
}

String _packageImport(String basePath, String path) {
  final parts = p.split(p.normalize(basePath));
  final libIndex = parts.indexOf('lib');
  if (libIndex <= 0) return path;
  final packageName = parts[libIndex - 1];
  final libPath = p.url.joinAll(parts.skip(libIndex + 1).followedBy([path]));
  return 'package:$packageName/$libPath';
}
