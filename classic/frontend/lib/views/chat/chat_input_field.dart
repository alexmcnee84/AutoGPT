import 'dart:io' as io;
import 'dart:typed_data';

import 'package:auto_gpt_flutter_client/models/attachment.dart';
import 'package:auto_gpt_flutter_client/viewmodels/chat_viewmodel.dart';
import 'package:auto_gpt_flutter_client/views/chat/continuous_mode_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';

class ChatInputField extends StatefulWidget {
  // Callback to be triggered when the send button is pressed
  final Function(String) onSendPressed;
  final Function() onContinuousModePressed;
  final bool isContinuousMode;
  // TODO: Create a view model for this class and remove the ChatViewModel
  final ChatViewModel viewModel;

  const ChatInputField({
    Key? key,
    required this.onSendPressed,
    required this.onContinuousModePressed,
    this.isContinuousMode = false,
    required this.viewModel,
  }) : super(key: key);

  @override
  _ChatInputFieldState createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  // Controller for the TextField to manage its content
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _throwawayFocusNode = FocusNode();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_handleViewModelUpdated);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && widget.isContinuousMode) {
        widget.onContinuousModePressed();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose(); // Dispose of the FocusNode when you're done.
    widget.viewModel.removeListener(_handleViewModelUpdated);
    _speechToText.stop();
    super.dispose();
  }

  void _handleViewModelUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _presentContinuousModeDialogIfNeeded() async {
    final showContinuousModeDialog = await widget.viewModel.prefsService
            .getBool('showContinuousModeDialog') ??
        true;

    FocusScope.of(context).requestFocus(_throwawayFocusNode);
    if (showContinuousModeDialog) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return ContinuousModeDialog(
            onProceed: () {
              Navigator.of(context).pop();
              _executeContinuousMode();
            },
            onCheckboxChanged: (bool value) async {
              await widget.viewModel.prefsService
                  .setBool('showContinuousModeDialog', !value);
            },
          );
        },
      );
    } else {
      _executeContinuousMode();
    }
  }

  void _executeContinuousMode() {
    if (!widget.isContinuousMode) {
      if (_canSend()) {
        widget.onSendPressed(_controller.text);
        _controller.clear();
        _focusNode.unfocus();
      }
    }
    widget.onContinuousModePressed();
  }

  bool _canSend() {
    final trimmed = _controller.text.trim();
    return trimmed.isNotEmpty || widget.viewModel.pendingAttachments.isNotEmpty;
  }

  Future<void> _handleFileSelection() async {
    final result = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true);
    if (result == null) {
      return;
    }

    for (final file in result.files) {
      Uint8List? bytes = file.bytes;
      if (bytes == null && !kIsWeb && file.path != null) {
        bytes = await io.File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        continue;
      }

      final attachment = Attachment(
        name: file.name,
        mimeType: file.mimeType ?? 'application/octet-stream',
        bytes: bytes,
      );

      widget.viewModel.addAttachment(attachment);
    }
  }

  Future<void> _handleVoiceInput() async {
    if (!_isListening) {
      final available = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          setState(() {
            _isListening = false;
          });
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
        });
        await _speechToText.listen(onResult: (result) {
          if (!mounted) {
            return;
          }
          setState(() {
            _controller.text = result.recognizedWords;
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          });
        });
      }
    } else {
      await _speechToText.stop();
      setState(() {
        _isListening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Using LayoutBuilder to provide the current constraints of the widget,
    // ensuring it rebuilds when the window size changes
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the width of the chat view based on the constraints provided
        double chatViewWidth = constraints.maxWidth;

        // Determine the width of the input field based on the chat view width.
        // If the chat view width is 1000 or more, the input width will be 900.
        // Otherwise, the input width will be the chat view width minus 40.
        double inputWidth = (chatViewWidth >= 1000) ? 900 : chatViewWidth - 40;

        return Container(
          width: inputWidth,
          // Defining the minimum and maximum height for the TextField container
          constraints: const BoxConstraints(
            minHeight: 50,
            maxHeight: 400,
          ),
          // Styling the container with a border and rounded corners
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.viewModel.pendingAttachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.viewModel.pendingAttachments
                        .map(
                          (attachment) => InputChip(
                            label: Text(attachment.name),
                            onDeleted: () {
                              widget.viewModel.removeAttachment(attachment);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  reverse: true,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onSubmitted: (_) {
                      if (_canSend()) {
                        widget.onSendPressed(_controller.text);
                        _controller.clear();
                      }
                    },
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Type a message, upload a file, or use voice...',
                      border: InputBorder.none,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Attach files',
                            child: IconButton(
                              icon: const Icon(Icons.attach_file),
                              onPressed: _handleFileSelection,
                            ),
                          ),
                          Tooltip(
                            message: _isListening
                                ? 'Stop voice input'
                                : 'Start voice input',
                            child: IconButton(
                              icon: Icon(
                                  _isListening ? Icons.stop : Icons.mic),
                              onPressed: _handleVoiceInput,
                            ),
                          ),
                          if (!widget.isContinuousMode)
                            Tooltip(
                              message: 'Send a single message',
                              child: IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: () {
                                  if (_canSend()) {
                                    widget.onSendPressed(_controller.text);
                                    _controller.clear();
                                  }
                                },
                              ),
                            ),
                          Tooltip(
                            message: widget.isContinuousMode
                                ? ''
                                : 'Enable continuous mode',
                            child: IconButton(
                              icon: Icon(widget.isContinuousMode
                                  ? Icons.pause
                                  : Icons.fast_forward),
                              onPressed: () {
                                if (!widget.isContinuousMode) {
                                  _presentContinuousModeDialogIfNeeded();
                                } else {
                                  widget.onContinuousModePressed();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
