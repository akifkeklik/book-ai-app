import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config.dart';
import '../data/repositories/book_repository_impl.dart';
import '../domain/repositories/book_repository.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';

import '../application/use_cases/manage_catalog_use_case.dart';
import '../application/use_cases/manage_recommendations_use_case.dart';
import '../application/use_cases/search_books_use_case.dart';
import '../application/use_cases/process_ai_chat_use_case.dart';

class ServiceLocator {
  static late final ApiService apiService;
  static late final SupabaseService supabaseService;
  static late final BookRepository bookRepository;
  
  static late final ManageCatalogUseCase manageCatalogUseCase;
  static late final ManageRecommendationsUseCase manageRecommendationsUseCase;
  static late final SearchBooksUseCase searchBooksUseCase;
  static late final ProcessAiChatUseCase processAiChatUseCase;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 8));
    
    await Hive.initFlutter();
    await Hive.openBox('books_cache');

    apiService = ApiService.instance;
    apiService.init();
    
    supabaseService = SupabaseService.instance;
    
    bookRepository = BookRepositoryImpl(apiService, supabaseService);
    
    manageCatalogUseCase = ManageCatalogUseCase(bookRepository);
    manageRecommendationsUseCase = ManageRecommendationsUseCase(bookRepository);
    searchBooksUseCase = SearchBooksUseCase(bookRepository);
    processAiChatUseCase = ProcessAiChatUseCase(bookRepository);
  }
}
