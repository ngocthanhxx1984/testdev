import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _isRegister = false;
  bool _obscure = true;
  bool _showServerField = false;

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = ApiService().baseUrl;
    if (_serverCtrl.text.isEmpty) _showServerField = true;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Save server URL if provided
    final serverUrl = _serverCtrl.text.trim();
    if (serverUrl.isNotEmpty) {
      await ApiService().saveBaseUrl(serverUrl);
    }

    if (!ApiService().isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please configure server URL first')),
      );
      setState(() => _showServerField = true);
      return;
    }

    final auth = context.read<AuthProvider>();
    bool success;

    if (_isRegister) {
      success = await auth.register(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
        email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
      );
    } else {
      success = await auth.login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
    }

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home_rounded, size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('IoT Controller', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    _isRegister ? 'Create Account' : 'Sign In',
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),

                  // Server URL
                  if (_showServerField) ...[
                    TextFormField(
                      controller: _serverCtrl,
                      decoration: InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'https://192.168.0.121',
                        prefixIcon: const Icon(Icons.dns),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (!v.startsWith('http')) return 'Must start with http:// or https://';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Username
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || v.trim().length < 3 ? 'Min 3 characters' : null,
                  ),
                  const SizedBox(height: 16),

                  // Email (register only)
                  if (_isRegister) ...[
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: InputDecoration(
                        labelText: 'Email (optional)',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Password
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || v.length < 6 ? 'Min 6 characters' : null,
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: auth.isLoading ? null : _submit,
                          child: auth.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_isRegister ? 'Register' : 'Login'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Toggle login/register
                  TextButton(
                    onPressed: () => setState(() => _isRegister = !_isRegister),
                    child: Text(_isRegister
                        ? 'Already have an account? Sign In'
                        : "Don't have an account? Register"),
                  ),

                  // Server URL toggle
                  if (!_showServerField)
                    TextButton(
                      onPressed: () => setState(() => _showServerField = true),
                      child: const Text('Change Server'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
