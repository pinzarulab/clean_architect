import 'package:path/path.dart' as p;

import '../case_utils.dart';
import '../config.dart';
import '../data_paths.dart';
import '../generated_file.dart';
import '../generator.dart';

List<GeneratedFile> featureTemplates(TemplateContext context) {
  final feature = context.cases;
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final files = <GeneratedFile>[
    if (context.config.structure == ProjectStructure.verticalPackages)
      _publicLibrary(context),
    if (context.config.useEitherFailure &&
        context.config.structure != ProjectStructure.verticalPackages)
      _failure(context),
    GeneratedFile(
      path: p.join(
        context.paths.domain,
        'entities',
        '${feature.snake}_entity.dart',
      ),
      content: _entity(context),
    ),
    GeneratedFile(
      path: p.join(
        context.paths.domain,
        'repositories',
        '${feature.snake}_repository.dart',
      ),
      content: _repository(context),
    ),
    GeneratedFile(
      path: p.join(
        context.paths.domain,
        'usecases',
        'get_${feature.snake}_list_use_case.dart',
      ),
      content: _useCase(context),
    ),
    GeneratedFile(
      path: p.join(dataPaths.remoteModels, '${feature.snake}_dto.dart'),
      content: _dto(context),
    ),
    GeneratedFile(
      path: p.join(dataPaths.mappers, '${feature.snake}_mapper.dart'),
      content: _mapper(context),
    ),
    GeneratedFile(
      path: p.join(
        dataPaths.remoteDataSources,
        '${feature.snake}_remote_data_source.dart',
      ),
      content: _remoteDataSource(context),
    ),
    GeneratedFile(
      path: p.join(dataPaths.localModels, '${feature.snake}_box.dart'),
      content: _localBox(context),
    ),
    GeneratedFile(
      path: p.join(
        dataPaths.localDataSources,
        '${feature.snake}_local_data_source.dart',
      ),
      content: _localSource(context),
    ),
    GeneratedFile(
      path: p.join(
        dataPaths.repositories,
        '${feature.snake}_repository_impl.dart',
      ),
      content: _repositoryImpl(context),
    ),
    _di(context),
  ];

  if (!context.skipPresentation) {
    files.addAll(_presentation(context));
  }

  return files;
}

GeneratedFile _publicLibrary(TemplateContext context) {
  final feature = context.cases;
  final exports = <String>[
    "export 'src/domain/entities/${feature.snake}_entity.dart';",
    "export 'src/domain/repositories/${feature.snake}_repository.dart';",
    "export 'src/domain/usecases/get_${feature.snake}_list_use_case.dart';",
    if (!context.skipPresentation)
      "export 'src/presentation/controllers/${feature.snake}_controller.dart';",
    if (!context.skipPresentation)
      "export 'src/presentation/pages/${feature.snake}_page.dart';",
    if (context.config.dependencyInjection == DependencyInjection.injectable)
      "export 'src/di/injector.dart';"
    else
      "export 'src/di/${feature.snake}_di.dart';",
  ];
  return GeneratedFile(
    path: p.join(
      _packageRoot(context.paths.domain),
      'lib',
      '${feature.snake}.dart',
    ),
    content:
        '''
/// Public API for the ${feature.title} feature.
library;

${exports.join('\n')}
''',
  );
}

GeneratedFile _failure(TemplateContext context) {
  return GeneratedFile(
    path: p.join(
      _packageRoot(context.paths.domain),
      'lib',
      'failures',
      'failure.dart',
    ),
    content: '''
class Failure {
  const Failure(this.message);

  final String message;
}
''',
  );
}

String _repository(TemplateContext context) {
  final feature = context.cases;
  final eitherImport = context.config.useEitherFailure
      ? "import 'package:dartz/dartz.dart';\n\nimport '${_failureImport(context)}';\n"
      : '';

  return '''
${eitherImport}import '../entities/${feature.snake}_entity.dart';

abstract interface class ${feature.pascal}Repository {
  ${_returnType(context, 'List<${feature.pascal}Entity>')} get${feature.pascal}List();
}
''';
}

String _useCase(TemplateContext context) {
  final feature = context.cases;
  final eitherImport = context.config.useEitherFailure
      ? "import 'package:dartz/dartz.dart';\n\nimport '${_failureImport(context)}';\n"
      : '';

  return '''
${_injectableImport(context)}${eitherImport}import '../entities/${feature.snake}_entity.dart';
import '../repositories/${feature.snake}_repository.dart';

${_lazySingletonAnnotation(context)}class Get${feature.pascal}ListUseCase {
  const Get${feature.pascal}ListUseCase(this._repository);

  final ${feature.pascal}Repository _repository;

  ${_returnType(context, 'List<${feature.pascal}Entity>')} call() {
    return _repository.get${feature.pascal}List();
  }
}
''';
}

String _localBox(TemplateContext context) {
  final feature = context.cases;
  return switch (context.config.localStorage) {
    LocalStorage.hive =>
      '''
import 'package:hive_ce/hive.dart';

part '${feature.snake}_box.g.dart';

@HiveType(typeId: ${stableHiveTypeId(feature.snake)})
class ${feature.pascal}Box extends HiveObject {
  ${feature.pascal}Box({
    this.id = 0,
    this.remoteId = '',
  });

  @HiveField(0)
  int id;

  @HiveField(1)
  String remoteId;
}
''',
    LocalStorage.objectbox =>
      '''
import 'package:objectbox/objectbox.dart';

@Entity()
class ${feature.pascal}Box {
  ${feature.pascal}Box({
    this.id = 0,
    this.remoteId = '',
  });

  @Id()
  int id;

  String remoteId;
}
''',
    _ =>
      '''
class ${feature.pascal}Box {
  const ${feature.pascal}Box({
    this.id = 0,
    this.remoteId = '',
  });

  final int id;
  final String remoteId;
}
''',
  };
}

String _localSource(TemplateContext context) {
  final feature = context.cases;
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final boxImport = relativeDartImport(
    fromDirectory: dataPaths.localDataSources,
    targetPath: p.join(dataPaths.localModels, '${feature.snake}_box.dart'),
  );
  final annotation = _lazySingletonAsAnnotation(
    context,
    '${feature.pascal}LocalDataSource',
  );
  if (context.config.localStorage == LocalStorage.hive) {
    return '''
${_injectableImport(context)}import 'package:hive_ce/hive.dart';

import '$boxImport';

abstract class ${feature.pascal}LocalDataSource {
  Future<void> cacheItems(List<Object> items);
}

$annotation
class ${feature.pascal}LocalDataSourceImpl implements ${feature.pascal}LocalDataSource {
  const ${feature.pascal}LocalDataSourceImpl(this._box);

  final Box<${feature.pascal}Box> _box;
  Box<${feature.pascal}Box> get box => _box;

  static Future<${feature.pascal}LocalDataSource> init() async {
    if (!Hive.isAdapterRegistered(${stableHiveTypeId(feature.snake)})) {
      Hive.registerAdapter(${feature.pascal}BoxAdapter());
    }
    final box = await Hive.openBox<${feature.pascal}Box>('${feature.snake}_box');
    return ${feature.pascal}LocalDataSourceImpl(box);
  }

  @override
  Future<void> cacheItems(List<Object> items) async {
    // TODO: Convert ${feature.title.toLowerCase()} items to ${feature.pascal}Box and cache them.
  }
}
''';
  }

  if (context.config.localStorage == LocalStorage.objectbox) {
    return '''
${_injectableImport(context)}import 'package:objectbox/objectbox.dart';

import '$boxImport';

abstract class ${feature.pascal}LocalDataSource {
  Future<void> cacheItems(List<Object> items);
}

$annotation
class ${feature.pascal}LocalDataSourceImpl implements ${feature.pascal}LocalDataSource {
  const ${feature.pascal}LocalDataSourceImpl(this._box);

  final Box<${feature.pascal}Box> _box;
  Box<${feature.pascal}Box> get box => _box;

  static ${feature.pascal}LocalDataSource init(Store store) {
    return ${feature.pascal}LocalDataSourceImpl(Box<${feature.pascal}Box>(store));
  }

  @override
  Future<void> cacheItems(List<Object> items) async {
    // TODO: Convert ${feature.title.toLowerCase()} items to ${feature.pascal}Box and cache them.
  }
}
''';
  }

  return '''
${_injectableImport(context)}import '$boxImport';

abstract class ${feature.pascal}LocalDataSource {
  Future<void> cacheItems(List<Object> items);
}

$annotation
class ${feature.pascal}LocalDataSourceImpl implements ${feature.pascal}LocalDataSource {
  const ${feature.pascal}LocalDataSourceImpl();

  static Future<${feature.pascal}LocalDataSource> init() async {
    return const ${feature.pascal}LocalDataSourceImpl();
  }

  @override
  Future<void> cacheItems(List<Object> items) async {
    final placeholder = const ${feature.pascal}Box();
    // TODO: Cache ${feature.title.toLowerCase()} items using your local storage. Remove placeholder when implemented.
    placeholder.id;
  }
}
''';
}

String _entity(TemplateContext context) {
  final feature = context.cases;
  if (context.config.models.useFreezed) {
    return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${feature.snake}_entity.freezed.dart';

@freezed
abstract class ${feature.pascal}Entity with _\$${feature.pascal}Entity {
  const factory ${feature.pascal}Entity({
    required String remoteId,
  }) = _${feature.pascal}Entity;
}
''';
  }

  return '''
class ${feature.pascal}Entity {
  const ${feature.pascal}Entity({
    required this.remoteId,
  });

  final String remoteId;
}
''';
}

String _dto(TemplateContext context) {
  final feature = context.cases;
  if (context.config.models.useFreezed) {
    if (context.config.models.useJsonSerializable) {
      return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${feature.snake}_dto.freezed.dart';
part '${feature.snake}_dto.g.dart';

@freezed
abstract class ${feature.pascal}Dto with _\$${feature.pascal}Dto {
  const factory ${feature.pascal}Dto({
    required String id,
  }) = _${feature.pascal}Dto;

  factory ${feature.pascal}Dto.fromJson(Map<String, dynamic> json) =>
      _\$${feature.pascal}DtoFromJson(json);
}
''';
    }

    return '''
import 'package:freezed_annotation/freezed_annotation.dart';

part '${feature.snake}_dto.freezed.dart';

@freezed
abstract class ${feature.pascal}Dto with _\$${feature.pascal}Dto {
  const ${feature.pascal}Dto._();

  const factory ${feature.pascal}Dto({
    required String id,
  }) = _${feature.pascal}Dto;

  factory ${feature.pascal}Dto.fromJson(Map<String, dynamic> json) {
    return ${feature.pascal}Dto(id: json['id'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'id': id};
  }
}
''';
  }

  if (context.config.models.useJsonSerializable) {
    return '''
import 'package:json_annotation/json_annotation.dart';

part '${feature.snake}_dto.g.dart';

@JsonSerializable()
class ${feature.pascal}Dto {
  const ${feature.pascal}Dto({
    required this.id,
  });

  factory ${feature.pascal}Dto.fromJson(Map<String, dynamic> json) {
    return _\$${feature.pascal}DtoFromJson(json);
  }

  final String id;

  Map<String, dynamic> toJson() => _\$${feature.pascal}DtoToJson(this);
}
''';
  }

  return '''
class ${feature.pascal}Dto {
  const ${feature.pascal}Dto({
    required this.id,
  });

  factory ${feature.pascal}Dto.fromJson(Map<String, dynamic> json) {
    return ${feature.pascal}Dto(id: json['id'] as String);
  }

  final String id;

  Map<String, dynamic> toJson() {
    return {'id': id};
  }
}
''';
}

String _mapper(TemplateContext context) {
  final feature = context.cases;
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final entityImport = _domainImport(
    context,
    'entities/${feature.snake}_entity.dart',
  );
  final boxImport = relativeDartImport(
    fromDirectory: dataPaths.mappers,
    targetPath: p.join(dataPaths.localModels, '${feature.snake}_box.dart'),
  );
  final dtoImport = relativeDartImport(
    fromDirectory: dataPaths.mappers,
    targetPath: p.join(dataPaths.remoteModels, '${feature.snake}_dto.dart'),
  );

  return '''
import '$entityImport';
import '$boxImport';
import '$dtoImport';

extension ${feature.pascal}DtoMapper on ${feature.pascal}Dto {
  ${feature.pascal}Entity toEntity() {
    return ${feature.pascal}Entity(remoteId: id);
  }

  ${feature.pascal}Box toBox() {
    return ${feature.pascal}Box(remoteId: id);
  }
}

extension ${feature.pascal}BoxMapper on ${feature.pascal}Box {
  ${feature.pascal}Entity toEntity() {
    return ${feature.pascal}Entity(remoteId: remoteId);
  }
}
''';
}

String _remoteDataSource(TemplateContext context) {
  final feature = context.cases;
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final dtoImport = relativeDartImport(
    fromDirectory: dataPaths.remoteDataSources,
    targetPath: p.join(dataPaths.remoteModels, '${feature.snake}_dto.dart'),
  );
  if (context.config.network == NetworkClient.abstract) {
    return '''
import '$dtoImport';

abstract interface class ${feature.pascal}RemoteDataSource {
  Future<List<${feature.pascal}Dto>> getItems();
}
''';
  }

  final factoryAnnotation =
      context.config.dependencyInjection == DependencyInjection.injectable
      ? '  @factoryMethod\n'
      : '';
  return '''
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
${_injectableImport(context)}

import '$dtoImport';

part '${feature.snake}_remote_data_source.g.dart';

${_lazySingletonAnnotation(context)}@RestApi(baseUrl: '')
abstract class ${feature.pascal}RemoteDataSource {
$factoryAnnotation  factory ${feature.pascal}RemoteDataSource(${context.config.dependencyInjection == DependencyInjection.injectable ? '@Named("main_dio") ' : ''}Dio dio) = _${feature.pascal}RemoteDataSource;

  @GET('/${feature.snake}')
  Future<List<${feature.pascal}Dto>> getItems();
}
''';
}

String _repositoryImpl(TemplateContext context) {
  final feature = context.cases;
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  final entityImport = _domainImport(
    context,
    'entities/${feature.snake}_entity.dart',
  );
  final repositoryImport = _domainImport(
    context,
    'repositories/${feature.snake}_repository.dart',
  );
  final mapperImport = relativeDartImport(
    fromDirectory: dataPaths.repositories,
    targetPath: p.join(dataPaths.mappers, '${feature.snake}_mapper.dart'),
  );
  final localSourceImport = relativeDartImport(
    fromDirectory: dataPaths.repositories,
    targetPath: p.join(
      dataPaths.localDataSources,
      '${feature.snake}_local_data_source.dart',
    ),
  );
  final remoteSourceImport = relativeDartImport(
    fromDirectory: dataPaths.repositories,
    targetPath: p.join(
      dataPaths.remoteDataSources,
      '${feature.snake}_remote_data_source.dart',
    ),
  );

  final eitherImport = context.config.useEitherFailure
      ? "import 'package:dartz/dartz.dart';\nimport '${_failureImport(context)}';\n"
      : '';
  final body = context.config.useEitherFailure
      ? '''try {
      final items = await _remoteDataSource.getItems();
      await _localDataSource.cacheItems(items);
      return right(items.map((item) => item.toEntity()).toList(growable: false));
    } catch (error) {
      return left(Failure(error.toString()));
    }'''
      : '''final items = await _remoteDataSource.getItems();
    await _localDataSource.cacheItems(items);
    return items.map((item) => item.toEntity()).toList(growable: false);''';

  return '''
${_injectableImport(context)}${eitherImport}import '$entityImport';
import '$repositoryImport';
import '$mapperImport';
import '$localSourceImport';
import '$remoteSourceImport';

${_lazySingletonAsAnnotation(context, '${feature.pascal}Repository')}
class ${feature.pascal}RepositoryImpl implements ${feature.pascal}Repository {
  const ${feature.pascal}RepositoryImpl({
    required ${feature.pascal}RemoteDataSource remoteDataSource,
    required ${feature.pascal}LocalDataSource localDataSource,
  })  : _remoteDataSource = remoteDataSource,
        _localDataSource = localDataSource;

  final ${feature.pascal}RemoteDataSource _remoteDataSource;
  final ${feature.pascal}LocalDataSource _localDataSource;

  @override
  ${_returnType(context, 'List<${feature.pascal}Entity>')} get${feature.pascal}List() async {
    $body
  }
}
''';
}

GeneratedFile _di(TemplateContext context) {
  final feature = context.cases;
  final dataPaths = DataPaths.resolve(context.config, context.paths.data);
  if (context.config.dependencyInjection == DependencyInjection.injectable) {
    return GeneratedFile(
      path: p.join(context.paths.di, '.gitkeep'),
      content: '',
    );
  }

  final objectBoxImport = context.config.localStorage == LocalStorage.objectbox
      ? "import 'package:objectbox/objectbox.dart';\nimport '${_dataFileImport(context, p.join(_packageRoot(context.paths.data), 'lib', 'objectbox.g.dart'))}';\n"
      : '';
  final dioImport = context.config.network == NetworkClient.dio
      ? "import 'package:dio/dio.dart';\n"
      : '';
  final localInitialization =
      context.config.localStorage == LocalStorage.objectbox
      ? '''
    if (!get.isRegistered<Store>()) {
      get.registerSingleton<Store>(await openStore());
    }
    final localDataSource = ${feature.pascal}LocalDataSourceImpl.init(
      get<Store>(),
    );'''
      : '''
    final localDataSource = await ${feature.pascal}LocalDataSourceImpl.init();''';
  final remoteRegistration = context.config.network == NetworkClient.dio
      ? '''
  if (!get.isRegistered<${feature.pascal}RemoteDataSource>()) {
    final dio = Dio(BaseOptions(baseUrl: ''));
    get.registerLazySingleton<${feature.pascal}RemoteDataSource>(
      () => ${feature.pascal}RemoteDataSource(dio),
    );
  }
'''
      : '''
  // Register ${feature.pascal}RemoteDataSource before resolving the repository.
''';

  return GeneratedFile(
    path: p.join(context.paths.di, '${feature.snake}_di.dart'),
    content:
        '''
import 'package:get_it/get_it.dart';
$dioImport$objectBoxImport
import '${_dataFileImport(context, p.join(dataPaths.repositories, '${feature.snake}_repository_impl.dart'))}';
import '${_dataFileImport(context, p.join(dataPaths.localDataSources, '${feature.snake}_local_data_source.dart'))}';
import '${_dataFileImport(context, p.join(dataPaths.remoteDataSources, '${feature.snake}_remote_data_source.dart'))}';
import '${_domainImport(context, 'repositories/${feature.snake}_repository.dart')}';
import '${_domainImport(context, 'usecases/get_${feature.snake}_list_use_case.dart')}';

Future<void> init${feature.pascal}Data(GetIt get) async {
  if (!get.isRegistered<${feature.pascal}LocalDataSource>()) {$localInitialization
    get.registerLazySingleton<${feature.pascal}LocalDataSource>(
      () => localDataSource,
    );
  }
$remoteRegistration
  if (!get.isRegistered<${feature.pascal}Repository>()) {
    get.registerLazySingleton<${feature.pascal}Repository>(
      () => ${feature.pascal}RepositoryImpl(
        remoteDataSource: get<${feature.pascal}RemoteDataSource>(),
        localDataSource: get<${feature.pascal}LocalDataSource>(),
      ),
    );
  }
}

void init${feature.pascal}Domain(GetIt get) {
  if (!get.isRegistered<Get${feature.pascal}ListUseCase>()) {
    get.registerLazySingleton<Get${feature.pascal}ListUseCase>(
      () => Get${feature.pascal}ListUseCase(get<${feature.pascal}Repository>()),
    );
  }
  // clean_architect:domain-registrations
}
''',
  );
}

List<GeneratedFile> _presentation(TemplateContext context) {
  final feature = context.cases;

  return [
    GeneratedFile(
      path: p.join(
        context.paths.presentation,
        'controllers',
        '${feature.snake}_controller.dart',
      ),
      content: _controller(context),
    ),
    GeneratedFile(
      path: p.join(
        context.paths.presentation,
        'pages',
        '${feature.snake}_page.dart',
      ),
      content: _page(context),
    ),
  ];
}

String _controller(TemplateContext context) {
  final feature = context.cases;
  final blocLoad = context.config.useEitherFailure
      ? '''final result = await _get${feature.pascal}ListUseCase();
    result.fold(
      (failure) => emit(state.copyWith(isLoading: false)),
      (entities) => emit(
        state.copyWith(
          isLoading: false,
          items: entities.map((entity) => entity.remoteId).toList(growable: false),
        ),
      ),
    );'''
      : '''final entities = await _get${feature.pascal}ListUseCase();
    emit(
      state.copyWith(
        isLoading: false,
        items: entities.map((entity) => entity.remoteId).toList(growable: false),
      ),
    );''';
  final notifierLoad = context.config.useEitherFailure
      ? '''final result = await _get${feature.pascal}ListUseCase();
    result.fold(
      (failure) => items = const <String>[],
      (entities) => items =
          entities.map((entity) => entity.remoteId).toList(growable: false),
    );'''
      : '''final entities = await _get${feature.pascal}ListUseCase();
    items = entities.map((entity) => entity.remoteId).toList(growable: false);''';
  final assignItems = context.config.stateManagement == StateManagement.getx
      ? 'items.assignAll(entities.map((entity) => entity.remoteId))'
      : 'items = entities.map((entity) => entity.remoteId).toList(growable: false)';
  final clearItems = context.config.stateManagement == StateManagement.getx
      ? 'items.clear()'
      : 'items = const <String>[]';
  final simpleLoad = context.config.useEitherFailure
      ? '''final result = await _get${feature.pascal}ListUseCase();
    result.fold(
      (failure) => $clearItems,
      (entities) => $assignItems,
    );'''
      : '''final entities = await _get${feature.pascal}ListUseCase();
    $assignItems;''';

  if (context.config.stateManagement == StateManagement.bloc) {
    return '''
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '${_domainPresentationImport(context, 'usecases/get_${feature.snake}_list_use_case.dart')}';

sealed class ${feature.pascal}Event extends Equatable {
  const ${feature.pascal}Event();

  @override
  List<Object?> get props => [];
}

class ${feature.pascal}Requested extends ${feature.pascal}Event {
  const ${feature.pascal}Requested();
}

class ${feature.pascal}State extends Equatable {
  const ${feature.pascal}State({
    this.items = const <String>[],
    this.isLoading = false,
  });

  final List<String> items;
  final bool isLoading;

  ${feature.pascal}State copyWith({
    List<String>? items,
    bool? isLoading,
  }) {
    return ${feature.pascal}State(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [items, isLoading];
}

class ${feature.pascal}Controller extends Bloc<${feature.pascal}Event, ${feature.pascal}State> {
  ${feature.pascal}Controller()
      : _get${feature.pascal}ListUseCase = GetIt.instance.get<Get${feature.pascal}ListUseCase>(),
        super(const ${feature.pascal}State()) {
    on<${feature.pascal}Requested>(_onRequested);
  }

  final Get${feature.pascal}ListUseCase _get${feature.pascal}ListUseCase;

  Future<void> _onRequested(
    ${feature.pascal}Requested event,
    Emitter<${feature.pascal}State> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    $blocLoad
  }
}
''';
  }

  if (context.config.stateManagement == StateManagement.provider) {
    return '''
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '${_domainPresentationImport(context, 'usecases/get_${feature.snake}_list_use_case.dart')}';

class ${feature.pascal}Controller extends ChangeNotifier {
  final _get${feature.pascal}ListUseCase = GetIt.instance.get<Get${feature.pascal}ListUseCase>();

  var items = const <String>[];
  var isLoading = false;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    $notifierLoad
    isLoading = false;
    notifyListeners();
  }
}
''';
  }

  final getxImport = context.config.stateManagement == StateManagement.getx
      ? "import 'package:get/get.dart';\n"
      : '';
  final baseClass = context.config.stateManagement == StateManagement.getx
      ? ' extends GetxController'
      : '';

  return '''
${getxImport}import '${_domainPresentationImport(context, 'usecases/get_${feature.snake}_list_use_case.dart')}';
import 'package:get_it/get_it.dart';

class ${feature.pascal}Controller$baseClass {
  final _get${feature.pascal}ListUseCase = GetIt.instance.get<Get${feature.pascal}ListUseCase>();

  ${context.config.stateManagement == StateManagement.getx ? 'final items = <String>[].obs;' : 'var items = const <String>[];'}

  Future<void> load() async {
    $simpleLoad
  }
}
''';
}

String _page(TemplateContext context) {
  final feature = context.cases;
  final viewItem =
      '''
class ${feature.pascal}ViewItem extends StatelessWidget {
  const ${feature.pascal}ViewItem({
    required this.id,
    super.key,
  });

  final String id;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(id));
  }
}
''';
  if (context.config.stateManagement == StateManagement.bloc) {
    return '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../controllers/${feature.snake}_controller.dart';

class ${feature.pascal}Page extends StatelessWidget {
  const ${feature.pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ${feature.pascal}Controller()..add(const ${feature.pascal}Requested()),
      child: Scaffold(
        appBar: AppBar(title: const Text('${feature.title}')),
        body: BlocBuilder<${feature.pascal}Controller, ${feature.pascal}State>(
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.items.isEmpty) {
              return const Center(child: Text('${feature.title}'));
            }
            return ListView.builder(
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                return ${feature.pascal}ViewItem(id: state.items[index]);
              },
            );
          },
        ),
      ),
    );
  }
}
$viewItem
''';
  }

  if (context.config.stateManagement == StateManagement.provider) {
    return '''
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/${feature.snake}_controller.dart';

class ${feature.pascal}Page extends StatelessWidget {
  const ${feature.pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ${feature.pascal}Controller()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('${feature.title}')),
        body: Consumer<${feature.pascal}Controller>(
          builder: (context, controller, child) {
            if (controller.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (controller.items.isEmpty) {
              return const Center(child: Text('${feature.title}'));
            }
            return ListView.builder(
              itemCount: controller.items.length,
              itemBuilder: (context, index) {
                return ${feature.pascal}ViewItem(id: controller.items[index]);
              },
            );
          },
        ),
      ),
    );
  }
}
$viewItem
''';
  }

  if (context.config.stateManagement == StateManagement.getx) {
    return '''
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/${feature.snake}_controller.dart';

class ${feature.pascal}Page extends StatefulWidget {
  const ${feature.pascal}Page({super.key});

  @override
  State<${feature.pascal}Page> createState() => _${feature.pascal}PageState();
}

class _${feature.pascal}PageState extends State<${feature.pascal}Page> {
  late final ${feature.pascal}Controller controller;

  @override
  void initState() {
    super.initState();
    Get.put(${feature.pascal}Controller());
    controller = Get.find<${feature.pascal}Controller>();
    controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('${feature.title}')),
      body: Obx(() {
        if (controller.items.isEmpty) {
          return const Center(child: Text('${feature.title}'));
        }
        return ListView.builder(
          itemCount: controller.items.length,
          itemBuilder: (context, index) {
            return ${feature.pascal}ViewItem(id: controller.items[index]);
          },
        );
      }),
    );
  }
}
$viewItem
''';
  }

  return '''
import 'package:flutter/material.dart';

class ${feature.pascal}Page extends StatelessWidget {
  const ${feature.pascal}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('${feature.title}')),
      body: const Center(child: Text('${feature.title}')),
    );
  }
}
$viewItem
''';
}

String _lazySingletonAsAnnotation(TemplateContext context, String typeName) {
  return context.config.dependencyInjection == DependencyInjection.injectable
      ? '@LazySingleton(as: $typeName)'
      : '';
}

String _returnType(TemplateContext context, String valueType) {
  if (context.config.useEitherFailure) {
    return 'Future<Either<Failure, $valueType>>';
  }
  return 'Future<$valueType>';
}

String _packageRoot(String libPath) {
  final parts = p.split(p.normalize(libPath));
  final libIndex = parts.indexOf('lib');
  if (libIndex == -1) return libPath;
  return p.joinAll(parts.take(libIndex));
}

String _domainImport(TemplateContext context, String path) {
  return _packageImport(context.paths.domain, path);
}

String _domainRootImport(TemplateContext context, String path) {
  final domainLib = p.join(_packageRoot(context.paths.domain), 'lib');
  return _packageImport(domainLib, path);
}

String _failureImport(TemplateContext context) {
  if (context.config.structure == ProjectStructure.verticalPackages) {
    return 'package:${_packageName(context.config.paths.core)}/core.dart';
  }
  return _domainRootImport(context, 'failures/failure.dart');
}

String _dataImport(TemplateContext context, String path) {
  return _packageImport(context.paths.data, path);
}

String _dataFileImport(TemplateContext context, String targetPath) {
  return _dataImport(
    context,
    relativeDartImport(
      fromDirectory: context.paths.data,
      targetPath: targetPath,
    ),
  );
}

String _domainPresentationImport(TemplateContext context, String path) {
  return _domainImport(context, path);
}

String _packageImport(String basePath, String path) {
  final parts = p.split(p.normalize(basePath));
  final libIndex = parts.indexOf('lib');
  if (libIndex <= 0) return path;

  final packageName = parts[libIndex - 1];
  final libPath = p.url.joinAll(parts.skip(libIndex + 1).followedBy([path]));
  return 'package:$packageName/$libPath';
}

String _packageName(String libPath) {
  final parts = p.split(p.normalize(libPath));
  final libIndex = parts.indexOf('lib');
  if (libIndex > 0) return parts[libIndex - 1];
  return p.basename(libPath);
}

String _injectableImport(TemplateContext context) {
  return context.config.dependencyInjection == DependencyInjection.injectable
      ? "import 'package:injectable/injectable.dart';\n"
      : '';
}

String _lazySingletonAnnotation(TemplateContext context) {
  return context.config.dependencyInjection == DependencyInjection.injectable
      ? '@lazySingleton\n'
      : '';
}
