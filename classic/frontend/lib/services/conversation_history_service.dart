import 'dart:convert';

import 'package:auto_gpt_flutter_client/models/conversation_history_entry.dart';
import 'package:auto_gpt_flutter_client/services/shared_preferences_service.dart';

/// Handles storing and retrieving local conversation history so that
/// interactions can be replayed when invoking a local LLM.
class ConversationHistoryService {
  ConversationHistoryService(this._preferencesService);

  final SharedPreferencesService _preferencesService;

  static const int _maxEntries = 200;

  String _historyKey(String taskId) => 'conversation_history_$taskId';

  Future<List<ConversationHistoryEntry>> loadHistory(String taskId) async {
    final stored = await _preferencesService.getString(_historyKey(taskId));
    if (stored == null || stored.isEmpty) {
      return [];
    }

    final List<dynamic> decoded = jsonDecode(stored) as List<dynamic>;
    return decoded
        .map((entry) => ConversationHistoryEntry.fromJson(
            entry as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveHistory(
    String taskId,
    List<ConversationHistoryEntry> entries,
  ) async {
    final trimmedEntries = entries.length > _maxEntries
        ? entries.sublist(entries.length - _maxEntries)
        : entries;

    final serialized = jsonEncode(
      trimmedEntries.map((entry) => entry.toJson()).toList(),
    );
    await _preferencesService.setString(_historyKey(taskId), serialized);
  }

  Future<void> appendEntry(
    String taskId,
    ConversationHistoryEntry entry,
  ) async {
    final history = await loadHistory(taskId);
    history.add(entry);
    await saveHistory(taskId, history);
  }

  Future<void> clearHistory(String taskId) async {
    await _preferencesService.remove(_historyKey(taskId));
  }
}
