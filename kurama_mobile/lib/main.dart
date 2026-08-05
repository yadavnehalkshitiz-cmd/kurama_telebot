import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'services/download_storage.dart';
import 'services/background_download_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/browser_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/vault_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/player_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.kuramabot.audio',
    androidNotificationChannelName: 'Kurama audio playback',
    androidNotificationOngoing: true,
  );
  await NotificationService.initialize(
    onOpen: (path) => _openDownloadedMedia(path),
  );
  await NotificationService.requestPermission();
  await BackgroundDownloadService.initialize();

  // Edge-to-edge dark status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0A0A0E),
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final storage = DownloadStorage(prefs);
  final userId = await storage.loadOrCreateUserId();

  // Restore saved server config or use zero-config cloud backend defaults
  final savedUrl = storage.loadServerUrl();
  final savedKey = storage.loadApiKey();

  final apiClient = ApiClient(
    baseUrl: (savedUrl != null && savedUrl.isNotEmpty)
        ? savedUrl
        : 'https://kurama-telebot.onrender.com',
    apiKey: (savedKey != null && savedKey.isNotEmpty)
        ? savedKey
        : 'changeme-in-production',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(storage, apiClient, userId: userId),
      child: const KuramaApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final path = NotificationService.pendingLaunchPath;
    if (path != null) _openDownloadedMedia(path);
  });
}

void _openDownloadedMedia(String path) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlayerScreen(filePath: path, title: 'Downloaded media'),
    ),
  );
}

class KuramaApp extends StatelessWidget {
  const KuramaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'KuramaBot',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      darkTheme: _buildTheme(),
      themeMode: ThemeMode.dark,
      home: const AppShell(),
    );
  }

  ThemeData _buildTheme() {
    // Ultra-premium Obsidian Glass brand palette
    const primarySeed = Color(0xFFFF5722); // Vibrant Fox Amber
    const bgDark = Color(0xFF0A0A0E); // Deepest Obsidian
    const surfaceDark = Color(0xFF14141E); // Glass Surface
    const cardDark = Color(0xFF1C1C28); // Elevated Glass Card

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: primarySeed,
      scaffoldBackgroundColor: bgDark,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Color(0xFF0D0D12),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primarySeed, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primarySeed,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: primarySeed.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceDark,
        selectedColor: primarySeed.withValues(alpha: 0.3),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════
//  Glass Bottom Navigation Shell
// ═════════════════════════════════════════════════════════

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    BrowserScreen(),
    DownloadsScreen(),
    VaultScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D12),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: primary.withValues(alpha: 0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 68,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.language_outlined),
              selectedIcon: Icon(Icons.language_rounded),
              label: 'Browse',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download_rounded),
              label: 'Downloads',
            ),
            NavigationDestination(
              icon: Icon(Icons.lock_outline_rounded),
              selectedIcon: Icon(Icons.lock_rounded),
              label: 'Vault',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
