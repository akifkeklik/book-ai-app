import '../../domain/repositories/book_repository.dart';

class ManageUserProfileUseCase {
  final BookRepository _repository;

  ManageUserProfileUseCase(this._repository);

  Future<void> upsertUserProfile({
    required String userId,
    required List<String> preferredGenres,
    required int readingFrequency,
    required List<String> preferredAuthors,
    required String preferredVibe,
  }) {
    return _repository.upsertUserProfile(
      userId: userId,
      preferredGenres: preferredGenres,
      readingFrequency: readingFrequency,
      preferredAuthors: preferredAuthors,
      preferredVibe: preferredVibe,
    );
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) {
    return _repository.getUserProfile(userId);
  }
}
