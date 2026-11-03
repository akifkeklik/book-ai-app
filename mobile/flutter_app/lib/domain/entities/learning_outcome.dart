class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.userId,
    required this.title,
    required this.concept,
    required this.question,
    required this.answer,
    this.explanation = '',
    this.sourceType = 'custom_question',
    this.sourceId,
    this.bookId,
    this.pathId,
    this.stage = 1,
    this.intervalDays = 1,
    this.nextReviewAt,
    this.lastReviewedAt,
    this.totalReviews = 0,
    this.successfulReviews = 0,
    this.status = 'active',
    this.priority = 0.0,
    this.recommendationReason = '',
    this.recommendationReasonKey = 'reinforcement_due',
    this.bookTitle,
    this.bookAuthor,
    this.bookThumbnail,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String concept;
  final String question;
  final String answer;
  final String explanation;
  final String sourceType;
  final String? sourceId;
  final String? bookId;
  final String? pathId;
  final int stage;
  final int intervalDays;
  final DateTime? nextReviewAt;
  final DateTime? lastReviewedAt;
  final int totalReviews;
  final int successfulReviews;
  final String status;
  final double priority;
  final String recommendationReason;
  final String recommendationReasonKey;
  final String? bookTitle;
  final String? bookAuthor;
  final String? bookThumbnail;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDue {
    if (nextReviewAt == null) return true;
    return nextReviewAt!.isBefore(DateTime.now()) || nextReviewAt!.isAtSameMomentAs(DateTime.now());
  }

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
      return null;
    }

    return ReviewItem(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      concept: json['concept']?.toString() ?? '',
      question: json['question']?.toString() ?? '',
      answer: json['answer']?.toString() ?? '',
      explanation: json['explanation']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? json['sourceType']?.toString() ?? 'custom_question',
      sourceId: json['source_id']?.toString() ?? json['sourceId']?.toString(),
      bookId: json['book_id']?.toString() ?? json['bookId']?.toString(),
      pathId: json['path_id']?.toString() ?? json['pathId']?.toString(),
      stage: (json['stage'] as num?)?.toInt() ?? 1,
      intervalDays: (json['interval_days'] as num? ?? json['intervalDays'] as num?)?.toInt() ?? 1,
      nextReviewAt: parseDate(json['next_review_at'] ?? json['nextReviewAt']),
      lastReviewedAt: parseDate(json['last_reviewed_at'] ?? json['lastReviewedAt']),
      totalReviews: (json['total_reviews'] as num? ?? json['totalReviews'] as num?)?.toInt() ?? 0,
      successfulReviews: (json['successful_reviews'] as num? ?? json['successfulReviews'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'active',
      priority: (json['priority'] as num?)?.toDouble() ?? 0.0,
      recommendationReason: json['recommendation_reason']?.toString() ?? json['recommendationReason']?.toString() ?? '',
      recommendationReasonKey: json['recommendation_reason_key']?.toString() ?? json['recommendationReasonKey']?.toString() ?? 'reinforcement_due',
      bookTitle: json['book_title']?.toString() ?? json['bookTitle']?.toString(),
      bookAuthor: json['book_author']?.toString() ?? json['bookAuthor']?.toString(),
      bookThumbnail: json['book_thumbnail']?.toString() ?? json['bookThumbnail']?.toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'concept': concept,
      'question': question,
      'answer': answer,
      'explanation': explanation,
      'source_type': sourceType,
      'source_id': sourceId,
      'book_id': bookId,
      'path_id': pathId,
      'stage': stage,
      'interval_days': intervalDays,
      'next_review_at': nextReviewAt?.toIso8601String(),
      'last_reviewed_at': lastReviewedAt?.toIso8601String(),
      'total_reviews': totalReviews,
      'successful_reviews': successfulReviews,
      'status': status,
      'priority': priority,
      'recommendation_reason': recommendationReason,
      'recommendation_reason_key': recommendationReasonKey,
      'book_title': bookTitle,
      'book_author': bookAuthor,
      'book_thumbnail': bookThumbnail,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ReviewItem copyWith({
    String? id,
    String? userId,
    String? title,
    String? concept,
    String? question,
    String? answer,
    String? explanation,
    String? sourceType,
    String? sourceId,
    String? bookId,
    String? pathId,
    int? stage,
    int? intervalDays,
    DateTime? nextReviewAt,
    DateTime? lastReviewedAt,
    int? totalReviews,
    int? successfulReviews,
    String? status,
    double? priority,
    String? recommendationReason,
    String? recommendationReasonKey,
    String? bookTitle,
    String? bookAuthor,
    String? bookThumbnail,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReviewItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      concept: concept ?? this.concept,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      explanation: explanation ?? this.explanation,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      bookId: bookId ?? this.bookId,
      pathId: pathId ?? this.pathId,
      stage: stage ?? this.stage,
      intervalDays: intervalDays ?? this.intervalDays,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      totalReviews: totalReviews ?? this.totalReviews,
      successfulReviews: successfulReviews ?? this.successfulReviews,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      recommendationReason: recommendationReason ?? this.recommendationReason,
      recommendationReasonKey: recommendationReasonKey ?? this.recommendationReasonKey,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookThumbnail: bookThumbnail ?? this.bookThumbnail,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ReviewAttempt {
  const ReviewAttempt({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.outcome,
    this.responseText = '',
    this.isCorrect = true,
    this.stageBefore = 1,
    this.stageAfter = 1,
    this.reviewedAt,
    this.itemTitle,
    this.concept,
  });

  final String id;
  final String userId;
  final String itemId;
  final String outcome; // 'remembered' | 'struggled'
  final String responseText;
  final bool isCorrect;
  final int stageBefore;
  final int stageAfter;
  final DateTime? reviewedAt;
  final String? itemTitle;
  final String? concept;

  factory ReviewAttempt.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v is String && v.isNotEmpty) {
        try {
          return DateTime.parse(v);
        } catch (_) {}
      }
      return null;
    }

    return ReviewAttempt(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      itemId: json['item_id']?.toString() ?? json['itemId']?.toString() ?? '',
      outcome: json['outcome']?.toString() ?? 'remembered',
      responseText: json['response_text']?.toString() ?? json['responseText']?.toString() ?? '',
      isCorrect: json['is_correct'] is bool ? json['is_correct'] as bool : (json['isCorrect'] is bool ? json['isCorrect'] as bool : true),
      stageBefore: (json['stage_before'] as num? ?? json['stageBefore'] as num?)?.toInt() ?? 1,
      stageAfter: (json['stage_after'] as num? ?? json['stageAfter'] as num?)?.toInt() ?? 1,
      reviewedAt: parseDate(json['reviewed_at'] ?? json['reviewedAt']),
      itemTitle: json['item_title']?.toString() ?? json['itemTitle']?.toString(),
      concept: json['concept']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'outcome': outcome,
      'response_text': responseText,
      'is_correct': isCorrect,
      'stage_before': stageBefore,
      'stage_after': stageAfter,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'item_title': itemTitle,
      'concept': concept,
    };
  }
}

class DifficultConcept {
  const DifficultConcept({
    required this.concept,
    this.totalItems = 0,
    this.totalAttempts = 0,
    this.successfulRecalls = 0,
    this.struggledRecalls = 0,
    this.retentionRate = 0.0,
    this.averageStage = 1.0,
    this.dueItems = 0,
    this.needsReview = false,
  });

  final String concept;
  final int totalItems;
  final int totalAttempts;
  final int successfulRecalls;
  final int struggledRecalls;
  final double retentionRate;
  final double averageStage;
  final int dueItems;
  final bool needsReview;

  factory DifficultConcept.fromJson(Map<String, dynamic> json) {
    return DifficultConcept(
      concept: json['concept']?.toString() ?? '',
      totalItems: (json['total_items'] as num? ?? json['totalItems'] as num?)?.toInt() ?? 0,
      totalAttempts: (json['total_attempts'] as num? ?? json['totalAttempts'] as num?)?.toInt() ?? 0,
      successfulRecalls: (json['successful_recalls'] as num? ?? json['successfulRecalls'] as num?)?.toInt() ?? 0,
      struggledRecalls: (json['struggled_recalls'] as num? ?? json['struggledRecalls'] as num?)?.toInt() ?? 0,
      retentionRate: (json['retention_rate'] as num? ?? json['retentionRate'] as num?)?.toDouble() ?? 0.0,
      averageStage: (json['average_stage'] as num? ?? json['averageStage'] as num?)?.toDouble() ?? 1.0,
      dueItems: (json['due_items'] as num? ?? json['dueItems'] as num?)?.toInt() ?? 0,
      needsReview: json['needs_review'] is bool ? json['needs_review'] as bool : (json['needsReview'] is bool ? json['needsReview'] as bool : false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'concept': concept,
      'total_items': totalItems,
      'total_attempts': totalAttempts,
      'successful_recalls': successfulRecalls,
      'struggled_recalls': struggledRecalls,
      'retention_rate': retentionRate,
      'average_stage': averageStage,
      'due_items': dueItems,
      'needs_review': needsReview,
    };
  }
}

class LearningProgress {
  const LearningProgress({
    this.masteryScore = 0.0,
    this.masteryLevel = 'insufficient_data',
    this.totalItems = 0,
    this.reviewsDue = 0,
    this.reviewsCompleted = 0,
    this.successfulRecalls = 0,
    this.struggledRecalls = 0,
    this.retentionRate = 0.0,
    this.conceptsCount = 0,
    this.difficultConcepts = const [],
    this.recentActivity = const [],
    this.activeStreakDays = 0,
    this.algorithmVersion = '1.0.0-deterministic',
  });

  final double masteryScore;
  final String masteryLevel;
  final int totalItems;
  final int reviewsDue;
  final int reviewsCompleted;
  final int successfulRecalls;
  final int struggledRecalls;
  final double retentionRate;
  final int conceptsCount;
  final List<DifficultConcept> difficultConcepts;
  final List<ReviewAttempt> recentActivity;
  final int activeStreakDays;
  final String algorithmVersion;

  factory LearningProgress.fromJson(Map<String, dynamic> json) {
    var diffList = <DifficultConcept>[];
    if (json['difficult_concepts'] is List) {
      diffList = (json['difficult_concepts'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => DifficultConcept.fromJson(m))
          .toList();
    } else if (json['difficultConcepts'] is List) {
      diffList = (json['difficultConcepts'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => DifficultConcept.fromJson(m))
          .toList();
    }

    var recentList = <ReviewAttempt>[];
    if (json['recent_activity'] is List) {
      recentList = (json['recent_activity'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => ReviewAttempt.fromJson(m))
          .toList();
    } else if (json['recentActivity'] is List) {
      recentList = (json['recentActivity'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => ReviewAttempt.fromJson(m))
          .toList();
    }

    return LearningProgress(
      masteryScore: (json['mastery_score'] as num? ?? json['masteryScore'] as num?)?.toDouble() ?? 0.0,
      masteryLevel: json['mastery_level']?.toString() ?? json['masteryLevel']?.toString() ?? 'insufficient_data',
      totalItems: (json['total_items'] as num? ?? json['totalItems'] as num?)?.toInt() ?? 0,
      reviewsDue: (json['reviews_due'] as num? ?? json['reviewsDue'] as num?)?.toInt() ?? 0,
      reviewsCompleted: (json['reviews_completed'] as num? ?? json['reviewsCompleted'] as num?)?.toInt() ?? 0,
      successfulRecalls: (json['successful_recalls'] as num? ?? json['successfulRecalls'] as num?)?.toInt() ?? 0,
      struggledRecalls: (json['struggled_recalls'] as num? ?? json['struggledRecalls'] as num?)?.toInt() ?? 0,
      retentionRate: (json['retention_rate'] as num? ?? json['retentionRate'] as num?)?.toDouble() ?? 0.0,
      conceptsCount: (json['concepts_count'] as num? ?? json['conceptsCount'] as num?)?.toInt() ?? 0,
      difficultConcepts: diffList,
      recentActivity: recentList,
      activeStreakDays: (json['active_streak_days'] as num? ?? json['activeStreakDays'] as num?)?.toInt() ?? 0,
      algorithmVersion: json['algorithm_version']?.toString() ?? json['algorithmVersion']?.toString() ?? '1.0.0-deterministic',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mastery_score': masteryScore,
      'mastery_level': masteryLevel,
      'total_items': totalItems,
      'reviews_due': reviewsDue,
      'reviews_completed': reviewsCompleted,
      'successful_recalls': successfulRecalls,
      'struggled_recalls': struggledRecalls,
      'retention_rate': retentionRate,
      'concepts_count': conceptsCount,
      'difficult_concepts': difficultConcepts.map((d) => d.toJson()).toList(),
      'recent_activity': recentActivity.map((r) => r.toJson()).toList(),
      'active_streak_days': activeStreakDays,
      'algorithm_version': algorithmVersion,
    };
  }
}

