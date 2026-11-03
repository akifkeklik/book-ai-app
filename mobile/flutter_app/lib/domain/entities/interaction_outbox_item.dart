import 'favorite_outbox_item.dart' show OutboxStatus;

class InteractionOutboxItem {
  final String id; // format: 'interaction_${userId}_$isbn13'
  final String userId;
  final String isbn13;
  final String interaction; // 'want_to_read', 'reading', 'finished', 'like', 'dislike', 'clear'
  final DateTime createdAt;
  final int retryCount;
  final OutboxStatus status;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;

  const InteractionOutboxItem({
    required this.id,
    required this.userId,
    required this.isbn13,
    required this.interaction,
    required this.createdAt,
    this.retryCount = 0,
    this.status = OutboxStatus.pending,
    this.lastError,
    this.lastAttemptAt,
    this.nextAttemptAt,
  });

  InteractionOutboxItem copyWith({
    String? id,
    String? userId,
    String? isbn13,
    String? interaction,
    DateTime? createdAt,
    int? retryCount,
    OutboxStatus? status,
    String? lastError,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    bool clearLastError = false,
    bool clearNextAttemptAt = false,
  }) {
    return InteractionOutboxItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      isbn13: isbn13 ?? this.isbn13,
      interaction: interaction ?? this.interaction,
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
        'interaction': interaction,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
        'status': status.name,
        'last_error': lastError,
        'last_attempt_at': lastAttemptAt?.toIso8601String(),
        'next_attempt_at': nextAttemptAt?.toIso8601String(),
      };

  factory InteractionOutboxItem.fromJson(Map<String, dynamic> json) {
    return InteractionOutboxItem(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      isbn13: json['isbn13']?.toString() ?? '',
      interaction: json['interaction']?.toString() ?? 'want_to_read',
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
