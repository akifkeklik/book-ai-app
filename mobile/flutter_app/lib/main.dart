import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'config.dart';
import 'di/service_locator.dart';
import 'services/background_sync_manager.dart';
import 'services/sync_coordinator.dart';
import 'data/repositories/notes_outbox_repository.dart';
import 'providers/auth_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/recommendation_provider.dart';
import 'providers/search_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/learning_path_provider.dart';
import 'providers/knowledge_graph_provider.dart';
import 'providers/learning_provider.dart';
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

/// Debug-only: Android emulator SSL sertifika sorununu çözer.
/// CERTIFICATE_VERIFY_FAILED hatasını önler (sadece kDebugMode'da aktif).
class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  // Android emulator debug: SSL sertifika doğrulamasını atla (only on native platforms)
  if (kDebugMode && !kIsWeb) {
    HttpOverrides.global = _DevHttpOverrides();
  }

  try {
    await ServiceLocator.initialize();
  } catch (e) {
    debugPrint('Startup Initialization Error: $e');
  }

  // Native background outbox synchronization registration
  try {
    BackgroundSyncManager.registerBackgroundSync();
  } catch (e) {
    debugPrint('Background Sync Registration Warning: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            ServiceLocator.supabaseService,
            bookRepository: ServiceLocator.bookRepository,
          ),
        ),
        Provider(create: (_) => ServiceLocator.manageUserProfileUseCase),
        Provider(create: (_) => ServiceLocator.viewBookDetailsUseCase),
        Provider(create: (_) => ServiceLocator.manageCatalogUseCase),
        Provider(create: (_) => ServiceLocator.manageRecommendationsUseCase),
        ChangeNotifierProvider(
          create: (_) => CatalogProvider(
            manageCatalog: ServiceLocator.manageCatalogUseCase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => RecommendationProvider(
            manageRecommendations: ServiceLocator.manageRecommendationsUseCase,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SearchProvider(
            searchBooksUseCase: ServiceLocator.searchBooksUseCase,
          ),
        ),
        ChangeNotifierProvider(create: (_) => FavoritesProvider(ServiceLocator.supabaseService)),
        ChangeNotifierProvider(
          create: (_) => NotesProvider(
            apiService: ServiceLocator.apiService,
            outboxRepository: NotesOutboxRepository(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => ErrorProvider()),
        ChangeNotifierProvider(create: (_) => LearningPathProvider()),
        ChangeNotifierProvider(create: (_) => KnowledgeGraphProvider()),
        ChangeNotifierProvider(create: (_) => LearningProvider()),
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

class _LibrisAppState extends State<LibrisApp> with WidgetsBindingObserver {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final userId = auth.currentUser?.id;
        if (userId != null && userId.isNotEmpty) {
          SyncCoordinator.instance.resetAuthFailures(userId);
        }
      } catch (_) {}
    }
  }

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
      theme: AppTheme.lightTheme(
        themeProvider.seedColor,
        palette: themeProvider.palette,
        highContrast: themeProvider.highContrast,
        fontFamily: themeProvider.fontFamily,
        lineSpacing: themeProvider.lineSpacing,
      ),
      darkTheme: AppTheme.darkTheme(
        themeProvider.seedColor,
        palette: themeProvider.palette,
        highContrast: themeProvider.highContrast,
        fontFamily: themeProvider.fontFamily,
        lineSpacing: themeProvider.lineSpacing,
      ),
      themeMode: themeProvider.themeMode,
      routerConfig: _router!,
      locale: langProvider.locale,
      builder: (context, child) {
        // Apply global text scale factor
        final mediaQuery = MediaQuery.of(context);
        final scale = themeProvider.textScaleFactor;

        Widget wrappedChild = MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(mediaQuery.textScaler.scale(scale)),
          ),
          child: _GlobalErrorListener(child: child!),
        );

        if (!langProvider.isInitialized) {
          return const SplashScreen();
        }
        return wrappedChild;
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
            label: context.tr('ok'),
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
