import 'package:flutter_test/flutter_test.dart';

import 'package:book_ai_app/domain/entities/learning_outcome.dart';
import 'package:book_ai_app/providers/learning_provider.dart';
import 'package:book_ai_app/services/api_service.dart';

class FakeLearningApiService implements ApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  LearningProgress? mockProgress;
  List<ReviewItem> mockQueue = [];
  List<ReviewAttempt> mockHistory = [];
  List<DifficultConcept> mockConcepts = [];
  bool shouldFail = false;
  int submitAttemptCalls = 0;
  int createQuestionCalls = 0;
  int deleteItemCalls = 0;

  @override
  Future<LearningProgress?> getLearningOverview() async {
    if (shouldFail) throw Exception('API Error');
    return mockProgress;
  }

  @override
  Future<List<ReviewItem>> getLearningQueue({
    String? concept,
    String? pathId,
    int limit = 20,
  }) async {
    if (shouldFail) throw Exception('API Error');
    var result = mockQueue;
    if (concept != null && concept.isNotEmpty) {
      result = result.where((it) => it.concept == concept).toList();
    }
    if (pathId != null && pathId.isNotEmpty) {
      result = result.where((it) => it.pathId == pathId).toList();
    }
    return result;
  }

  @override
  Future<ReviewItem?> getLearningItem(String itemId) async {
    if (shouldFail) throw Exception('API Error');
    return mockQueue.where((it) => it.id == itemId).firstOrNull;
  }

  @override
  Future<ReviewItem?> createLearningItem({
    required String title,
    required String concept,
    required String question,
    required String answer,
    String? explanation,
    String? bookId,
    String? pathId,
    String sourceType = 'custom_question',
    String? sourceId,
  }) async {
    if (shouldFail) throw Exception('API Error');
    createQuestionCalls++;
    final newItem = ReviewItem(
      id: 'item-$createQuestionCalls',
      userId: 'test-user',
      title: title,
      concept: concept,
      question: question,
      answer: answer,
      explanation: explanation ?? '',
      sourceType: sourceType,
      bookId: bookId,
      pathId: pathId,
      stage: 1,
      intervalDays: 1,
      nextReviewAt: DateTime.now().add(const Duration(days: 1)),
    );
    mockQueue.insert(0, newItem);
    return newItem;
  }

  @override
  Future<bool> deleteLearningItem(String itemId) async {
    if (shouldFail) throw Exception('API Error');
    deleteItemCalls++;
    mockQueue.removeWhere((it) => it.id == itemId);
    return true;
  }

  @override
  Future<Map<String, dynamic>?> submitLearningAttempt({
    required String itemId,
    required String outcome,
    String responseText = '',
  }) async {
    if (shouldFail) throw Exception('API Error');
    submitAttemptCalls++;
    final currentItem = mockQueue.where((it) => it.id == itemId).firstOrNull;
    final stageBefore = currentItem?.stage ?? 1;
    final stageAfter = outcome == 'remembered' ? stageBefore + 1 : 1;
    final nextDays = stageAfter == 2 ? 3 : (stageAfter == 1 ? 1 : 7);

    final updatedItem = currentItem?.copyWith(
      stage: stageAfter,
      intervalDays: nextDays,
      nextReviewAt: DateTime.now().add(Duration(days: nextDays)),
      totalReviews: (currentItem.totalReviews) + 1,
      successfulReviews: outcome == 'remembered'
          ? (currentItem.successfulReviews) + 1
          : currentItem.successfulReviews,
    ) ?? ReviewItem(
      id: itemId,
      userId: 'test-user',
      title: 'Item',
      concept: 'Concept',
      question: 'Q',
      answer: 'A',
      stage: stageAfter,
      intervalDays: nextDays,
      nextReviewAt: DateTime.now().add(Duration(days: nextDays)),
    );

    final attempt = ReviewAttempt(
      id: 'attempt-$submitAttemptCalls',
      userId: 'test-user',
      itemId: itemId,
      outcome: outcome,
      responseText: responseText,
      isCorrect: outcome == 'remembered',
      stageBefore: stageBefore,
      stageAfter: stageAfter,
      reviewedAt: DateTime.now(),
    );

    mockHistory.insert(0, attempt);

    return {
      'attempt': attempt,
      'item': updatedItem,
      'schedule': {
        'stage': stageAfter,
        'interval_days': nextDays,
      },
    };
  }

  @override
  Future<List<ReviewAttempt>> getLearningHistory({
    int limit = 50,
    int offset = 0,
    String? itemId,
  }) async {
    if (shouldFail) throw Exception('API Error');
    return mockHistory;
  }

  @override
  Future<List<DifficultConcept>> getLearningConcepts() async {
    if (shouldFail) throw Exception('API Error');
    return mockConcepts;
  }
}

void main() {
  group('Learning Outcomes Entity Tests', () {
    test('ReviewItem JSON serialization & deserialization with date parsing', () {
      final json = {
        'id': 'item-101',
        'user_id': 'user-alice',
        'title': 'Test Item',
        'concept': 'Cognitive Biases',
        'question': 'What is Confirmation Bias?',
        'answer': 'Tendency to search for information confirming preconceptions.',
        'explanation': 'Thinking, Fast and Slow chapter 7',
        'source_type': 'key_takeaway',
        'stage': 2,
        'interval_days': 3,
        'next_review_at': '2026-10-30T10:00:00Z',
        'total_reviews': 3,
        'successful_reviews': 2,
        'status': 'active',
        'priority': 75.5,
        'recommendation_reason': 'Scheduled for upcoming review',
        'recommendation_reason_key': 'reinforcement_due',
        'book_title': 'Thinking, Fast and Slow',
      };

      final item = ReviewItem.fromJson(json);
      expect(item.id, equals('item-101'));
      expect(item.userId, equals('user-alice'));
      expect(item.concept, equals('Cognitive Biases'));
      expect(item.stage, equals(2));
      expect(item.intervalDays, equals(3));
      expect(item.nextReviewAt, isNotNull);
      expect(item.priority, equals(75.5));
      expect(item.recommendationReasonKey, equals('reinforcement_due'));
      expect(item.bookTitle, equals('Thinking, Fast and Slow'));

      final serialized = item.toJson();
      expect(serialized['id'], equals('item-101'));
      expect(serialized['concept'], equals('Cognitive Biases'));
      expect(serialized['stage'], equals(2));
    });

    test('ReviewAttempt JSON serialization & deserialization', () {
      final json = {
        'id': 'attempt-202',
        'user_id': 'user-alice',
        'item_id': 'item-101',
        'outcome': 'remembered',
        'response_text': 'Favoring confirming evidence',
        'is_correct': true,
        'stage_before': 1,
        'stage_after': 2,
        'reviewed_at': '2026-10-28T09:00:00Z',
        'item_title': 'Confirmation Bias',
        'concept': 'Cognitive Biases',
      };

      final attempt = ReviewAttempt.fromJson(json);
      expect(attempt.id, equals('attempt-202'));
      expect(attempt.outcome, equals('remembered'));
      expect(attempt.isCorrect, isTrue);
      expect(attempt.stageBefore, equals(1));
      expect(attempt.stageAfter, equals(2));
      expect(attempt.concept, equals('Cognitive Biases'));

      final serialized = attempt.toJson();
      expect(serialized['outcome'], equals('remembered'));
      expect(serialized['stage_after'], equals(2));
    });

    test('LearningProgress JSON serialization with nested difficult concepts and activity', () {
      final json = {
        'mastery_score': 82.5,
        'mastery_level': 'proficient',
        'total_items': 15,
        'reviews_due': 3,
        'reviews_completed': 12,
        'successful_recalls': 10,
        'struggled_recalls': 2,
        'retention_rate': 83.3,
        'concepts_count': 5,
        'active_streak_days': 4,
        'algorithm_version': '1.0.0-deterministic',
        'difficult_concepts': [
          {
            'concept': 'Bayesian Inference',
            'total_items': 2,
            'total_attempts': 4,
            'successful_recalls': 1,
            'struggled_recalls': 3,
            'retention_rate': 25.0,
            'average_stage': 1.0,
            'due_items': 2,
            'needs_review': true,
          }
        ],
        'recent_activity': [
          {
            'id': 'att-1',
            'user_id': 'alice',
            'item_id': 'item-1',
            'outcome': 'remembered',
            'is_correct': true,
            'stage_before': 2,
            'stage_after': 3,
          }
        ],
      };

      final progress = LearningProgress.fromJson(json);
      expect(progress.masteryScore, equals(82.5));
      expect(progress.masteryLevel, equals('proficient'));
      expect(progress.reviewsDue, equals(3));
      expect(progress.activeStreakDays, equals(4));
      expect(progress.difficultConcepts.length, equals(1));
      expect(progress.difficultConcepts.first.concept, equals('Bayesian Inference'));
      expect(progress.difficultConcepts.first.needsReview, isTrue);
      expect(progress.recentActivity.length, equals(1));
    });
  });

  group('LearningProvider State Management Tests', () {
    late FakeLearningApiService fakeApi;
    late LearningProvider provider;

    setUp(() {
      fakeApi = FakeLearningApiService();
      fakeApi.mockProgress = const LearningProgress(
        masteryScore: 78.0,
        masteryLevel: 'practicing',
        totalItems: 8,
        reviewsDue: 2,
        reviewsCompleted: 6,
        successfulRecalls: 5,
        struggledRecalls: 1,
        retentionRate: 83.3,
        activeStreakDays: 3,
      );
      fakeApi.mockQueue = [
        ReviewItem(
          id: 'item-1',
          userId: 'user-alice',
          title: 'Heuristics',
          concept: 'Psychology',
          question: 'What is an availability heuristic?',
          answer: 'Judging probability by ease of examples coming to mind.',
          stage: 1,
          intervalDays: 1,
          nextReviewAt: DateTime.now().subtract(const Duration(hours: 2)),
          recommendationReasonKey: 'review_overdue',
        ),
        ReviewItem(
          id: 'item-2',
          userId: 'user-alice',
          title: 'Mental Models',
          concept: 'Thinking',
          question: 'What is Occam Razor?',
          answer: 'Simpler explanations are generally better than complex ones.',
          stage: 2,
          intervalDays: 3,
          nextReviewAt: DateTime.now().subtract(const Duration(hours: 1)),
          recommendationReasonKey: 'reinforcement_due',
        ),
      ];
      provider = LearningProvider(apiService: fakeApi);
    });

    test('Initial empty state before login', () {
      expect(provider.progress, isNull);
      expect(provider.queue, isEmpty);
      expect(provider.activeItem, isNull);
      expect(provider.masteryScore, equals(0.0));
      expect(provider.masteryLevel, equals('insufficient_data'));
    });

    test('updateUser loads isolated data and sets active item', () async {
      provider.updateUser('user-alice');
      await Future.delayed(Duration.zero);

      expect(provider.currentUserId, equals('user-alice'));
      expect(provider.queue.length, equals(2));
      expect(provider.activeItem?.id, equals('item-1'));
      expect(provider.masteryScore, equals(78.0));
      expect(provider.reviewsDue, equals(2));
    });

    test('Concept filtering filters queue items', () async {
      provider.updateUser('user-alice');
      await Future.delayed(Duration.zero);

      provider.filterByConcept('Psychology');
      await Future.delayed(Duration.zero);

      expect(provider.selectedConceptFilter, equals('Psychology'));
      expect(provider.queue.length, equals(1));
      expect(provider.queue.first.concept, equals('Psychology'));
    });

    test('Path filtering filters queue items by pathId', () async {
      fakeApi.mockQueue = [
        const ReviewItem(
          id: 'item-path-1',
          userId: 'user-alice',
          title: 'Path Question',
          concept: 'Systems',
          question: 'Q',
          answer: 'A',
          pathId: 'path-systems-101',
          stage: 1,
          intervalDays: 1,
        ),
        const ReviewItem(
          id: 'item-other',
          userId: 'user-alice',
          title: 'Other Question',
          concept: 'Art',
          question: 'Q2',
          answer: 'A2',
          pathId: 'path-art-202',
          stage: 1,
          intervalDays: 1,
        ),
      ];

      provider.updateUser('user-alice');
      await Future.delayed(Duration.zero);

      provider.filterByPath('path-systems-101');
      await Future.delayed(Duration.zero);

      expect(provider.selectedPathFilter, equals('path-systems-101'));
      expect(provider.queue.length, equals(1));
      expect(provider.queue.first.id, equals('item-path-1'));
    });

    test('submitAttempt advances stage and removes future item from session queue', () async {
      provider.updateUser('user-alice');
      await Future.delayed(Duration.zero);

      expect(provider.queue.length, equals(2));
      final res = await provider.submitAttempt(
        itemId: 'item-1',
        outcome: 'remembered',
        responseText: 'Mental shortcut',
      );

      expect(res, isNotNull);
      expect(fakeApi.submitAttemptCalls, equals(1));
      // item-1 next review is in +3 days, so isDue is false and it leaves the active due session
      expect(provider.queue.length, equals(1));
      expect(provider.activeItem?.id, equals('item-2'));
    });

    test('createQuestion prepends new item to queue', () async {
      provider.updateUser('user-alice');
      await Future.delayed(Duration.zero);

      final created = await provider.createQuestion(
        title: 'Loss Aversion',
        concept: 'Economics',
        question: 'What is loss aversion?',
        answer: 'Pain of losing is psychologically twice as powerful as pleasure of gaining.',
      );

      expect(created, isNotNull);
      expect(fakeApi.createQuestionCalls, equals(1));
      expect(provider.queue.any((q) => q.concept == 'Economics'), isTrue);
    });

    test('Account isolation: logging out or switching user flushes memory state', () async {
      provider.updateUser('user-alice');
      await Future.delayed(Duration.zero);
      expect(provider.queue, isNotEmpty);
      expect(provider.progress, isNotNull);

      // Logout
      provider.updateUser(null);
      expect(provider.queue, isEmpty);
      expect(provider.progress, isNull);
      expect(provider.activeItem, isNull);
      expect(provider.currentUserId, isNull);

      // Switch to Bob who has empty data
      fakeApi.mockQueue = [];
      fakeApi.mockProgress = null;
      provider.updateUser('user-bob');
      await Future.delayed(Duration.zero);

      expect(provider.currentUserId, equals('user-bob'));
      expect(provider.queue, isEmpty);
      expect(provider.masteryScore, equals(0.0));
    });
  });
}

