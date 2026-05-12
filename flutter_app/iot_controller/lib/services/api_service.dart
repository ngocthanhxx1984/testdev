import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  String _baseUrl = '';
  String _token = '';

  String get baseUrl => _baseUrl;
  String get token => _token;
  bool get hasToken => _token.isNotEmpty;
  bool get isConfigured => _baseUrl.isNotEmpty;

  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('api_base_url') ?? '';
    _token = prefs.getString('api_token') ?? '';
  }

  Future<void> saveBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _baseUrl);
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_token', token);
  }

  Future<void> clearToken() async {
    _token = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_token');
  }

  HttpClient _createClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    // Accept self-signed certificates for dev
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    if (_baseUrl.isEmpty) {
      throw ApiException('Server URL not configured');
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final client = _createClient();

    try {
      late HttpClientRequest request;
      switch (method) {
        case 'GET':
          request = await client.getUrl(uri);
          break;
        case 'POST':
          request = await client.postUrl(uri);
          break;
        case 'PUT':
          request = await client.putUrl(uri);
          break;
        case 'PATCH':
          request = await client.patchUrl(uri);
          break;
        case 'DELETE':
          request = await client.deleteUrl(uri);
          break;
        default:
          throw ApiException('Unknown method: $method');
      }

      request.headers.set('Content-Type', 'application/json');
      if (_token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $_token');
      }

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (responseBody.isEmpty) {
        return {'_statusCode': response.statusCode};
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      json['_statusCode'] = response.statusCode;

      if (response.statusCode >= 400) {
        throw ApiException(
          json['error'] as String? ?? 'Request failed (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }

      return json;
    } on ApiException {
      rethrow;
    } on SocketException catch (e) {
      throw ApiException('Connection failed: ${e.message}');
    } catch (e) {
      throw ApiException('Request error: $e');
    } finally {
      client.close();
    }
  }

  // --- Auth ---
  Future<Map<String, dynamic>> register(String username, String password, {String? email}) async {
    final result = await _request('POST', '/api/auth/register', body: {
      'username': username,
      'password': password,
      if (email != null) 'email': email,
    });
    if (result['token'] != null) {
      await saveToken(result['token'] as String);
    }
    return result;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final result = await _request('POST', '/api/auth/login', body: {
      'username': username,
      'password': password,
    });
    if (result['token'] != null) {
      await saveToken(result['token'] as String);
    }
    return result;
  }

  Future<Map<String, dynamic>> getMe() async {
    return _request('GET', '/api/auth/me');
  }

  Future<void> logout() async {
    await clearToken();
  }

  // --- Devices ---
  Future<List<Map<String, dynamic>>> getDevices() async {
    final result = await _request('GET', '/api/devices');
    // The response is an array, but our _request parses as Map
    // We need to handle array response differently
    return [];
  }

  Future<List<dynamic>> fetchDevices() async {
    if (_baseUrl.isEmpty) return [];
    final uri = Uri.parse('$_baseUrl/api/devices');
    final client = _createClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      if (_token.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $_token');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(body) as List<dynamic>;
      }
    } catch (e) {
      // Silently fail — devices come from MQTT discovery mainly
    } finally {
      client.close();
    }
    return [];
  }

  Future<Map<String, dynamic>> sendCommand(String deviceId, String feature, bool state) async {
    return _request('POST', '/api/devices/$deviceId/command', body: {
      'feature': feature,
      'state': state,
    });
  }

  Future<Map<String, dynamic>> updateDevice(String deviceId, {String? name, String? deviceType}) async {
    return _request('PUT', '/api/devices/$deviceId', body: {
      if (name != null) 'name': name,
      if (deviceType != null) 'device_type': deviceType,
    });
  }

  // --- Automations ---
  Future<List<dynamic>> fetchAutomations() async {
    if (_baseUrl.isEmpty || _token.isEmpty) return [];
    final uri = Uri.parse('$_baseUrl/api/automations');
    final client = _createClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $_token');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(body) as List<dynamic>;
      }
    } catch (e) {
      // silently fail
    } finally {
      client.close();
    }
    return [];
  }

  Future<Map<String, dynamic>> createAutomation(Map<String, dynamic> data) async {
    return _request('POST', '/api/automations', body: data);
  }

  Future<Map<String, dynamic>> updateAutomation(String id, Map<String, dynamic> data) async {
    return _request('PUT', '/api/automations/$id', body: data);
  }

  Future<Map<String, dynamic>> toggleAutomation(String id) async {
    return _request('PATCH', '/api/automations/$id/toggle');
  }

  Future<void> deleteAutomation(String id) async {
    await _request('DELETE', '/api/automations/$id');
  }

  Future<Map<String, dynamic>> startCountdown(String id) async {
    return _request('POST', '/api/automations/$id/countdown/start');
  }

  Future<Map<String, dynamic>> cancelCountdown(String id) async {
    return _request('POST', '/api/automations/$id/countdown/cancel');
  }

  // --- Logs ---
  Future<List<dynamic>> fetchDeviceLogs({String? deviceId, int limit = 50}) async {
    if (_baseUrl.isEmpty || _token.isEmpty) return [];
    final params = <String, String>{'limit': limit.toString()};
    if (deviceId != null) params['device_id'] = deviceId;
    final uri = Uri.parse('$_baseUrl/api/logs/devices').replace(queryParameters: params);
    final client = _createClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer $_token');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(body) as List<dynamic>;
      }
    } catch (e) {
      // silently fail
    } finally {
      client.close();
    }
    return [];
  }

  Future<List<dynamic>> fetchAutomationLogs({int limit = 50}) async {
    if (_baseUrl.isEmpty || _token.isEmpty) return [];
    final uri = Uri.parse('$_baseUrl/api/logs/automations?limit=$limit');
    final client = _createClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer $_token');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(body) as List<dynamic>;
      }
    } catch (e) {
      // silently fail
    } finally {
      client.close();
    }
    return [];
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}
