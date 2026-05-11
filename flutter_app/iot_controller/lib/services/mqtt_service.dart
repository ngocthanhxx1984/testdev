import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

typedef MessageCallback = void Function(String topic, Map<String, dynamic> payload);

class MqttService {
  MqttServerClient? _client;
  final StreamController<MqttConnectionState> _connectionController =
      StreamController<MqttConnectionState>.broadcast();
  final Map<String, List<MessageCallback>> _subscriptions = {};

  bool _isConnecting = false;
  String _host = '';
  int _port = 443;
  String _username = '';
  String _password = '';
  String _clientId = '';

  Stream<MqttConnectionState> get connectionStream => _connectionController.stream;

  MqttConnectionState get connectionState =>
      _client?.connectionStatus?.state ?? MqttConnectionState.disconnected;

  bool get isConnected => connectionState == MqttConnectionState.connected;

  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    required String clientId,
  }) async {
    if (_isConnecting) return false;
    _isConnecting = true;

    _host = host;
    _port = port;
    _username = username;
    _password = password;
    _clientId = clientId;

    try {
      _client?.disconnect();

      _client = MqttServerClient.withPort(_host, _clientId, _port);

      // Plain MQTT (no TLS) for OpenWrt Mosquitto broker
      _client!.secure = false;

      // Connection settings
      _client!.keepAlivePeriod = 30;
      _client!.connectTimeoutPeriod = 10000; // 10 seconds
      _client!.logging(on: true);

      // Callbacks
      _client!.onConnected = _onConnected;
      _client!.onDisconnected = _onDisconnected;
      _client!.onSubscribed = _onSubscribed;

      // Build connection message with authentication
      final connMsg = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .authenticateAs(_username, _password)
          .startClean()
          .withProtocolName('MQTT')
          .withProtocolVersion(4);

      _client!.connectionMessage = connMsg;

      print('[MQTT] Connecting to $host:$port as $clientId...');
      final connResult = await _client!.connect(_username, _password);
      print('[MQTT] Connection result: ${connResult?.state}');

      if (_client!.connectionStatus?.state == MqttConnectionState.connected) {
        // Enable auto-reconnect AFTER successful first connection
        _client!.autoReconnect = true;
        _client!.resubscribeOnAutoReconnect = true;
        _client!.onAutoReconnect = _onAutoReconnect;
        _client!.onAutoReconnected = _onAutoReconnected;

        _client!.updates?.listen(_onMessage);
        _isConnecting = false;
        return true;
      } else {
        print('[MQTT] Connection failed: ${_client!.connectionStatus}');
      }
    } catch (e, stackTrace) {
      print('[MQTT] Connection error: $e');
      print('[MQTT] Stack trace: $stackTrace');
    }

    _isConnecting = false;
    return false;
  }

  void disconnect() {
    _client?.autoReconnect = false;
    _client?.disconnect();
    _subscriptions.clear();
  }

  void subscribe(String topic, MessageCallback callback) {
    _subscriptions.putIfAbsent(topic, () => []);
    _subscriptions[topic]!.add(callback);

    if (isConnected) {
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void unsubscribe(String topic) {
    _subscriptions.remove(topic);
    if (isConnected) {
      _client?.unsubscribe(topic);
    }
  }

  void publish(String topic, Map<String, dynamic> payload, {bool retain = false}) {
    if (!isConnected) {
      print('[MQTT] Not connected, cannot publish');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    _client?.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: retain,
    );
  }

  void _onConnected() {
    print('[MQTT] Connected successfully!');
    _connectionController.add(MqttConnectionState.connected);

    // Re-subscribe to all topics
    for (final topic in _subscriptions.keys) {
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void _onDisconnected() {
    print('[MQTT] Disconnected');
    _connectionController.add(MqttConnectionState.disconnected);
  }

  void _onAutoReconnect() {
    print('[MQTT] Auto-reconnecting...');
  }

  void _onAutoReconnected() {
    print('[MQTT] Auto-reconnected');
    _connectionController.add(MqttConnectionState.connected);
  }

  void _onSubscribed(String topic) {
    print('[MQTT] Subscribed to: $topic');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final pubMsg = msg.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(pubMsg.payload.message);

      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;

        // Match subscriptions (support wildcards)
        for (final entry in _subscriptions.entries) {
          if (_topicMatches(entry.key, topic)) {
            for (final cb in entry.value) {
              cb(topic, json);
            }
          }
        }
      } catch (e) {
        print('[MQTT] Failed to parse message on $topic: $e');
      }
    }
  }

  bool _topicMatches(String pattern, String topic) {
    if (pattern == topic) return true;
    if (pattern.contains('+') || pattern.contains('#')) {
      final patParts = pattern.split('/');
      final topParts = topic.split('/');

      for (int i = 0; i < patParts.length; i++) {
        if (patParts[i] == '#') return true;
        if (i >= topParts.length) return false;
        if (patParts[i] != '+' && patParts[i] != topParts[i]) return false;
      }
      return patParts.length == topParts.length;
    }
    return false;
  }

  void dispose() {
    disconnect();
    _connectionController.close();
  }
}
