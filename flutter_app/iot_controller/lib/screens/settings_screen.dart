import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mqtt_provider.dart';
import '../providers/device_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _obscurePassword = true;
  bool _fieldsPopulated = false;

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = ApiService().baseUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryPopulateFields();
      context.read<MqttProvider>().addListener(_tryPopulateFields);
    });
  }

  void _tryPopulateFields() {
    final provider = context.read<MqttProvider>();
    if (!_fieldsPopulated && provider.host.isNotEmpty) {
      _hostController.text = provider.host;
      _portController.text = provider.port.toString();
      _usernameController.text = provider.username;
      _passwordController.text = provider.password;
      _clientIdController.text = provider.clientId;
      _fieldsPopulated = true;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _clientIdController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MqttProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account section
                _buildAccountSection(),
                const SizedBox(height: 24),

                // Connection Status Card
                _buildStatusCard(provider),
                const SizedBox(height: 24),

                // Server URL
                const Text(
                  'API Server',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serverUrlController,
                  decoration: InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://192.168.0.121',
                    prefixIcon: const Icon(Icons.dns),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    helperText: 'Node.js backend URL (e.g., https://192.168.0.121)',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final url = _serverUrlController.text.trim();
                      if (url.isNotEmpty) {
                        await ApiService().saveBaseUrl(url);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Server URL saved'), backgroundColor: Colors.green),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Save Server URL'),
                  ),
                ),
                const SizedBox(height: 24),

                // MQTT Settings
                const Text(
                  'MQTT Broker Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _hostController,
                  decoration: InputDecoration(
                    labelText: 'MQTT Host',
                    hintText: '192.168.0.121',
                    prefixIcon: const Icon(Icons.dns),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: 'Port',
                    hintText: '1883',
                    prefixIcon: const Icon(Icons.numbers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (int.tryParse(v) == null) return 'Invalid port';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'MQTT Username',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'MQTT Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _clientIdController,
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    hintText: 'flutter_iot_app',
                    prefixIcon: const Icon(Icons.badge),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _saveSettings(provider),
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: provider.isConnecting
                            ? null
                            : () => _connectOrDisconnect(provider),
                        icon: provider.isConnecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(provider.isConnected ? Icons.link_off : Icons.link),
                        label: Text(provider.isConnecting
                            ? 'Connecting...'
                            : provider.isConnected
                                ? 'Disconnect'
                                : 'Connect'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          backgroundColor: provider.isConnected ? Colors.red : null,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                // Logout
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      final mqtt = context.read<MqttProvider>();
                      mqtt.disconnect();
                      await auth.logout();
                    },
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('Logout', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountSection() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(
                  (auth.username ?? '?')[0].toUpperCase(),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.displayName ?? auth.username ?? 'User',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '@${auth.username ?? ''}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(MqttProvider provider) {
    final isConnected = provider.isConnected;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? [Colors.green[400]!, Colors.green[600]!]
              : [Colors.grey[400]!, Colors.grey[600]!],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.cloud_done : Icons.cloud_off,
            size: 40,
            color: Colors.white,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? 'MQTT Connected' : 'MQTT Disconnected',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (isConnected)
                  Text(
                    'Broker: ${provider.host}',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSettings(MqttProvider provider) async {
    if (!_formKey.currentState!.validate()) return;

    await provider.saveSettings(
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      clientId: _clientIdController.text.trim().isNotEmpty
          ? _clientIdController.text.trim()
          : 'flutter_iot_app',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _connectOrDisconnect(MqttProvider provider) async {
    if (provider.isConnected) {
      provider.disconnect();
      context.read<DeviceProvider>().stopListening();
      return;
    }

    await _saveSettings(provider);

    final success = await provider.connect();
    if (success && mounted) {
      context.read<DeviceProvider>().startListening();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected to MQTT Broker'), backgroundColor: Colors.green),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect. Check your settings.'), backgroundColor: Colors.red),
      );
    }
  }
}
