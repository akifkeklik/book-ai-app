import '../../domain/repositories/book_repository.dart';

class ProcessAiChatUseCase {
  final BookRepository _repository;

  ProcessAiChatUseCase(this._repository);

  Future<Map<String, dynamic>> execute(String query) {
    return _repository.chatWithAI(query);
  }
}
