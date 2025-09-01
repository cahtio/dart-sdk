import 'package:get_it/get_it.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tinode/src/models/server-messages.dart';
import 'package:tinode/src/models/auth-token.dart';
import 'package:tinode/src/services/database_manager.dart';

class AuthService {
  String? _userId;
  String? _lastLogin;
  AuthToken? _authToken;
  bool _authenticated = false;

  late DatabaseManager _databaseManager;

  PublishSubject<OnLoginData> onLogin = PublishSubject<OnLoginData>();

  AuthService() {
    _databaseManager = GetIt.I.get<DatabaseManager>();
  }

  bool get isAuthenticated {
    return _authenticated;
  }

  AuthToken? get authToken {
    return _authToken;
  }

  String? get userId {
    return _userId;
  }

  String? get lastLogin {
    return _lastLogin;
  }

  void setLastLogin(String lastLogin) {
    _lastLogin = lastLogin;
  }

  void setAuthToken(AuthToken authToken) {
    _authToken = authToken;
  }

  void setUserId(String? userId) {
    _userId = userId;
  }

  void onLoginSuccessful(CtrlMessage? ctrl) async {
    if (ctrl == null) {
      return;
    }

    var params = ctrl.params;
    print('params');
    print(params);
    if (params == null || params['user'] == null) {
      return;
    }

    _userId = params['user'];
    _authenticated = (ctrl.code ?? 0) >= 200 && (ctrl.code ?? 0) < 300;

    if (params['token'] != null && params['expires'] != null) {
      _authToken = AuthToken(
        params['token'],
        DateTime.parse(params['expires']),
      );
    } else {
      _authToken = null;
    }

    await _databaseManager.setUid(userId);

    var code = ctrl.code;
    var text = ctrl.text;
    if (code != null && text != null) {
      onLogin.add(OnLoginData(code, text));
    }
  }
}
