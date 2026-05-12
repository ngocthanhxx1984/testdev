import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  String? _userId;
  String? _username;
  String? _displayName;
  bool _isLoading = false;
  String? _error;

  String? get userId => _userId;
  String? get username => _username;
  String? get displayName => _displayName;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _api.hasToken && _userId != null;

  Future<void> tryAutoLogin() async {
    await _api.loadSettings();
    if (!_api.hasToken || !_api.isConfigured) return;

    try {
      final result = await _api.getMe();
      _userId = result['id'] as String?;
      _username = result['username'] as String?;
      _displayName = result['displayName'] as String?;
      notifyListeners();
    } catch (e) {
      // Token expired or invalid
      await _api.clearToken();
      debugPrint('[AUTH] Auto-login failed: $e');
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.login(username, password);
      final user = result['user'] as Map<String, dynamic>;
      _userId = user['id'] as String?;
      _username = user['username'] as String?;
      _displayName = user['displayName'] as String?;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Connection failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String username, String password, {String? email}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.register(username, password, email: email);
      final user = result['user'] as Map<String, dynamic>;
      _userId = user['id'] as String?;
      _username = user['username'] as String?;
      _displayName = user['displayName'] as String?;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Connection failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _api.logout();
    _userId = null;
    _username = null;
    _displayName = null;
    notifyListeners();
  }
}
