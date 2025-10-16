import 'dart:convert';
import 'dart:typed_data';

/// Represents a file attachment that can be shared with the agent.
class Attachment {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  Attachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  /// Creates an [Attachment] from a JSON representation.
  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      name: json['name'] as String,
      mimeType: json['mime_type'] as String,
      bytes: base64Decode(json['data'] as String),
    );
  }

  /// Converts the attachment to JSON. The binary payload is encoded as base64.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'mime_type': mimeType,
      'data': base64Encode(bytes),
    };
  }

  /// Converts the attachment metadata without the binary payload.
  Map<String, dynamic> toMetadataJson() {
    return {
      'name': name,
      'mime_type': mimeType,
      'size': bytes.length,
    };
  }
}
