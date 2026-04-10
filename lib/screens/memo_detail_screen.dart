import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../themes/app_theme.dart';
import 'add_task_screen.dart';

class MemoDetailScreen extends StatefulWidget {
  final String memoId;
  final String title;
  final String body;
  final bool isCreating;

  const MemoDetailScreen({
    super.key,
    this.memoId = '',
    this.title = '',
    this.body = '',
    this.isCreating = false,
  });

  @override
  State<MemoDetailScreen> createState() => _MemoDetailScreenState();
}

class _MemoDetailScreenState extends State<MemoDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _background = AppTheme.pageBackground;
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFFAC638);
  static const _accentColorNew = Color(0xFFE2B736);
  static const _cardBorder = Color.fromRGBO(250, 198, 56, 0.05);
  static const _bodyText = Color(0xFF334155);

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _bodyFocusNode;
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final AnimationController _voiceBarsController;

  late String _originalTitle;
  late String _originalBody;
  late bool _isCreatingMode;
  late String _currentMemoId;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isAnalyzingTask = false;
  bool _speechReady = false;
  bool _isListening = false;
  double _soundLevel = 0;
  String _voiceTarget = 'body';
  String _listeningTarget = 'body';
  String _voiceBaseText = '';

  bool get _hasChanges {
    return _titleController.text.trim() != _originalTitle.trim() ||
        _bodyController.text.trim() != _originalBody.trim();
  }

  @override
  void initState() {
    super.initState();
    _originalTitle = widget.title;
    _originalBody = widget.body;
    _isCreatingMode = widget.isCreating;
    _currentMemoId = widget.memoId;
    _isEditing = widget.isCreating;
    _titleController = TextEditingController(text: widget.title)
      ..addListener(_handleFieldChanged);
    _bodyController = TextEditingController(text: widget.body)
      ..addListener(_handleFieldChanged);
    _titleFocusNode = FocusNode()..addListener(_handleFocusChange);
    _bodyFocusNode = FocusNode()..addListener(_handleFocusChange);
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initSpeech();
  }

  void _handleFieldChanged() {
    if (!mounted || !_isEditing) {
      return;
    }
    setState(() {});
  }

  void _handleFocusChange() {
    if (!mounted || _isListening) {
      return;
    }

    final nextTarget = _titleFocusNode.hasFocus ? 'title' : 'body';
    if (nextTarget == _voiceTarget) {
      return;
    }

    setState(() {
      _voiceTarget = nextTarget;
    });
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = ready;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
      });
    }
  }

  Future<_SavedMemo?> _saveMemo({
    bool popAfterCreate = true,
    bool showSuccessMessage = true,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (user == null) {
      _showMessage('Please sign in to save your memo.');
      return null;
    }

    if (title.isEmpty && body.isEmpty) {
      _showMessage('Please enter your memo first.');
      return null;
    }

    final effectiveTitle = title.isNotEmpty ? title : _fallbackTitle(body);

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isCreatingMode) {
        final docRef = await FirebaseFirestore.instance
            .collection('memos')
            .add({
              'userId': user.uid,
              'title': effectiveTitle,
              'body': body,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

        _originalTitle = effectiveTitle;
        _originalBody = body;
        _currentMemoId = docRef.id;

        if (_titleController.text.trim().isEmpty) {
          _titleController.text = effectiveTitle;
          _titleController.selection = TextSelection.collapsed(
            offset: _titleController.text.length,
          );
        }

        if (!mounted) {
          return _SavedMemo(
            memoId: docRef.id,
            title: effectiveTitle,
            body: body,
          );
        }

        setState(() {
          _isCreatingMode = false;
          _isEditing = false;
        });

        if (popAfterCreate) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Memo saved.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        } else if (showSuccessMessage) {
          _showMessage('Memo saved.');
        }

        return _SavedMemo(memoId: docRef.id, title: effectiveTitle, body: body);
      }

      if (_currentMemoId.isEmpty) {
        throw StateError('Missing memo id.');
      }

      await FirebaseFirestore.instance
          .collection('memos')
          .doc(_currentMemoId)
          .update({
            'title': effectiveTitle,
            'body': body,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _originalTitle = effectiveTitle;
      _originalBody = body;

      if (!mounted) {
        return _SavedMemo(
          memoId: _currentMemoId,
          title: effectiveTitle,
          body: body,
        );
      }

      setState(() {
        _isEditing = false;
      });

      if (showSuccessMessage) {
        _showMessage('Memo updated.');
      }

      return _SavedMemo(
        memoId: _currentMemoId,
        title: effectiveTitle,
        body: body,
      );
    } catch (_) {
      _showMessage('Failed to save memo. Please try again.');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
  }

  void _cancelEditing() {
    _titleController.text = _originalTitle;
    _bodyController.text = _originalBody;
    setState(() {
      _isEditing = false;
    });
  }

  String _fallbackTitle(String body) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return 'Untitled Memo';
    }

    final firstLine = trimmedBody.split('\n').first.trim();
    if (firstLine.length <= 28) {
      return firstLine;
    }
    return '${firstLine.substring(0, 28).trimRight()}...';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _analyzeMemoAndOpenTask() async {
    if (_isSaving || _isAnalyzingTask) {
      return;
    }

    final savedMemo = (_isCreatingMode || (_isEditing && _hasChanges))
        ? await _saveMemo(popAfterCreate: false, showSuccessMessage: false)
        : _SavedMemo(
            memoId: _currentMemoId,
            title: _originalTitle,
            body: _originalBody,
          );

    if (savedMemo == null) {
      return;
    }

    final memoTitle = savedMemo.title.trim();
    final memoBody = savedMemo.body.trim();

    if (memoTitle.isEmpty && memoBody.isEmpty) {
      _showMessage('This memo is empty.');
      return;
    }

    setState(() {
      _isAnalyzingTask = true;
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'australia-southeast1',
      ).httpsCallable('analyzeMemoToTask');

      final result = await callable.call(<String, dynamic>{
        'title': memoTitle,
        'body': memoBody,
        'timezone': DateTime.now().timeZoneName,
        'currentDateISO': _currentDateISO(),
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final draft = _MemoTaskDraft.fromMap(data);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddTaskScreen(
            initialTitle: draft.title.isNotEmpty ? draft.title : memoTitle,
            initialNotes: draft.notes.isNotEmpty ? draft.notes : memoBody,
            initialDate: draft.date,
            initialTime: draft.time,
            initialCategory: draft.category,
            initialReminderEnabled: draft.reminderEnabled,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      _showMessage(_mapFunctionError(error));
    } catch (_) {
      _showMessage('Failed to analyze memo. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingTask = false;
        });
      }
    }
  }

  String _mapFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'invalid-argument':
        return 'This memo does not have enough content to analyze.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a few seconds.';
      default:
        return error.message ?? 'AI analysis failed. Please try again.';
    }
  }

  String _currentDateISO() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _toggleListening() async {
    if (_isSaving || _isAnalyzingTask) {
      return;
    }

    if (!_isEditing) {
      _startEditing();
    }

    if (_isListening) {
      await _speech.stop();
      return;
    }

    if (!_speechReady) {
      await _initSpeech();
    }

    if (!_speechReady) {
      _showMessage('Voice input is not available on this device.');
      return;
    }

    if (!mounted) {
      return;
    }

    final target = _titleFocusNode.hasFocus
        ? 'title'
        : _bodyFocusNode.hasFocus
        ? 'body'
        : _voiceTarget;

    _titleFocusNode.unfocus();
    _bodyFocusNode.unfocus();
    FocusScope.of(context).unfocus();

    _listeningTarget = target;
    _voiceTarget = _listeningTarget;
    final controller = _listeningTarget == 'title'
        ? _titleController
        : _bodyController;
    _voiceBaseText = controller.text;

    if (_voiceBaseText.isNotEmpty &&
        !_voiceBaseText.endsWith(' ') &&
        !_voiceBaseText.endsWith('\n')) {
      _voiceBaseText = '$_voiceBaseText ';
    }

    final started = await _speech.listen(
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 8),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onSoundLevelChange: (level) {
        if (!mounted) {
          return;
        }
        setState(() {
          _soundLevel = level;
        });
      },
      onResult: (result) {
        if (!mounted) {
          return;
        }

        final transcript = result.recognizedWords.trim();
        final nextText = transcript.isEmpty
            ? _voiceBaseText.trimRight()
            : '$_voiceBaseText$transcript';
        final targetController = _listeningTarget == 'title'
            ? _titleController
            : _bodyController;

        targetController.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = started;
      _soundLevel = 0;
    });

    if (started) {
      _startVoiceBars();
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    if (status == 'listening') {
      setState(() {
        _isListening = true;
      });
      _startVoiceBars();
      return;
    }

    if (status == 'done' || status == 'notListening') {
      setState(() {
        _isListening = false;
        _soundLevel = 0;
      });
      _stopVoiceBars();
    }
  }

  void _handleSpeechError(dynamic error) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
      _soundLevel = 0;
    });
    _stopVoiceBars();

    if (error?.permanent != true) {
      _showMessage('Voice input stopped. Please try again.');
    }
  }

  void _startVoiceBars() {
    if (!_voiceBarsController.isAnimating) {
      _voiceBarsController.repeat();
    }
  }

  void _stopVoiceBars() {
    _voiceBarsController.stop();
  }

  @override
  void dispose() {
    _voiceBarsController.dispose();
    _speech.cancel();
    _titleFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _bodyFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _titleController
      ..removeListener(_handleFieldChanged)
      ..dispose();
    _bodyController
      ..removeListener(_handleFieldChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: statusBarHeight,
            child: const ColoredBox(color: AppTheme.headerBackground),
          ),
          SafeArea(
            child: Center(
              child: Container(
                width: 430,
                constraints: const BoxConstraints(maxWidth: 430),
                height: double.infinity,
                color: _background,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        children: [
                          const SizedBox(height: 89),
                          Expanded(child: _buildContent(context)),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildAppBar(context),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 20,
                      child: _buildBottomActions(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final actionLabel = _isCreatingMode
        ? 'Save'
        : _isEditing
        ? (_hasChanges ? 'Save' : 'Edit')
        : 'Edit';

    return Container(
      height: 89,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: AppTheme.headerBackground,
        boxShadow: const [AppTheme.headerShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppTheme.backButton(
            context,
            onPressed: () {
              if (_isEditing && !_isCreatingMode) {
                _cancelEditing();
                return;
              }
              Navigator.of(context).pop();
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                _isCreatingMode ? 'New Memo' : 'Memo Detail',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _primaryColor,
                  letterSpacing: -0.45,
                ),
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _isSaving
                ? null
                : () {
                    if (_isCreatingMode) {
                      _saveMemo();
                      return;
                    }

                    if (!_isEditing) {
                      _startEditing();
                      return;
                    }

                    if (_hasChanges) {
                      _saveMemo();
                    }
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accentColor,
                      ),
                    )
                  : Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _accentColorNew,
                        letterSpacing: 0.35,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(24, 0, 24, 188 + keyboardInset),
      child: Column(
        children: [
          const SizedBox(height: 39),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _cardBorder),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(25, 21, 25, 25),
            child: _isEditing ? _buildEditableBody() : _buildReadOnlyBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          maxLines: 2,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'Memo title',
            border: InputBorder.none,
            isCollapsed: true,
          ),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _primaryColor,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bodyController,
          focusNode: _bodyFocusNode,
          maxLines: 14,
          minLines: 10,
          decoration: const InputDecoration(
            hintText: 'Write your memo here...',
            border: InputBorder.none,
            isCollapsed: true,
          ),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: _bodyText,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _originalTitle,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _primaryColor,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _originalBody,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: _bodyText,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isListening) ...[
          _buildListeningBanner(),
          const SizedBox(height: 12),
        ],
        _buildAddTaskButton(context),
        const SizedBox(height: 14),
        _buildVoiceInputButton(),
      ],
    );
  }

  Widget _buildAddTaskButton(BuildContext context) {
    return GestureDetector(
      onTap: _isAnalyzingTask || _isSaving ? null : _analyzeMemoAndOpenTask,
      child: Opacity(
        opacity: (_isAnalyzingTask || _isSaving) ? 0.7 : 1,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFAC638), Color(0xFFF59E0B)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFAC638).withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isAnalyzingTask
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _isCreatingMode ? 'Save & Add Task' : 'Add Task',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceInputButton() {
    final targetLabel = _voiceTarget == 'title' ? 'Title' : 'Content';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _isListening
              ? 'Listening for $targetLabel'
              : 'Voice input for $targetLabel',
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _toggleListening,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isListening
                    ? const [Color(0xFFF59E0B), Color(0xFFEA580C)]
                    : const [Color(0xFFFFF6D8), Color(0xFFF7E6A8)],
              ),
              border: Border.all(
                color: _isListening
                    ? const Color(0xFFF59E0B)
                    : const Color(0x33FAC638),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (_isListening
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFFAC638))
                          .withValues(alpha: 0.24),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none_rounded,
              color: _isListening ? Colors.white : _accentColor,
              size: 30,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListeningBanner() {
    final targetLabel = _listeningTarget == 'title' ? 'Title' : 'Content';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22F59E0B)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _VoiceBars(
              animation: _voiceBarsController,
              level: _soundLevel,
              color: _accentColor,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Listening to $targetLabel',
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedMemo {
  const _SavedMemo({
    required this.memoId,
    required this.title,
    required this.body,
  });

  final String memoId;
  final String title;
  final String body;
}

class _VoiceBars extends StatelessWidget {
  const _VoiceBars({
    required this.animation,
    required this.level,
    required this.color,
  });

  final Animation<double> animation;
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final normalizedLevel = level.isFinite
            ? ((level + 2) / 12).clamp(0.15, 1.0)
            : 0.2;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(10, (index) {
            final phase = animation.value * math.pi * 2 + index * 0.55;
            final height = 10 + math.sin(phase).abs() * 20 * normalizedLevel;

            return Container(
              width: 5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        );
      },
    );
  }
}

class _MemoTaskDraft {
  const _MemoTaskDraft({
    required this.title,
    required this.notes,
    required this.category,
    required this.date,
    required this.time,
    required this.reminderEnabled,
  });

  final String title;
  final String notes;
  final String? category;
  final DateTime? date;
  final TimeOfDay? time;
  final bool reminderEnabled;

  factory _MemoTaskDraft.fromMap(Map<String, dynamic> map) {
    final date = _parseDate(map['dateISO'] as String?);
    final time = _parseTime(map['time24h'] as String?);

    return _MemoTaskDraft(
      title: (map['title'] as String? ?? '').trim(),
      notes: (map['notes'] as String? ?? '').trim(),
      category: (map['category'] as String?)?.trim(),
      date: date,
      time: time,
      reminderEnabled: map['reminderEnabled'] as bool? ?? true,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }

  static TimeOfDay? _parseTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parts = value.trim().split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }
}
