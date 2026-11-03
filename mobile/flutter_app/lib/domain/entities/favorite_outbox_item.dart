enum OutboxAction { add, remove }

enum OutboxStatus { pending, syncing, failed, permanentFailure }

class FavoriteOutboxItem {
  final String id; // format: '${userId}_$isbn13'
  final String userId;
  final String isbn13;
  final OutboxAction action;
  final String bookTitle;
  final String bookAuthor;
  final String? bookImageUrl;
  final DateTime createdAt;
  final int retryCount;
  final OutboxStatus status;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;

  const FavoriteOutboxItem({
    required this.id,
    required this.userId,
    required this.isbn13,
    required this.action,
    required this.bookTitle,
    required this.bookAuthor,
    this.bookImageUrl,
    required this.createdAt,
    this.retryCount = 0,
    this.status = OutboxStatus.pending,
    this.lastError,
    this.lastAttemptAt,
    this.nextAttemptAt,
  });

  FavoriteOutboxItem copyWith({
    String? id,
    String? userId,
    String? isbn13,
    OutboxAction? action,
    String? bookTitle,
    String? bookAuthor,
    String? bookImageUrl,
    DateTime? createdAt,
    int? retryCount,
    OutboxStatus? status,
    String? lastError,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    bool clearLastError = false,
    bool clearNextAttemptAt = false,
  }) {
    return FavoriteOutboxItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      isbn13: isbn13 ?? this.isbn13,
      action: action ?? this.action,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookImageUrl: bookImageUrl ?? this.bookImageUrl,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextAttemptAt: clearNextAttemptAt ? null : (nextAttemptAt ?? this.nextAttemptAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'isbn13': isbn13,
        'action': action.name,
        'book_title': bookTitle,
        'book_author': bookAuthor,
        'book_image_url': bookImageUrl,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
        'status': status.name,
        'last_error': lastError,
        'last_attempt_at': lastAttemptAt?.toIso8601String(),
        'next_attempt_at': nextAttemptAt?.toIso8601String(),
      };

  factory FavoriteOutboxItem.fromJson(Map<String, dynamic> json) {
    return FavoriteOutboxItem(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      isbn13: json['isbn13']?.toString() ?? '',
      action: json['action'] == 'remove'
          ? OutboxAction.remove
          : OutboxAction.add,
      bookTitle: json['book_title']?.toString() ?? '',
      bookAuthor: json['book_author']?.toString() ?? '',
      bookImageUrl: json['book_image_url']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      status: OutboxStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OutboxStatus.pending,
      ),
      lastError: json['last_error']?.toString(),
      lastAttemptAt: json['last_attempt_at'] != null
          ? DateTime.tryParse(json['last_attempt_at'].toString())
          : null,
      nextAttemptAt: json['next_attempt_at'] != null
          ? DateTime.tryParse(json['next_attempt_at'].toString())
          : null,
    );
  }
}
