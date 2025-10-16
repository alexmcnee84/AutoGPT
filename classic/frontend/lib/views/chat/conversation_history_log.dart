import 'package:auto_gpt_flutter_client/models/conversation_history_entry.dart';
import 'package:auto_gpt_flutter_client/models/message_type.dart';
import 'package:flutter/material.dart';

class ConversationHistoryLog extends StatelessWidget {
  final List<ConversationHistoryEntry> entries;
  final VoidCallback onClear;

  const ConversationHistoryLog({
    super.key,
    required this.entries,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        title: Text(
          'Conversation History (${entries.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No history recorded yet.'),
            )
          else
            ...entries.map((entry) => ListTile(
                  title: Text(entry.message),
                  subtitle: Text(
                    '${_roleLabel(entry)} · ${entry.timestamp.toLocal()}',
                  ),
                  trailing: entry.attachments.isNotEmpty
                      ? Wrap(
                          spacing: 4,
                          children: entry.attachments
                              .map((attachment) => Chip(
                                    label: Text(attachment.name),
                                  ))
                              .toList(),
                        )
                      : null,
                )),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(
                right: 16.0,
                bottom: 12.0,
              ),
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear history'),
              ),
            ),
          )
        ],
      ),
    );
  }

  static String _roleLabel(ConversationHistoryEntry entry) {
    return entry.messageType == MessageType.user ? 'You' : 'Assistant';
  }
}
