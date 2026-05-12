import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/mqtt_provider.dart';
import 'providers/device_provider.dart';
import 'providers/automation_provider.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/smart_screen.dart';
import 'screens/automation_screen.dart';
import 'screens/ota_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().loadSettings();
  runApp(const IoTControllerApp());
}

class IoTControllerApp extends StatelessWidget {
  const IoTControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => MqttProvider()..loadSettings()),
        ChangeNotifierProxyProvider<MqttProvider, DeviceProvider>(
          create: (ctx) =>
              DeviceProvider(ctx.read<MqttProvider>().service),
          update: (ctx, mqtt, prev) => prev ?? DeviceProvider(mqtt.service),
        ),
        ChangeNotifierProxyProvider<MqttProvider, AutomationProvider>(
          create: (ctx) =>
              AutomationProvider(ctx.read<MqttProvider>().service),
          update: (ctx, mqtt, prev) =>
              prev ?? AutomationProvider(mqtt.service),
        ),
      ],
      child: MaterialApp(
        title: 'IoT Controller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.system,
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isLoggedIn) {
              return const MainNavigation();
            }
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _listeningStarted = false;

  final _screens = const [
    HomeScreen(),
    SmartScreen(),
    AutomationScreen(),
    OtaScreen(),
    NotificationScreen(),
    SettingsScreen(),
  ];

  final _titles = const [
    'Home',
    'Entities',
    'Automation',
    'OTA Center',
    'Notifications',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartListening();
    });
  }

  void _autoStartListening() {
    final mqttProvider = context.read<MqttProvider>();
    final deviceProvider = context.read<DeviceProvider>();

    void checkAndStart() {
      if (mqttProvider.isConnected && !_listeningStarted) {
        _listeningStarted = true;
        deviceProvider.startListening();
        context.read<AutomationProvider>().syncToServer();
      } else if (!mqttProvider.isConnected) {
        _listeningStarted = false;
      }
    }

    checkAndStart();
    mqttProvider.addListener(checkAndStart);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        centerTitle: true,
        actions: [
          if (_currentIndex == 0)
            Consumer<MqttProvider>(
              builder: (context, provider, _) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  provider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: provider.isConnected ? Colors.green : Colors.grey,
                ),
              ),
            ),
          if (_currentIndex == 4)
            Consumer<DeviceProvider>(
              builder: (context, provider, _) {
                final count = provider.unreadCount;
                if (count == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Badge(
                    label: Text('$count'),
                    child: const Icon(Icons.notifications),
                  ),
                );
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: 'Entities',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Automation',
          ),
          NavigationDestination(
            icon: Icon(Icons.system_update_outlined),
            selectedIcon: Icon(Icons.system_update),
            label: 'OTA',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
