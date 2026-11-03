class LearningNote {
  const LearningNote({
    required this.id,
    required this.userId,
    required this.bookId,
    required this.noteType,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.bookTitle,
    this.bookAuthor,
    this.bookThumbnail,
    this.isPendingSync = false,
    this.isSyncFailed = false,
    this.syncError,
    this.clientId,
    this.reviewStage,
    this.nextReviewAt,
    this.isReviewDue,
  });

  final String id;
  final String userId;
  final String bookId;
  final String noteType; // 'personal_note', 'key_takeaway', 'question'
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? bookTitle;
  final String? bookAuthor;
  final String? bookThumbnail;

  // Offline-first sync & smart review metadata
  final bool isPendingSync;
  final bool isSyncFailed;
  final String? syncError;
  final String? clientId;
  final int? reviewStage;
  final DateTime? nextReviewAt;
  final bool? isReviewDue;

  factory LearningNote.fromJson(Map<String, dynamic> json) {
    final rawBook = json['book'] is Map<String, dynamic>
        ? json['book'] as Map<String, dynamic>
        : null;

    DateTime parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        try {
          return DateTime.parse(d);
        } catch (_) {}
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        try {
          return DateTime.parse(d);
        } catch (_) {}
      }
      return null;
    }

    return LearningNote(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      bookId: json['book_id']?.toString() ?? json['bookId']?.toString() ?? '',
      noteType: json['note_type']?.toString() ??
          json['noteType']?.toString() ??
          'personal_note',
      content: json['content']?.toString() ?? '',
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
      bookTitle: rawBook?['title']?.toString() ?? json['bookTitle']?.toString(),
      bookAuthor: rawBook?['authors']?.toString() ?? json['bookAuthor']?.toString(),
      bookThumbnail: rawBook?['thumbnail']?.toString() ?? json['bookThumbnail']?.toString(),
      isPendingSync: json['isPendingSync'] == true || json['is_pending_sync'] == true,
      isSyncFailed: json['isSyncFailed'] == true || json['is_sync_failed'] == true,
      syncError: json['syncError']?.toString() ?? json['sync_error']?.toString(),
      clientId: json['clientId']?.toString() ?? json['client_id']?.toString(),
      reviewStage: json['reviewStage'] is int ? json['reviewStage'] as int : (json['review_stage'] is int ? json['review_stage'] as int : null),
      nextReviewAt: parseNullableDate(json['nextReviewAt'] ?? json['next_review_at']),
      isReviewDue: json['isReviewDue'] == true || json['is_review_due'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'book_id': bookId,
      'note_type': noteType,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (bookTitle != null || bookAuthor != null || bookThumbnail != null)
        'book': {
          if (bookTitle != null) 'title': bookTitle,
          if (bookAuthor != null) 'authors': bookAuthor,
          if (bookThumbnail != null) 'thumbnail': bookThumbnail,
        },
      if (isPendingSync) 'isPendingSync': isPendingSync,
      if (isSyncFailed) 'isSyncFailed': isSyncFailed,
      if (syncError != null) 'syncError': syncError,
      if (clientId != null) 'clientId': clientId,
      if (reviewStage != null) 'reviewStage': reviewStage,
      if (nextReviewAt != null) 'nextReviewAt': nextReviewAt!.toIso8601String(),
      if (isReviewDue != null) 'isReviewDue': isReviewDue,
    };
  }

  LearningNote copyWith({
    String? id,
    String? userId,
    String? bookId,
    String? noteType,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? bookTitle,
    String? bookAuthor,
    String? bookThumbnail,
    bool? isPendingSync,
    bool? isSyncFailed,
    String? syncError,
    String? clientId,
    int? reviewStage,
    DateTime? nextReviewAt,
    bool? isReviewDue,
  }) {
    return LearningNote(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      bookId: bookId ?? this.bookId,
      noteType: noteType ?? this.noteType,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookThumbnail: bookThumbnail ?? this.bookThumbnail,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      isSyncFailed: isSyncFailed ?? this.isSyncFailed,
      syncError: syncError ?? this.syncError,
      clientId: clientId ?? this.clientId,
      reviewStage: reviewStage ?? this.reviewStage,
      nextReviewAt: nextReviewAt ?? this.nextReviewAt,
      isReviewDue: isReviewDue ?? this.isReviewDue,
    );
  }
}
