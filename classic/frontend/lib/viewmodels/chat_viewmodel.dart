import 'package:auto_gpt_flutter_client/models/attachment.dart';
import 'package:auto_gpt_flutter_client/models/chat.dart';
import 'package:auto_gpt_flutter_client/models/conversation_history_entry.dart';
import 'package:auto_gpt_flutter_client/models/message_type.dart';
import 'package:auto_gpt_flutter_client/models/step.dart';
import 'package:auto_gpt_flutter_client/models/step_request_body.dart';
import 'package:auto_gpt_flutter_client/services/chat_service.dart';
import 'package:auto_gpt_flutter_client/services/conversation_history_service.dart';
import 'package:auto_gpt_flutter_client/services/shared_preferences_service.dart';
import 'package:flutter/foundation.dart';

class ChatViewModel with ChangeNotifier {
  final ChatService _chatService;
  final SharedPreferencesService _prefsService;
  final ConversationHistoryService _historyService;

  List<Chat> _chats = [];
  String? _currentTaskId;
  final List<Attachment> _pendingAttachments = [];
  List<ConversationHistoryEntry> _conversationHistory = [];

  bool _isWaitingForAgentResponse = false;
  bool _isContinuousMode = false;

  ChatViewModel(
      this._chatService, this._prefsService, this._historyService);

  bool get isWaitingForAgentResponse => _isWaitingForAgentResponse;
  SharedPreferencesService get prefsService => _prefsService;

  bool get isContinuousMode => _isContinuousMode;
  set isContinuousMode(bool value) {
    _isContinuousMode = value;
    notifyListeners();
  }

  List<Chat> get chats => _chats;
  String? get currentTaskId => _currentTaskId;

  List<Attachment> get pendingAttachments =>
      List.unmodifiable(_pendingAttachments);

  List<ConversationHistoryEntry> get conversationHistory =>
      List.unmodifiable(_conversationHistory);

  void setCurrentTaskId(String taskId) {
    if (_currentTaskId != taskId) {
      _currentTaskId = taskId;
      fetchChatsForTask();
      _loadConversationHistory();
    }
  }

  void clearCurrentTaskAndChats() {
    _currentTaskId = null;
    _chats.clear();
    _pendingAttachments.clear();
    _conversationHistory = [];
    notifyListeners();
  }

  Future<void> fetchChatsForTask() async {
    if (_currentTaskId == null) {
      print("Error: Task ID is not set.");
      return;
    }
    try {
      final Map<String, dynamic> stepsResponse =
          await _chatService.listTaskSteps(_currentTaskId!, pageSize: 10000);

      final List<dynamic> stepsJsonList = stepsResponse['steps'] ?? [];
      List<Step> steps =
          stepsJsonList.map((stepMap) => Step.fromMap(stepMap)).toList();

      List<Chat> chats = [];
      DateTime currentTimestamp = DateTime.now();

      for (int i = 0; i < steps.length; i++) {
        Step step = steps[i];

        if (step.input.isNotEmpty) {
          chats.add(Chat(
              id: step.stepId,
              taskId: step.taskId,
              message: step.input,
              timestamp: currentTimestamp,
              messageType: MessageType.user,
              artifacts: step.artifacts));
        }

        chats.add(Chat(
            id: step.stepId,
            taskId: step.taskId,
            message: step.output,
            timestamp: currentTimestamp,
            messageType: MessageType.agent,
            jsonResponse: stepsJsonList[i],
            artifacts: step.artifacts));
      }

      if (chats.isNotEmpty) {
        _chats = chats;
      }

      await _loadConversationHistory(seedChats: chats);

      notifyListeners();

      print(
          "Chats (and steps) fetched successfully for task ID: $_currentTaskId");
    } catch (error) {
      print("Error fetching chats: $error");
    }
  }

  Future<void> sendChatMessage(String message,
      {required int continuousModeSteps, int currentStep = 1}) async {
    if (_currentTaskId == null) {
      print("Error: Task ID is not set.");
      return;
    }

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }

    final String outgoingMessage =
        trimmedMessage.isEmpty ? '[File Upload]' : trimmedMessage;

    final ConversationHistoryEntry userHistoryEntry =
        ConversationHistoryEntry(
      messageType: MessageType.user,
      message: outgoingMessage,
      timestamp: DateTime.now(),
      attachments: List.from(_pendingAttachments),
    );

    final List<Map<String, dynamic>> conversationPayload = [
      ..._conversationHistory
          .map((entry) => entry.toPayloadJson(includeAttachmentData: false)),
      userHistoryEntry.toPayloadJson(includeAttachmentData: true),
    ];

    final Map<String, dynamic> additionalInput = {
      'conversation_history': conversationPayload,
    };

    if (_pendingAttachments.isNotEmpty) {
      additionalInput['attachments'] =
          _pendingAttachments.map((attachment) => attachment.toJson()).toList();
    }

    _isWaitingForAgentResponse = true;
    notifyListeners();

    try {
      StepRequestBody requestBody = StepRequestBody(
        input: outgoingMessage,
        additionalInput: additionalInput,
      );

      Map<String, dynamic> executedStepResponse =
          await _chatService.executeStep(_currentTaskId!, requestBody);

      Step executedStep = Step.fromMap(executedStepResponse);

      if (executedStep.input.isNotEmpty) {
        final userChat = Chat(
            id: executedStep.stepId,
            taskId: executedStep.taskId,
            message: executedStep.input,
            timestamp: DateTime.now(),
            messageType: MessageType.user,
            artifacts: executedStep.artifacts);

        _chats.add(userChat);
      }

      final agentChat = Chat(
          id: executedStep.stepId,
          taskId: executedStep.taskId,
          message: executedStep.output,
          timestamp: DateTime.now(),
          messageType: MessageType.agent,
          jsonResponse: executedStepResponse,
          artifacts: executedStep.artifacts);

      _chats.add(agentChat);

      removeTemporaryMessage();

      _pendingAttachments.clear();

      final ConversationHistoryEntry agentHistoryEntry =
          ConversationHistoryEntry(
        messageType: MessageType.agent,
        message: agentChat.message,
        timestamp: agentChat.timestamp,
      );

      _conversationHistory.addAll([userHistoryEntry, agentHistoryEntry]);
      await _historyService.saveHistory(_currentTaskId!, _conversationHistory);

      notifyListeners();

      if (_isContinuousMode && !executedStep.isLast) {
        print("Continuous Mode: Step $currentStep of $continuousModeSteps");
        if (currentStep < continuousModeSteps) {
          await sendChatMessage("",
              continuousModeSteps: continuousModeSteps,
              currentStep: currentStep + 1);
        } else {
          _isContinuousMode = false;
        }
      }

      print("Chats added for task ID: $_currentTaskId");
    } catch (e) {
      removeTemporaryMessage();
      rethrow;
    } finally {
      _isWaitingForAgentResponse = false;
      notifyListeners();
    }
  }

  void addTemporaryMessage(String message) {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty && _pendingAttachments.isEmpty) {
      return;
    }
    final displayMessage = trimmedMessage.isNotEmpty
        ? trimmedMessage
        : 'Sent ${_pendingAttachments.length} attachment(s).';

    Chat tempMessage = Chat(
        id: "TEMP_ID",
        taskId: "TEMP_ID",
        message: displayMessage,
        timestamp: DateTime.now(),
        messageType: MessageType.user,
        artifacts: []);

    _chats.add(tempMessage);
    notifyListeners();
  }

  void removeTemporaryMessage() {
    _chats.removeWhere((chat) => chat.id == "TEMP_ID");
    notifyListeners();
  }

  void addAttachment(Attachment attachment) {
    _pendingAttachments.add(attachment);
    notifyListeners();
  }

  void removeAttachment(Attachment attachment) {
    _pendingAttachments.remove(attachment);
    notifyListeners();
  }

  Future<void> clearConversationHistory() async {
    if (_currentTaskId == null) {
      return;
    }
    await _historyService.clearHistory(_currentTaskId!);
    _conversationHistory = [];
    notifyListeners();
  }

  Future<void> _loadConversationHistory({List<Chat>? seedChats}) async {
    if (_currentTaskId == null) {
      return;
    }

    final history = await _historyService.loadHistory(_currentTaskId!);
    if (history.isNotEmpty) {
      _conversationHistory = history;
      return;
    }

    if (seedChats != null && seedChats.isNotEmpty) {
      _conversationHistory = seedChats
          .map(
            (chat) => ConversationHistoryEntry(
              messageType: chat.messageType,
              message: chat.message,
              timestamp: chat.timestamp,
            ),
          )
          .toList();
      await _historyService.saveHistory(_currentTaskId!, _conversationHistory);
    } else {
      _conversationHistory = [];
    }
  }

  Future<void> downloadArtifact(String taskId, String artifactId) async {
    try {
      await _chatService.downloadArtifact(taskId, artifactId);
      print("Artifact $artifactId downloaded successfully for task $taskId!");
    } catch (error) {
      print("Error downloading artifact: $error");
    }
  }
}
