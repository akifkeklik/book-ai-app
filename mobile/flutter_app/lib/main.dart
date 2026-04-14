import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

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

// Senior Solution: Enable Mouse Drag Scrolling for Web
class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Senior Logic: Ensure startup doesn't hang forever
  try {
    // Initialise Firebase (Will fail gracefully if flutterfire configure wasn't run)
    try {
      await Firebase.initializeApp();
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    } catch (_) {}

    // Initialise Supabase
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 3));
    
    // Initialize Hive
    await Hive.initFlutter();
    await Hive.openBox('books_cache');
  } catch (e) {
    debugPrint('Startup Initialization Error: $e');
    // We continue anyway to show the UI/Error states
  }

  runApp(const LibrisApp());
}

class LibrisApp extends StatelessWidget {
  const LibrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BookProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => ErrorProvider()),
      ],
      child: Consumer4<AuthProvider, ThemeProvider, LanguageProvider, ErrorProvider>(
        builder: (context, auth, themeProvider, langProvider, errorProvider, _) {
          // Senior Logic: Only show the app if fully initialized.
          // Otherwise, the splash screen manages the loading.
          if (!langProvider.isInitialized) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.darkTheme(themeProvider.seedColor),
              home: const SplashScreen(),
            );
          }

          return MaterialApp.router(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            // Senior Solution: Applied the custom scroll behavior here
            scrollBehavior: MyCustomScrollBehavior(),
            theme: AppTheme.lightTheme(themeProvider.seedColor),
            darkTheme: AppTheme.darkTheme(themeProvider.seedColor),
            themeMode: themeProvider.themeMode,
            routerConfig: AppRouter.createRouter(auth),
            locale: langProvider.locale,
            builder: (context, child) {
              // Listen to ErrorProvider and show SnackBar if there is an error
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (errorProvider.currentError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        errorProvider.currentError!,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.red.shade800,
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: 'Kapat',
                        textColor: Colors.white,
                        onPressed: () {},
                      ),
                    ),
                  );
                  errorProvider.clearError();
                }
              });
              return child!;
            },
          );
        },
      ),
    );
  }
}
