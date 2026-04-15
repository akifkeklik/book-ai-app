import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'providers/auth_provider.dart';
import 'providers/book_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/language_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/error_provider.dart';
import 'screens/splash_screen.dart';
import 'router.dart';
import 'theme/app_theme.dart';

// Senior Solution: Enable Mouse Drag Scrolling for Web (Refined to not steal clicks)
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    try {
      await Firebase.initializeApp();
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    } catch (_) {}

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 8));
    
    await Hive.initFlutter();
    await Hive.openBox('books_cache');
  } catch (e) {
    debugPrint('Startup Initialization Error: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BookProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => ErrorProvider()),
      ],
      child: const LibrisApp(),
    ),
  );
}

class LibrisApp extends StatefulWidget {
  const LibrisApp({super.key});

  @override
  State<LibrisApp> createState() => _LibrisAppState();
}

class _LibrisAppState extends State<LibrisApp> {
  GoRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_router == null) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      _router = AppRouter.createRouter(auth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final langProvider = context.watch<LanguageProvider>();

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      scrollBehavior: MyCustomScrollBehavior(),
      theme: AppTheme.lightTheme(themeProvider.seedColor),
      darkTheme: AppTheme.darkTheme(themeProvider.seedColor),
      themeMode: themeProvider.themeMode,
      routerConfig: _router!,
      locale: langProvider.locale,
      builder: (context, child) {
        // If language or auth is not initialized, show Splash.
        // This keeps the Navigator tree alive even during loading.
        if (!langProvider.isInitialized) {
          return const SplashScreen();
        }
        return _GlobalErrorListener(child: child!);
      },
    );
  }
}

class _GlobalErrorListener extends StatefulWidget {
  const _GlobalErrorListener({required this.child});
  final Widget child;

  @override
  State<_GlobalErrorListener> createState() => _GlobalErrorListenerState();
}

class _GlobalErrorListenerState extends State<_GlobalErrorListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ErrorProvider>().addListener(_handleError);
      }
    });
  }

  @override
  void dispose() {
    // Note: Standard practice to remove listener, 
    // though global providers usually outlive this widget.
    try {
      context.read<ErrorProvider>().removeListener(_handleError);
    } catch (_) {}
    super.dispose();
  }

  void _handleError() {
    if (!mounted) return;
    final errorProvider = context.read<ErrorProvider>();
    if (errorProvider.currentError != null) {
      final message = errorProvider.currentError!;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'TAMAM',
            textColor: Colors.white,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
      
      errorProvider.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
