import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../services/mqtt_service.dart';

class MqttProvider extends ChangeNotifier {
  final MqttService _mqttService = MqttService();

  String _host = '';
  int _port = 443;
  String _username = '';
  String _password = '';
  String _clientId = 'flutter_iot_app';

  bool _isConnecting = false;
  MqttConnectionState _state = MqttConnectionState.disconnected;

  MqttService get service => _mqttService;
  String get host => _host;
  int get port => _port;
  String get username => _username;
  String get password => _password;
  String get clientId => _clientId;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _state == MqttConnectionState.connected;
  MqttConnectionState get state => _state;

  MqttProvider() {
    _mqttService.connectionStream.listen((state) {
      _state = state;
      notifyListeners();
    });
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('mqtt_host') ?? '';
    _port = prefs.getInt('mqtt_port') ?? 443;
    _username = prefs.getString('mqtt_username') ?? '';
    _password = prefs.getString('mqtt_password') ?? '';
    _clientId = prefs.getString('mqtt_client_id') ?? '';
    if (_clientId.isEmpty || _clientId == 'flutter_iot_app') {
      // Generate unique client ID per device to avoid MQTT broker conflicts
      final rng = Random();
      final suffix = List.generate(8, (_) => rng.nextInt(16).toRadixString(16)).join();
      _clientId = 'flutter_iot_$suffix';
      await prefs.setString('mqtt_client_id', _clientId);
    }
    notifyListeners();

    // Auto-connect if saved credentials exist
    if (_host.isNotEmpty && _username.isNotEmpty && _password.isNotEmpty) {
      await connect();
    }
  }

  Future<void> saveSettings({
    required String host,
    required int port,
    required String username,
    required String password,
    String? clientId,
  }) async {
    _host = host;
    _port = port;
    _username = username;
    _password = password;
    if (clientId != null) _clientId = clientId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_host', _host);
    await prefs.setInt('mqtt_port', _port);
    await prefs.setString('mqtt_username', _username);
    await prefs.setString('mqtt_password', _password);
    await prefs.setString('mqtt_client_id', _clientId);
    notifyListeners();
  }

  Future<bool> connect() async {
    if (_host.isEmpty || _username.isEmpty) return false;
    _isConnecting = true;
    notifyListeners();

    final result = await _mqttService.connect(
      host: _host,
      port: _port,
      username: _username,
      password: _password,
      clientId: _clientId,
    );

    _isConnecting = false;
    notifyListeners();
    return result;
  }

  void disconnect() {
    _mqttService.disconnect();
    _state = MqttConnectionState.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _mqttService.dispose();
    super.dispose();
  }
}
