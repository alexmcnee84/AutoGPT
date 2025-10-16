import 'package:auto_gpt_flutter_client/models/attachment.dart';
import 'package:auto_gpt_flutter_client/models/message_type.dart';

/// Stores a single entry of the conversation history for local playback.
class ConversationHistoryEntry {
  final MessageType messageType;
  final String message;
  final DateTime timestamp;
  final List<Attachment> attachments;

  ConversationHistoryEntry({
    required this.messageType,
    required this.message,
    required this.timestamp,
    this.attachments = const [],
  });

  factory ConversationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ConversationHistoryEntry(
      messageType: MessageType.values.firstWhere(
        (type) => type.toString() == json['messageType'],
        orElse: () => MessageType.user,
      ),
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .map((attachment) =>
              Attachment.fromJson(attachment as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageType': messageType.toString(),
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'attachments': attachments.map((attachment) => attachment.toJson()).toList(),
    };
  }

  Map<String, dynamic> toPayloadJson({bool includeAttachmentData = false}) {
    return {
      'role': messageType == MessageType.user ? 'user' : 'assistant',
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'attachments': attachments
          .map((attachment) => includeAttachmentData
              ? attachment.toJson()
              : attachment.toMetadataJson())
          .toList(),
    };
  }
}
