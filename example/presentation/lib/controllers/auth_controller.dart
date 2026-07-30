import 'package:domain/features/auth/usecases/get_auth_list_use_case.dart';
import 'package:get_it/get_it.dart';

class AuthController {
  final _getAuthListUseCase = GetIt.instance.get<GetAuthListUseCase>();

  var items = const <String>[];

  Future<void> load() async {
    final entities = await _getAuthListUseCase();
    items = entities.map((entity) => entity.remoteId).toList(growable: false);
  }
}
