# clean_architect

A configurable Dart CLI generator for Clean Architecture Flutter/Dart projects.

`clean_architect` generates boring, predictable architecture files that you can edit immediately. The generator does not try to hide your app behind runtime abstractions. The flexibility lives in `clean_architect.yaml`: paths, layer layout, state management, network client, local storage, model style, and dependency injection style.

## Install

```sh
dart pub global activate clean_architect
```

After global activation you can run the executable from any folder:

```sh
clean_architect init
clean_architect create architecture
clean_architect create auth
clean_architect create feature orders
```

## Empty Folder Usage

Use the global executable when generating into an empty folder:

```sh
mkdir my_app
cd my_app
clean_architect create architecture
```

Do not use `dart run clean_architect ...` in an empty folder. `dart run` needs a local `pubspec.yaml` before the CLI can start. Use `dart run clean_architect ...` only when developing this package from its own checkout or from another Dart project that already has a `pubspec.yaml`.

## Commands

```sh
clean_architect --version
clean_architect <command> --help
clean_architect create feature --help
clean_architect init
clean_architect scan
clean_architect doctor
clean_architect create architecture
clean_architect create base
clean_architect create auth
clean_architect create feature <name>
clean_architect create usecase <name> --feature <feature>
clean_architect create repository <feature>
clean_architect create remote-function <name> --feature <feature>
clean_architect create local-function <name> --feature <feature>
clean_architect create cached-function <name> --feature <feature>
```

Examples:

```sh
clean_architect init
clean_architect scan
clean_architect create architecture
clean_architect create feature orders
clean_architect create auth
clean_architect create usecase login --feature auth
clean_architect create repository auth
clean_architect create remote-function loadDetails --feature orders
clean_architect create local-function readDraft --feature orders
clean_architect create cached-function syncDetails --feature orders
clean_architect doctor
```

Useful flags:

```sh
clean_architect init --dry-run
clean_architect init --force

clean_architect scan
clean_architect scan --write
clean_architect scan --json
clean_architect scan --root packages/my_app
clean_architect scan --write --force

clean_architect create architecture --dry-run
clean_architect create auth --dry-run
clean_architect create auth --overwrite
clean_architect create auth --force
clean_architect create feature profile --skip-presentation

clean_architect create auth --state getx
clean_architect create auth --state bloc
clean_architect create auth --state provider
clean_architect create auth --state none
clean_architect create auth --network dio
clean_architect create auth --network abstract
clean_architect create auth --storage secure_storage
clean_architect create auth --storage shared_preferences
clean_architect create auth --storage hive
clean_architect create auth --storage objectbox
clean_architect create auth --storage abstract
clean_architect create auth --di injectable
clean_architect create auth --dependency-injection manual
clean_architect create feature orders --use-either-failure
clean_architect create feature orders --no-use-either-failure
clean_architect create architecture --flutter-create --platforms android,ios
clean_architect create auth --flutter-create --platforms android,ios,web
```

`--overwrite` and `--force` are required before conflicting generated files are replaced. Complete features and identical generated files are treated as idempotent no-ops.

## Configuration File

Run:

```sh
clean_architect init
```

This creates `clean_architect.yaml`:

<!-- BEGIN GENERATED:default-config -->
```yaml
clean_architect:
  config_version: 1
  structure: layered_packages # layered_packages, feature_first, or vertical_packages
  data_layout: source_first # source_first or type_first
  state_management: getx # getx, bloc, provider, or none
  network: dio # dio or abstract
  local_storage: secure_storage # secure_storage, shared_preferences, hive, objectbox, or abstract
  dependency_injection: manual # manual or injectable
  use_asset_generator: true
  use_either_failure: false
  flutter:
    create_presentation: false
    platforms:
      - android
      - ios
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
    app: app/lib
    core: packages/core/lib
    features: packages/features
```
<!-- END GENERATED:default-config -->

### Configuration Reference

| Key | Values | Default | What it controls |
| --- | --- | --- | --- |
| `config_version` | positive integer | `1` | Configuration schema version used for future migrations. |
| `structure` | `layered_packages`, `feature_first`, `vertical_packages` | `layered_packages` | How feature paths and package boundaries are resolved. |
| `data_layout` | `source_first`, `type_first` | `source_first` | Whether data files are grouped by source first or by artifact type first. |
| `state_management` | `getx`, `bloc`, `provider`, `none` | `getx` | Presentation controller/page style. |
| `network` | `dio`, `abstract` | `dio` | Remote data source style and generated data dependencies. |
| `local_storage` | `secure_storage`, `shared_preferences`, `hive`, `objectbox`, `abstract` | `secure_storage` | Local auth credential storage style and generated storage dependencies. |
| `dependency_injection` | `manual`, `injectable` | `manual` | Manual DI builder files or injectable/get_it setup files and annotations. |
| `use_asset_generator` | `true`, `false` | `true` | Whether presentation gets `asset_generator_kit.yaml` and the asset generator dependency. |
| `use_either_failure` | `true`, `false` | `false` | Whether generated repositories, repository implementations, and use cases return `Future<Either<Failure, T>>`. |
| `flutter.create_presentation` | `true`, `false` | `false` | Whether to run `flutter create .` inside presentation, or inside app for `vertical_packages`. |
| `flutter.platforms` | list or comma-separated text | `android`, `ios` | Platforms passed to `flutter create . --platforms=...`. |
| `models.use_freezed` | `true`, `false` | `true` | Whether entities/DTOs use Freezed. |
| `models.use_json_serializable` | `true`, `false` | `true` | Whether DTO JSON methods use `json_serializable`; `false` uses manual serialization. |
| `paths.domain` | public path below `lib` | `domain/lib` | Domain layer feature root. `lib/src` is rejected because layers import each other. |
| `paths.data` | public path below `lib` | `data/lib/features` | Data layer feature root. |
| `paths.presentation` | public path below `lib` | `presentation/lib` | Presentation layer root. |
| `paths.di` | public path below `lib` | `di/lib` | Dependency injection layer root. |
| `paths.app` | public path below `lib` | `app/lib` | Runnable Flutter app root used by `vertical_packages`. |
| `paths.core` | public path below `lib` | `packages/core/lib` | Shared core package used by `vertical_packages`. |
| `paths.features` | relative package-parent path | `packages/features` | Parent directory for vertical feature packages. |

Use `abstract` when you want the source boundaries without a concrete local storage package.

CLI overrides are intentionally small and only affect the current command. They do not rewrite `clean_architect.yaml`.

## Generated Project Shape

The default `layered_packages` architecture is a multi-package Flutter/Dart
workspace shape:

```txt
my_app/
  domain/
    pubspec.yaml
    lib/
      features/
        base_feature/
          entities/
          repositories/
          usecases/

  data/
    pubspec.yaml
    lib/
      features/
        base_feature/
          remote/
            models/
          local/
            models/
          repositories/

  di/
    pubspec.yaml
    lib/

  presentation/
    pubspec.yaml
    analysis_options.yaml
    asset_generator_kit.yaml
    assets/
      images/
      icons/
    lib/
      main.dart
      widgets/
      pages/
      utils/
      controllers/
      constants/
```

Every layer gets its own `pubspec.yaml`:

- `domain` is a pure Dart package for entities, repository contracts, and use cases.
- `data` is a Dart/Flutter package for DTOs, remote data sources, local sources, mappers, and repository implementations.
- `di` is a Dart package that connects `domain` and `data` dependencies.
- `presentation` is a runnable Flutter package with `main.dart`, Flutter dependencies, and UI folders.

After generation, run Flutter setup inside `presentation` when you want a complete Flutter platform project:

```sh
cd presentation
flutter create .
flutter pub get
```

Or let `clean_architect` do the Flutter project bootstrap automatically:

```sh
clean_architect create architecture --flutter-create --platforms android,ios
```

The same behavior can be configured in `clean_architect.yaml`:

```yaml
clean_architect:
  flutter:
    create_presentation: true
    platforms:
      - android
      - ios
      - web
```

When enabled, the CLI runs `flutter create . --platforms=<platforms>` from the
generated `presentation/` package root, or from `app/` in `vertical_packages`
mode. `--dry-run` prints the command without executing it.
`--skip-presentation` disables this step for the current command.

Run `dart pub get` in the other layer packages as needed.

## Data Layer Layouts

`data_layout` changes only the internal organization of each feature's data
layer. Domain, presentation, DI, package roots, class names, and command
behavior remain unchanged.

The default `source_first` mode keeps each model beside its source category:

```yaml
clean_architect:
  data_layout: source_first
```

```txt
data/lib/features/orders/
  remote/
    models/
      orders_dto.dart
    orders_remote_data_source.dart
  local/
    models/
      orders_box.dart
    orders_local_data_source.dart
  mappers/
  repositories/
```

Use `type_first` to keep models and data sources in separate top-level
directories:

```yaml
clean_architect:
  data_layout: type_first
```

```txt
data/lib/features/orders/
  data_sources/
    remote/
      orders_remote_data_source.dart
    local/
      orders_local_data_source.dart
  models/
    remote/
      orders_dto.dart
    local/
      orders_box.dart
  mappers/
  repositories/
```

The setting applies to `create architecture`, `create auth`, `create feature`,
all remote/local/cached operation commands, and generated Injectable
`DataModule` imports. It also works inside each feature package when
`structure: vertical_packages` is selected. Existing configurations that omit
the key continue to generate `source_first`.

## Generated Output Contract

These manifests are generated from the public Dart API and checked against this
README in the test suite. They are the authoritative file output for the default
configuration; narrative examples elsewhere describe selected files only.

### Architecture

<!-- BEGIN GENERATED:architecture -->
```txt
data/lib/features/base_feature/local/.gitkeep
data/lib/features/base_feature/local/models/.gitkeep
data/lib/features/base_feature/mappers/.gitkeep
data/lib/features/base_feature/remote/.gitkeep
data/lib/features/base_feature/remote/models/.gitkeep
data/lib/features/base_feature/repositories/.gitkeep
data/pubspec.yaml
di/lib/.gitkeep
di/lib/di.dart
di/pubspec.yaml
domain/lib/features/base_feature/entities/.gitkeep
domain/lib/features/base_feature/repositories/.gitkeep
domain/lib/features/base_feature/usecases/.gitkeep
domain/pubspec.yaml
presentation/analysis_options.yaml
presentation/asset_generator_kit.yaml
presentation/assets/icons/.gitkeep
presentation/assets/images/.gitkeep
presentation/lib/constants/.gitkeep
presentation/lib/controllers/.gitkeep
presentation/lib/main.dart
presentation/lib/pages/.gitkeep
presentation/lib/utils/.gitkeep
presentation/lib/widgets/.gitkeep
presentation/pubspec.yaml
```
<!-- END GENERATED:architecture -->

### Auth

<!-- BEGIN GENERATED:auth -->
```txt
data/lib/features/auth/local/auth_local_data_source.dart
data/lib/features/auth/local/models/auth_box.dart
data/lib/features/auth/mappers/auth_token_mapper.dart
data/lib/features/auth/remote/auth_remote_data_source.dart
data/lib/features/auth/remote/models/auth_token_dto.dart
data/lib/features/auth/remote/models/login_request_dto.dart
data/lib/features/auth/repositories/auth_repository_impl.dart
data/pubspec.yaml
di/lib/auth_di.dart
di/lib/di.dart
di/pubspec.yaml
domain/lib/features/auth/entities/auth_credentials_entity.dart
domain/lib/features/auth/entities/auth_token_entity.dart
domain/lib/features/auth/repositories/auth_repository.dart
domain/lib/features/auth/usecases/clear_auth_credentials_use_case.dart
domain/lib/features/auth/usecases/get_auth_credentials_use_case.dart
domain/lib/features/auth/usecases/login_use_case.dart
domain/lib/features/auth/usecases/logout_use_case.dart
domain/lib/features/auth/usecases/save_auth_credentials_use_case.dart
domain/pubspec.yaml
presentation/analysis_options.yaml
presentation/asset_generator_kit.yaml
presentation/assets/icons/.gitkeep
presentation/assets/images/.gitkeep
presentation/lib/constants/.gitkeep
presentation/lib/controllers/.gitkeep
presentation/lib/controllers/auth_controller.dart
presentation/lib/main.dart
presentation/lib/pages/.gitkeep
presentation/lib/pages/login_page.dart
presentation/lib/utils/.gitkeep
presentation/lib/widgets/.gitkeep
presentation/pubspec.yaml
```
<!-- END GENERATED:auth -->

### Generic Orders Feature

<!-- BEGIN GENERATED:feature-orders -->
```txt
data/lib/features/orders/local/models/orders_box.dart
data/lib/features/orders/local/orders_local_data_source.dart
data/lib/features/orders/mappers/orders_mapper.dart
data/lib/features/orders/remote/models/orders_dto.dart
data/lib/features/orders/remote/orders_remote_data_source.dart
data/lib/features/orders/repositories/orders_repository_impl.dart
data/pubspec.yaml
di/lib/di.dart
di/lib/orders_di.dart
di/pubspec.yaml
domain/lib/features/orders/entities/orders_entity.dart
domain/lib/features/orders/repositories/orders_repository.dart
domain/lib/features/orders/usecases/get_orders_list_use_case.dart
domain/pubspec.yaml
presentation/analysis_options.yaml
presentation/asset_generator_kit.yaml
presentation/assets/icons/.gitkeep
presentation/assets/images/.gitkeep
presentation/lib/constants/.gitkeep
presentation/lib/controllers/.gitkeep
presentation/lib/controllers/orders_controller.dart
presentation/lib/main.dart
presentation/lib/pages/.gitkeep
presentation/lib/pages/orders_page.dart
presentation/lib/utils/.gitkeep
presentation/lib/widgets/.gitkeep
presentation/pubspec.yaml
```
<!-- END GENERATED:feature-orders -->

### Remote Operation

<!-- BEGIN GENERATED:remote-operation -->
```txt
data/lib/features/orders/mappers/load_details_mapper.dart
data/lib/features/orders/remote/models/load_details_dto.dart
domain/lib/features/orders/entities/load_details_entity.dart
domain/lib/features/orders/usecases/load_details_use_case.dart
```
<!-- END GENERATED:remote-operation -->

### Local Operation

<!-- BEGIN GENERATED:local-operation -->
```txt
data/lib/features/orders/local/models/read_draft_box.dart
data/lib/features/orders/mappers/read_draft_mapper.dart
domain/lib/features/orders/entities/read_draft_entity.dart
domain/lib/features/orders/usecases/read_draft_use_case.dart
```
<!-- END GENERATED:local-operation -->

### Cached Operation

<!-- BEGIN GENERATED:cached-operation -->
```txt
data/lib/features/orders/local/models/sync_details_box.dart
data/lib/features/orders/mappers/sync_details_box_mapper.dart
data/lib/features/orders/mappers/sync_details_mapper.dart
data/lib/features/orders/remote/models/sync_details_dto.dart
domain/lib/features/orders/entities/sync_details_entity.dart
domain/lib/features/orders/usecases/stream_details_use_case.dart
domain/lib/features/orders/usecases/sync_details_use_case.dart
```
<!-- END GENERATED:cached-operation -->

## Flutter Presentation Bootstrap

By default, `clean_architect` creates the `presentation` package files but does not run Flutter tooling. This keeps generation fast and works even on machines without Flutter installed.

To generate Flutter platform folders automatically, use:

```sh
clean_architect create architecture --flutter-create --platforms android,ios
```

Supported platform names are the Flutter platform names: `android`, `ios`, `web`, `macos`, `windows`, and `linux`.

The YAML equivalent is:

```yaml
clean_architect:
  flutter:
    create_presentation: true
    platforms: android,ios
```

or:

```yaml
clean_architect:
  flutter:
    create_presentation: true
    platforms:
      - android
      - ios
```

This runs for commands that generate presentation structure: `create architecture`,
`create base`, `create auth`, and `create feature <name>`. It is skipped for
operation commands, `create usecase`, `create repository`, and commands using
`--skip-presentation`. In `vertical_packages`, Flutter scaffolding is created in
the configured app package.

## Structure Modes

### Default Layered Packages

```yaml
clean_architect:
  config_version: 1
  structure: layered_packages
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
```

`clean_architect create auth` creates:

```txt
domain/lib/features/auth/...
data/lib/features/auth/...
di/lib/auth_di.dart
di/lib/di.dart
presentation/lib/controllers/auth_controller.dart
presentation/lib/pages/login_page.dart
```

### Custom Layer Paths

You can point the layers to existing packages or app folders:

```yaml
clean_architect:
  config_version: 1
  structure: layered_packages
  paths:
    domain: packages/domain/lib/modules
    data: packages/data/lib/modules
    presentation: apps/customer_app/lib
    di: packages/di/lib
```

Then `clean_architect create feature profile` creates feature files under those configured roots.

### Feature First

`feature_first` is available for projects that still want feature-based grouping while keeping the same layer packages:

```yaml
clean_architect:
  config_version: 1
  structure: feature_first
  paths:
    domain: domain/lib
    data: data/lib/features
    presentation: presentation/lib
    di: di/lib
```

Feature-first resolution keeps the four layer packages while grouping each
feature inside every layer:

```txt
domain/lib/features/<feature>/...
data/lib/features/<feature>/...
presentation/lib/features/<feature>/pages/...
presentation/lib/features/<feature>/controllers/...
di/lib/features/<feature>/...
```

### Vertical Feature Packages

Use `vertical_packages` when features should be independent packages that own
all of their architecture layers:

```yaml
clean_architect:
  config_version: 1
  structure: vertical_packages
  state_management: bloc
  network: dio
  local_storage: hive
  dependency_injection: injectable
  use_asset_generator: false
  use_either_failure: true
  flutter:
    create_presentation: true
    platforms: [android, ios, web]
  models:
    use_freezed: true
    use_json_serializable: true
  paths:
    app: app/lib
    core: packages/core/lib
    features: packages/features
```

Then run:

```sh
clean_architect create architecture
clean_architect create auth
clean_architect create feature orders
```

The result is a runnable app shell, a stable shared core, and one package per
feature:

```txt
app/
  pubspec.yaml
  assets/
    icons/
    images/
  lib/
    main.dart
    app.dart
    constants/
    controllers/
    di/
    pages/
    routing/
    theme/
    utils/
    widgets/
  test/

packages/
  core/
    pubspec.yaml
    lib/
      core.dart
      src/
        errors/
        failures/
        logging/
        usecases/

  features/
    auth/
      pubspec.yaml
      lib/
        auth.dart
        src/
          domain/
            entities/
            repositories/
            usecases/
          data/
            remote/
              models/
            local/
              models/
            mappers/
            repositories/
          presentation/
            controllers/
            pages/
          di/
```

Every feature package has one `pubspec.yaml`, so its domain, data,
presentation, and DI code evolve together without cross-feature imports. The
app manifest is updated with an idempotent path dependency whenever auth, a
generic feature, or a standalone repository package is created. Injectable
configuration and Hive/ObjectBox providers live in each feature's
`lib/src/di/` folder.

Each package also gets a public barrel, such as `orders/lib/orders.dart`, which
exports its stable entities, repository contract, use cases, page, controller,
and DI entry point. Consumers import only the package API:

```dart
import 'package:orders/orders.dart';
```

Operation commands extend this barrel when they add new entities and use cases.

The generated `ARCHITECTURE.md` records these dependency rules:

1. The app may depend on core and feature packages.
2. A feature owns its domain, data, presentation, and DI code.
3. Features may depend on core but must not import one another.
4. Core must not depend on the app or any feature.

With Flutter creation enabled, the project is immediately runnable:

```sh
cd app
flutter pub get
flutter run
```

## `create architecture`

```sh
clean_architect create architecture
```

Generates the layer packages and default folders only. It does not generate auth code.

Default placeholder feature name:

```txt
domain/lib/features/base_feature
data/lib/features/base_feature
```

Use this when you want the clean architecture project skeleton first, then add features later.

## `create feature <name>`

```sh
clean_architect create feature orders
```

Generates a generic feature module.

Domain:

```txt
domain/lib/features/orders/entities/orders_entity.dart
domain/lib/features/orders/repositories/orders_repository.dart
domain/lib/features/orders/usecases/get_orders_list_use_case.dart
```

Data:

```txt
data/lib/features/orders/remote/models/orders_dto.dart
data/lib/features/orders/remote/orders_remote_data_source.dart
data/lib/features/orders/local/models/orders_box.dart
data/lib/features/orders/local/orders_local_data_source.dart
data/lib/features/orders/mappers/orders_mapper.dart
data/lib/features/orders/repositories/orders_repository_impl.dart
```

Presentation, unless `--skip-presentation` is used:

```txt
presentation/lib/controllers/orders_controller.dart
presentation/lib/pages/orders_page.dart
```

The generic feature is intentionally minimal: entity, DTO, mapper, repository contract, repository implementation, list use case, local source, Retrofit remote data source, controller, and page. Its `OrdersViewItem` is a real widget declared in `orders_page.dart`, so a one-off UI element does not get its own file.

## `create auth`

```sh
clean_architect create auth
```

Generates a concrete auth starter feature.

Domain:

```txt
domain/lib/features/auth/entities/auth_token_entity.dart
domain/lib/features/auth/entities/auth_credentials_entity.dart
domain/lib/features/auth/repositories/auth_repository.dart
domain/lib/features/auth/usecases/login_use_case.dart
domain/lib/features/auth/usecases/logout_use_case.dart
domain/lib/features/auth/usecases/save_auth_credentials_use_case.dart
domain/lib/features/auth/usecases/get_auth_credentials_use_case.dart
domain/lib/features/auth/usecases/clear_auth_credentials_use_case.dart
```

Data:

```txt
data/lib/features/auth/remote/models/auth_token_dto.dart
data/lib/features/auth/remote/models/login_request_dto.dart
data/lib/features/auth/remote/auth_remote_data_source.dart
data/lib/features/auth/local/models/auth_box.dart
data/lib/features/auth/local/auth_local_data_source.dart
data/lib/features/auth/mappers/auth_token_mapper.dart
data/lib/features/auth/repositories/auth_repository_impl.dart
```

Presentation, unless `--skip-presentation` is used:

```txt
presentation/lib/controllers/auth_controller.dart
presentation/lib/pages/login_page.dart
```

Login form data is generated as `LoginState` in `auth_controller.dart`; it is
not emitted as a non-widget file under `widgets/`.

The generated remote remote data source uses Dio + Retrofit style:

```dart
@lazySingleton
@RestApi(baseUrl: '')
abstract class AuthRemoteDataSource {
  @factoryMethod
  factory AuthRemoteDataSource(@Named("auth_dio") Dio dio) = _AuthRemoteDataSource;

  @POST('/authorization/token/')
  Future<AuthTokenDto> login(@Body() Map<String, dynamic> body);
}
```

The generated auth controller uses `GetIt.instance.get<LoginUseCase>()`, and the GetX page registers the controller in `initState` with `Get.put(AuthController())`.

## Operation Commands

Operation commands add a new function to an existing feature. They generate the required entity/model/usecase support files and patch the existing source, repository, repository implementation, and controller files.

### Remote Function

```sh
clean_architect create remote-function loadDetails --feature orders
```

Aliases: `remote-function`, `remote-method`.

Adds:

```txt
domain/lib/features/orders/entities/load_details_entity.dart
domain/lib/features/orders/usecases/load_details_use_case.dart
data/lib/features/orders/remote/models/load_details_dto.dart
data/lib/features/orders/mappers/load_details_mapper.dart
```

Patches:

```txt
data/lib/features/orders/remote/orders_remote_data_source.dart
domain/lib/features/orders/repositories/orders_repository.dart
data/lib/features/orders/repositories/orders_repository_impl.dart
presentation/lib/controllers/orders_controller.dart
```

### Local Function

```sh
clean_architect create local-function readDraft --feature orders
```

Aliases: `local-function`, `local-method`.

Adds:

```txt
domain/lib/features/orders/entities/read_draft_entity.dart
domain/lib/features/orders/usecases/read_draft_use_case.dart
data/lib/features/orders/local/models/read_draft_box.dart
data/lib/features/orders/mappers/read_draft_mapper.dart
```

Patches the local source, repository contract, repository implementation, and controller.

### Cached Function

```sh
clean_architect create cached-function syncDetails --feature orders
```

Aliases: `cached-function`, `cached-method`.

Adds remote and local support together:

```txt
domain/lib/features/orders/entities/sync_details_entity.dart
domain/lib/features/orders/usecases/sync_details_use_case.dart
domain/lib/features/orders/usecases/stream_details_use_case.dart
data/lib/features/orders/remote/models/sync_details_dto.dart
data/lib/features/orders/local/models/sync_details_box.dart
data/lib/features/orders/mappers/sync_details_mapper.dart
data/lib/features/orders/mappers/sync_details_box_mapper.dart
```

Patches the remote source with `syncDetails()`, the local source with
`streamDetails()`, and uses those same names in the repository, use cases,
repository implementation, and controller. The generated use cases are
`SyncDetailsUseCase` and `StreamDetailsUseCase`.

## Dependency Injection Modes

### Manual

```yaml
dependency_injection: manual
```

Manual mode generates a single GetIt bootstrap plus editable per-feature
registration files:

```txt
di/lib/di.dart
di/lib/auth_di.dart
di/lib/orders_di.dart
```

`initDi` initializes every feature's data dependencies first and domain use
cases second. Local storage is awaited before remote sources and repositories
are registered. Generated registrations use `isRegistered` guards, so startup
and generator reruns remain idempotent. Presentation calls the bootstrap before
`runApp`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await initDi(get: GetIt.instance);
runApp(const CleanArchitectApp());
```

Creating another feature patches the root bootstrap. Creating a use case or an
operation patches that feature's domain registrations. In `vertical_packages`,
the equivalent bootstrap lives at `app/lib/di/bootstrap.dart` and each feature
exports its registration functions from its public library.

### Injectable

```yaml
dependency_injection: injectable
```

Injectable mode adds injectable/get_it dependencies and generates injector entry files:

```txt
domain/lib/injector.dart
data/lib/injector.dart
di/lib/di.dart
```

Generated classes receive injectable annotations where supported. After generation, run build runner in the generated packages that contain injectable/freezed/json_serializable code.

```sh
cd domain
dart run build_runner build
cd ../data
dart run build_runner build
```

In `vertical_packages`, each feature has one injector and data module:

```txt
packages/features/orders/lib/src/di/injector.dart
packages/features/orders/lib/src/di/data_module.dart
```

Run build runner from that feature package:

```sh
cd packages/features/orders
dart run build_runner build --delete-conflicting-outputs
```

## Either / Failure Return Type

```yaml
use_either_failure: true
```

When enabled, generated repository contracts, repository implementations, and use cases use:

```dart
Future<Either<Failure, T>>
```

instead of:

```dart
Future<T>
```

The generator also creates `domain/lib/failures/failure.dart` where needed and
adds `dartz` to generated layer pubspecs. Vertical features reuse the shared
`Failure` from `packages/core`. You can override the value for one command with
`--use-either-failure` or `--no-use-either-failure`.

## Model Modes

### Freezed + JSON Serializable

```yaml
models:
  use_freezed: true
  use_json_serializable: true
```

Entities and DTOs use Freezed. DTOs also include JSON serialization parts when JSON serialization is enabled.

Typical follow-up command in generated packages:

```sh
dart run build_runner build
```

### Plain Dart Fallback

```yaml
models:
  use_freezed: false
  use_json_serializable: false
```

Entities and DTOs are generated as simple Dart classes.

## State Management

### GetX

```yaml
state_management: getx
```

Presentation controllers extend `GetxController`, pages use `Get.put(...)`, `Get.find(...)`, and reactive values where needed.

### Bloc

```yaml
state_management: bloc
```

Presentation controllers use `flutter_bloc` with event/state classes, and pages use `BlocProvider`/`BlocBuilder`.

### Provider

```yaml
state_management: provider
```

Presentation controllers extend `ChangeNotifier`, and pages use `ChangeNotifierProvider`/`Consumer`.

### None

```yaml
state_management: none
```

Presentation files are generated without state management package wiring. This is useful when you want to connect another state system manually.

## Network

### Dio

```yaml
network: dio
```

Generated remote services use Dio + Retrofit imports and annotations. The data package receives the relevant dependencies.

### Abstract

```yaml
network: abstract
```

Use this when you want the generated repositories and source boundaries but plan to implement networking yourself.

## Local Storage

### Secure Storage

```yaml
local_storage: secure_storage
```

Auth local source uses `flutter_secure_storage` for credential persistence.

### Hive

```yaml
local_storage: hive
```

The data package uses the maintained Hive CE runtime and generator packages.
Local sources can initialize their boxes directly. Injectable projects get a
generated module that initializes Hive, registers each adapter with a stable
type ID, opens each box, and provides the box to its local data source:

```txt
data/lib/data_module.dart
```

Adding another Hive feature or local/cached operation updates the same module
with the additional adapter and box provider.

Generated local models keep an integer `id` for the Hive/ObjectBox database key
and a String `remoteId` for the API identity. DTO `id` values map to
`Entity.remoteId` and `Box.remoteId`, so remote identifiers never overwrite local
database keys.

### ObjectBox

```yaml
local_storage: objectbox
```

The data package gets ObjectBox dependencies, local sources can initialize their box from a Store, and injectable projects get a generated module:

```txt
data/lib/data_module.dart
```

Run build runner in the data package after adding ObjectBox entities so `objectbox.g.dart` can be generated.

### Abstract

```yaml
local_storage: abstract
```

Auth local source contains TODO methods so you can wire a custom persistence mechanism yourself.

## Dependency Compatibility

Version 0.3.0 emits only the dependencies required by the selected
configuration. Runtime packages use their current stable releases. Builder
packages use the newest mutually compatible stable set verified against
generated Flutter projects:

```txt
build_runner: ^2.15.1
freezed: ^3.2.5
injectable_generator: ^3.0.2
hive_ce_generator: 1.11.1
```

Some newer individual builder releases target incompatible analyzer versions.
These constraints avoid prerelease transitive dependencies while allowing
Freezed, Retrofit, Injectable, and Hive CE generation to run together.

## Presentation Package

The generated presentation package includes:

```txt
presentation/lib/main.dart
presentation/lib/widgets/
presentation/lib/pages/
presentation/lib/utils/
presentation/lib/controllers/
presentation/lib/constants/
presentation/assets/images/
presentation/assets/icons/
```

When `use_asset_generator: true`, it also includes:

```txt
presentation/asset_generator_kit.yaml
```

and adds `assetgeneratorkit` to `presentation/pubspec.yaml`.

## Safety

Every generation command builds a complete in-memory plan first. Names,
configuration, required features, duplicate outputs, and filesystem conflicts
are validated before the first file is written. If any conflict is found, the
command aborts without partially generating the remaining files.

Identical files are left untouched, and rerunning a completed feature or
operation is an idempotent no-op. Operation commands require the feature to
already exist:

```sh
clean_architect create feature orders
clean_architect create cached-function syncCatalog --feature orders
```

By default, conflicting existing files are not overwritten.

Preview generated files:

```sh
clean_architect create auth --dry-run
```

Overwrite intentionally:

```sh
clean_architect create auth --overwrite
```

or:

```sh
clean_architect create auth --force
```

## Scan Existing Projects

```sh
clean_architect scan
```

`scan` discovers architecture from the project itself. It reads nested
`pubspec.yaml` files, package path dependencies, feature directory signatures,
source imports and annotations, Flutter entry points, and platform folders. It
can detect:

- `layered_packages`, `feature_first`, and `vertical_packages` structures.
- Domain, data, presentation, DI, app, core, and features paths.
- `source_first` and `type_first` data layouts.
- GetX, Bloc, Provider, or no generated state-management integration.
- Dio/Retrofit, local-storage packages, manual GetIt, and Injectable.
- Freezed, json_serializable, `Either<Failure, T>`, and asset generation.
- Existing Flutter platform folders.

The default command is read-only. Every structural path is reported with a
confidence level:

```txt
Detected architecture: layered_packages
Confidence: high

Paths:
  domain: domain/lib (high)
  data: data/lib/features (high)
  presentation: presentation/lib (high)
  di: di/lib (high)

Configuration differences:
  dependency_injection: manual -> injectable
```

When differences are listed, generation continues to use the existing YAML
until you explicitly apply the detected values. This makes stale settings such
as manual DI in an Injectable project visible before a create command runs.

Create or update the configuration explicitly:

```sh
clean_architect scan --write
```

Existing comments and unknown YAML keys are preserved. The rendered file is
validated before it replaces the previous configuration. If structural paths
are ambiguous, the scanner reports its selected candidates and requires an
explicit review followed by:

```sh
clean_architect scan --write --force
```

For tooling and CI integrations, request structured output or scan another
root without changing the current directory:

```sh
clean_architect scan --json
clean_architect scan --root packages/my_app
```

`--force` does not make an incomplete scan writable. Domain, data,
presentation, and DI packages must all be identified for layered structures;
vertical structures require app, core, and a shared feature-package parent.

## Doctor

```sh
clean_architect doctor
```

`doctor` validates the complete generated project:

- Every configured package root and layer path exists and is structurally valid.
- Each layer has a readable `pubspec.yaml` whose package name matches its root.
- Required dependencies and dev dependencies are present with compatible version constraints.
- Local path dependencies resolve to the configured domain, data, and DI packages.
- The active Dart and Flutter versions satisfy the generated package constraints.
- `build_runner` is declared and resolved in every package that needs it.
- Every referenced generated `.g.dart` file exists.
- Vertical app, core, and every discovered feature package are checked.

A healthy project exits with code `0`. Failed validation exits with code `1`, so
`clean_architect doctor` can be used directly in CI.

## Integration Test Matrix

The integration suite generates complete projects in temporary directories,
then runs dependency resolution, code generation, analysis in every layer, and the project doctor.

| Scenario | Coverage |
| --- | --- |
| `default_getx_manual_dio_secure` | Layered packages, GetX, manual DI, Dio, secure storage |
| `bloc_injectable_hive_feature_first` | Feature first, Bloc, Injectable, Hive CE |
| `provider_injectable_objectbox` | Layered packages, type-first data layout, Provider, Injectable, ObjectBox |
| `getx_manual_objectbox` | Layered packages, type-first data layout, GetX, manual GetIt registration, ObjectBox |
| `none_abstract_plain_feature_first` | Feature first, no state package, abstract sources, plain Dart models |
| `either_enabled` | Layered packages with `Either<Failure, T>` returns |
| `shared_preferences_json_only_custom_paths` | Shared preferences, JSON-only models, and custom public layer paths |
| `freezed_without_json` | Freezed-only models, Injectable, and manual JSON methods |
| `vertical_bloc_injectable_hive_either` | Vertical feature packages, type-first data layout, runnable app/core packages, Bloc, Injectable, Hive CE, and Either |

Normal `dart test` runs skip these expensive cases. Run the full matrix with:

```sh
CLEAN_ARCHITECT_INTEGRATION=all dart test test/integration/generated_project_matrix_test.dart
```

Run one scenario while developing:

```sh
CLEAN_ARCHITECT_INTEGRATION=provider_injectable_objectbox dart test test/integration/generated_project_matrix_test.dart
```

Keep generated projects after success for manual inspection:

```sh
CLEAN_ARCHITECT_INTEGRATION=all CLEAN_ARCHITECT_KEEP_INTEGRATION_PROJECTS=true dart test test/integration/generated_project_matrix_test.dart
```

Every scenario creates the architecture, auth, an `orders` feature, standalone
use case and repository files, and all three operation types. It reruns every
generation command without allowing any file changes, then resolves dependencies,
runs builders and analysis, and requires `clean_architect doctor` to pass. GitHub
Actions runs each scenario as a separate matrix job. The vertical scenario also
generates a real Flutter web scaffold, runs its widget tests, and builds the app.

## 1.0 Stability Contract

Version `1.0.0` establishes the stable interface. Existing commands, options,
configuration keys, generated package roots, and exported Dart APIs follow the
compatibility and deprecation policy below.

### Frozen CLI surface

| Command | Status |
| --- | --- |
| `init` | Supported |
| `scan` | Supported |
| `doctor` | Supported |
| `create architecture` | Supported |
| `create auth` | Supported |
| `create feature <name>` | Supported |
| `create usecase <name> --feature <feature>` | Supported |
| `create repository <feature>` | Supported |
| `create remote-function <name> --feature <feature>` | Supported |
| `create local-function <name> --feature <feature>` | Supported |
| `create cached-function <name> --feature <feature>` | Supported |

`create base`, `remote-method`, `local-method`, `cached-method`, and `--di`
remain supported compatibility aliases. Canonical names are used in new
documentation and examples.

### Frozen public Dart API

Import supported APIs from:

```dart
import 'package:clean_architect/clean_architect.dart';
```

The 1.0 public surface includes the configuration enums and value objects,
`CleanArchitectGenerator`, `GeneratedFile`, `OperationKind`, `PathResolver`,
`FeaturePaths`, `ProjectDoctor`, its diagnostic/report types,
`ProjectScanner`, `ProjectScanResult`, `ScanFinding`, `ScanDiagnostic`,
`ScanConfigWriter`,
`currentConfigVersion`, and `packageVersion`. Files below `lib/src` are
implementation details and are not covered by compatibility guarantees.

### Backward compatibility and upgrades

- Patch releases fix defects without intentionally changing generated output.
- Minor releases may add commands, options, configuration keys, templates, or
  public APIs. Existing valid configuration remains valid.
- A command, key, alias, or public API must be deprecated for at least one
  minor release before removal.
- Breaking changes are reserved for a new major version after 1.0.
- Generated source is owned by the consuming project. Upgrading the CLI never
  rewrites existing files unless the user explicitly passes `--force` or
  `--overwrite`.
- `config_version` controls schema migrations independently from the package
  version. New optional keys retain defaults; incompatible schema changes
  increment `config_version` and include migration instructions.
- Golden snapshots protect representative generated output. Intentional
  template changes must update the corresponding goldens and changelog.

Before upgrading, commit the consuming project, update `clean_architect`, run
`clean_architect doctor`, preview generation with `--dry-run`, and review any
intentional snapshot-level output changes described in the changelog.

## Runnable Example

[`example/`](example/) is a checked-in generated project with `domain`, `data`,
`di`, and a Flutter `presentation` package. It can be launched with:

```sh
cd example/presentation
flutter pub get
flutter run -d chrome
```

CI resolves and analyzes this example and builds its web target on every
change.

## Publishing / Development Notes

When working on this package locally:

```sh
dart format lib test bin
dart analyze
dart test
UPDATE_GOLDENS=true dart test test/golden_generation_test.dart
UPDATE_README_CONTRACTS=true dart test test/readme_contract_test.dart
dart pub publish --dry-run
```

Run `dart pub publish --dry-run` before publishing to verify pub.dev metadata and package contents.
