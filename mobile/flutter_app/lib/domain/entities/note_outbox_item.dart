import 'favorite_outbox_item.dart' show OutboxStatus;

enum NoteOutboxAction {
  create,
  update,
  delete,
}

class NoteOutboxItem {
  final String id; // format: 'outbox_note_${userId}_$clientNoteId'
  final String userId;
  final String clientNoteId;
  final String? serverId;
  final String bookId;
  final NoteOutboxAction action;
  final String noteType;
  final String content;
  final DateTime createdAt;
  final OutboxStatus status;
  final int retryCount;
  final String? lastError;
  final DateTime? lastAttemptAt;
  final String? bookTitle;
  final String? bookAuthor;
  final String? bookThumbnail;

  const NoteOutboxItem({
    required this.id,
    required this.userId,
    required this.clientNoteId,
    this.serverId,
    required this.bookId,
    required this.action,
    required this.noteType,
    required this.content,
    required this.createdAt,
    this.status = OutboxStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptAt,
    this.bookTitle,
    this.bookAuthor,
    this.bookThumbnail,
  });

  NoteOutboxItem copyWith({
    String? id,
    String? userId,
    String? clientNoteId,
    String? serverId,
    String? bookId,
    NoteOutboxAction? action,
    String? noteType,
    String? content,
    DateTime? createdAt,
    OutboxStatus? status,
    int? retryCount,
    String? lastError,
    DateTime? lastAttemptAt,
    String? bookTitle,
    String? bookAuthor,
    String? bookThumbnail,
    bool clearLastError = false,
  }) {
    return NoteOutboxItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      clientNoteId: clientNoteId ?? this.clientNoteId,
      serverId: serverId ?? this.serverId,
      bookId: bookId ?? this.bookId,
      action: action ?? this.action,
      noteType: noteType ?? this.noteType,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookThumbnail: bookThumbnail ?? this.bookThumbnail,
    );
  }

  factory NoteOutboxItem.fromJson(Map<String, dynamic> json) {
    NoteOutboxAction parseAction(dynamic raw) {
      if (raw == 'create' || raw == 'NoteOutboxAction.create') return NoteOutboxAction.create;
      if (raw == 'update' || raw == 'NoteOutboxAction.update') return NoteOutboxAction.update;
      if (raw == 'delete' || raw == 'NoteOutboxAction.delete') return NoteOutboxAction.delete;
      return NoteOutboxAction.create;
    }

    OutboxStatus parseStatus(dynamic raw) {
      if (raw == 'syncing') return OutboxStatus.syncing;
      if (raw == 'failed') return OutboxStatus.failed;
      if (raw == 'permanentFailure') return OutboxStatus.permanentFailure;
      return OutboxStatus.pending;
    }

    DateTime parseDate(dynamic d) {
      if (d is String && d.isNotEmpty) {
        try {
          return DateTime.parse(d);
        } catch (_) {}
      }
      return DateTime.now();
    }

    return NoteOutboxItem(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      clientNoteId: json['clientNoteId']?.toString() ?? json['client_note_id']?.toString() ?? '',
      serverId: json['serverId']?.toString() ?? json['server_id']?.toString(),
      bookId: json['bookId']?.toString() ?? json['book_id']?.toString() ?? '',
      action: parseAction(json['action']),
      noteType: json['noteType']?.toString() ?? json['note_type']?.toString() ?? 'personal_note',
      content: json['content']?.toString() ?? '',
      createdAt: parseDate(json['createdAt'] ?? json['created_at']),
      status: parseStatus(json['status']),
      retryCount: json['retryCount'] is int ? json['retryCount'] as int : 0,
      lastError: json['lastError']?.toString(),
      lastAttemptAt: json['lastAttemptAt'] != null ? parseDate(json['lastAttemptAt']) : null,
      bookTitle: json['bookTitle']?.toString(),
      bookAuthor: json['bookAuthor']?.toString(),
      bookThumbnail: json['bookThumbnail']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'clientNoteId': clientNoteId,
      if (serverId != null) 'serverId': serverId,
      'bookId': bookId,
      'action': action.name,
      'noteType': noteType,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      'retryCount': retryCount,
      if (lastError != null) 'lastError': lastError,
      if (lastAttemptAt != null) 'lastAttemptAt': lastAttemptAt!.toIso8601String(),
      if (bookTitle != null) 'bookTitle': bookTitle,
      if (bookAuthor != null) 'bookAuthor': bookAuthor,
      if (bookThumbnail != null) 'bookThumbnail': bookThumbnail,
    };
  }
}
