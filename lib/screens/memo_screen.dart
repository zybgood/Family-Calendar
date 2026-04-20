import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../navigation/app_bottom_nav.dart';
import '../themes/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/bottom_navigation_bar.dart';
import 'memo_detail_screen.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen>
    with SingleTickerProviderStateMixin {
  static const bgColor = AppTheme.pageBackground;
  static const primaryColor = Color(0xFF0F172A);
  static const accentColor = Color(0xFFE2B736);
  static const secondaryAccent = Color(0xFFFDE047);
  static const borderColor = Color.fromRGBO(236, 91, 19, 0.05);
  static const int _cardTitleLimit = 20;
  static const double _cancelEnterInset = 6;
  static const double _cancelExitInset = 24;

  final int _selectedNavIndex = 0;
  String? _deleteActionMemoId;
  String? _deletingMemoId;
  final GlobalKey _cancelVoiceZoneKey = GlobalKey();
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final AnimationController _voiceBarsController;
  late final ValueNotifier<_VoiceUiState> _voiceUi;
  bool _speechReady = false;
  bool? _pendingVoiceCancel;
  int _voiceSessionId = 0;
  String _voiceDraftText = '';

  bool get _isListening => _voiceUi.value.isListening;
  bool get _isVoiceTransitioning => _voiceUi.value.isVoiceTransitioning;
  bool get _isVoiceHoldActive => _voiceUi.value.isVoiceHoldActive;
  bool get _isCancelZoneActive => _voiceUi.value.isCancelZoneActive;
  bool get _isCreatingVoiceMemo => _voiceUi.value.isCreatingVoiceMemo;
  double get _soundLevel => _voiceUi.value.soundLevel;
  bool get _isVoiceOverlayVisible {
    return _voiceUi.value.isOverlayVisible;
  }

  @override
  void initState() {
    super.initState();
    _voiceUi = ValueNotifier(const _VoiceUiState());
    _voiceBarsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _initSpeech();
  }

  @override
  void dispose() {
    _voiceUi.dispose();
    _voiceBarsController.dispose();
    _speech.cancel();
    super.dispose();
  }

  void _updateVoiceUi(_VoiceUiState Function(_VoiceUiState current) transform) {
    final current = _voiceUi.value;
    final next = transform(current);
    if (identical(current, next) || current == next) {
      return;
    }
    _voiceUi.value = next;
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

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) {
      return true;
    }

    await _initSpeech();
    return _speechReady;
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

  void _startVoiceBars() {
    if (!_voiceBarsController.isAnimating) {
      _voiceBarsController.repeat();
    }
  }

  void _stopVoiceBars() {
    _voiceBarsController.stop();
  }

  void _resetVoiceOverlay({required bool clearText}) {
    _updateVoiceUi(
      (current) => current.copyWith(
        isListening: false,
        isVoiceTransitioning: false,
        isVoiceHoldActive: false,
        isCancelZoneActive: false,
        isCreatingVoiceMemo: false,
        soundLevel: 0,
      ),
    );
    _pendingVoiceCancel = null;
    if (clearText) {
      _voiceDraftText = '';
    }
    _stopVoiceBars();
  }

  void _updateCancelZoneState(Offset globalPosition) {
    if (!_isVoiceHoldActive) {
      return;
    }

    final renderObject = _cancelVoiceZoneKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      if (_isCancelZoneActive) {
        _updateVoiceUi(
          (current) => current.copyWith(isCancelZoneActive: false),
        );
      }
      return;
    }

    final origin = renderObject.localToGlobal(Offset.zero);
    final rect = origin & renderObject.size;
    final enterRect = rect.deflate(_cancelEnterInset);
    final exitRect = rect.inflate(_cancelExitInset);
    final nextValue = _isCancelZoneActive
        ? exitRect.contains(globalPosition)
        : enterRect.contains(globalPosition);

    if (nextValue == _isCancelZoneActive || !mounted) {
      return;
    }

    _updateVoiceUi(
      (current) => current.copyWith(isCancelZoneActive: nextValue),
    );
  }

  void _maybeCompleteReleasedVoiceSession() {
    final cancel = _pendingVoiceCancel;
    if (cancel == null ||
        _isVoiceHoldActive ||
        _speech.isListening ||
        _isListening) {
      return;
    }

    _completeReleasedVoiceSession(cancel: cancel);
  }

  void _completeReleasedVoiceSession({required bool cancel}) {
    if (_isCreatingVoiceMemo) {
      return;
    }

    final transcript = _voiceDraftText.trim();
    _voiceSessionId++;
    _pendingVoiceCancel = null;

    if (cancel || transcript.isEmpty) {
      _resetVoiceOverlay(clearText: true);
      return;
    }

    _resetVoiceOverlay(clearText: false);
    unawaited(_createMemoFromVoice(transcript));
  }

  Future<void> _startVoiceMemoCreation() async {
    if (_isVoiceTransitioning ||
        _isCreatingVoiceMemo ||
        _isListening ||
        _isVoiceHoldActive) {
      return;
    }

    final ready = await _ensureSpeechReady();
    if (!ready) {
      _showMessage('Voice input is not available on this device.');
      return;
    }

    if (!mounted) {
      return;
    }

    final sessionId = ++_voiceSessionId;
    _pendingVoiceCancel = null;
    _voiceDraftText = '';
    _updateVoiceUi(
      (current) => current.copyWith(
        isVoiceTransitioning: true,
        isVoiceHoldActive: true,
        isCancelZoneActive: false,
        soundLevel: 0,
      ),
    );
    _startVoiceBars();

    try {
      await _speech.listen(
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(minutes: 5),
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
        ),
        onSoundLevelChange: (level) {
          if (!mounted || sessionId != _voiceSessionId) {
            return;
          }
          _updateVoiceUi((current) => current.copyWith(soundLevel: level));
        },
        onResult: (result) {
          if (!mounted || sessionId != _voiceSessionId) {
            return;
          }
          _voiceDraftText = result.recognizedWords.trim();
        },
      );

      if (!mounted || sessionId != _voiceSessionId) {
        return;
      }

      _updateVoiceUi((current) => current.copyWith(isListening: true));
    } catch (_) {
      _voiceSessionId++;
      _resetVoiceOverlay(clearText: true);
      _showMessage('Unable to start voice input. Please try again.');
    } finally {
      if (mounted && sessionId == _voiceSessionId) {
        _updateVoiceUi(
          (current) => current.copyWith(isVoiceTransitioning: false),
        );
        _maybeCompleteReleasedVoiceSession();
      }
    }
  }

  Future<void> _stopVoiceMemoCreation({required bool cancel}) async {
    if ((!_isVoiceHoldActive && _pendingVoiceCancel == null) ||
        _isCreatingVoiceMemo) {
      return;
    }

    _updateVoiceUi(
      (current) => current.copyWith(
        isVoiceHoldActive: false,
        isCancelZoneActive: false,
        isVoiceTransitioning: true,
      ),
    );
    _pendingVoiceCancel = cancel;

    final releaseSessionId = _voiceSessionId;

    try {
      if (_speech.isListening || _isListening) {
        if (cancel) {
          await _speech.cancel();
        } else {
          await _speech.stop();
        }

        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (!mounted || releaseSessionId != _voiceSessionId) {
            return;
          }
          _maybeCompleteReleasedVoiceSession();
        });
      } else {
        _maybeCompleteReleasedVoiceSession();
      }
    } catch (_) {
      _pendingVoiceCancel = true;
      _maybeCompleteReleasedVoiceSession();
      if (!cancel) {
        _showMessage('Voice input stopped unexpectedly. Please try again.');
      }
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    if (status == stt.SpeechToText.listeningStatus) {
      _updateVoiceUi(
        (current) =>
            current.copyWith(isListening: true, isVoiceTransitioning: false),
      );
      _startVoiceBars();
      return;
    }

    if (status == stt.SpeechToText.doneStatus ||
        status == stt.SpeechToText.notListeningStatus) {
      _updateVoiceUi(
        (current) => current.copyWith(isListening: false, soundLevel: 0),
      );
      _stopVoiceBars();
      _maybeCompleteReleasedVoiceSession();
    }
  }

  void _handleSpeechError(dynamic error) {
    if (!mounted) {
      return;
    }

    final wasUserCanceled = _pendingVoiceCancel == true;
    _voiceSessionId++;
    if (wasUserCanceled) {
      _resetVoiceOverlay(clearText: true);
      return;
    }

    _pendingVoiceCancel = true;
    _resetVoiceOverlay(clearText: true);

    final errorMessage = '${error?.errorMsg ?? error}'.toLowerCase();
    final isPermissionError =
        errorMessage.contains('permission') ||
        errorMessage.contains('recognizer_disabled');

    if (isPermissionError) {
      _showMessage(
        'Microphone or speech permission is unavailable. Please check system settings.',
      );
      return;
    }

    if (error?.permanent != true) {
      _showMessage('Voice input stopped. Please try again.');
    }
  }

  Future<void> _openNewMemo() async {
    if (_isVoiceTransitioning || _isCreatingVoiceMemo || _isVoiceHoldActive) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MemoDetailScreen(isCreating: true),
      ),
    );
  }

  String _fallbackTitle(String body) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return 'Untitled Memo';
    }

    final firstLine = trimmedBody.split('\n').first.trim();
    if (firstLine.length <= 20) {
      return firstLine;
    }
    return firstLine.substring(0, 20).trimRight();
  }

  Future<void> _createMemoFromVoice(String transcript) async {
    final user = FirebaseAuth.instance.currentUser;
    final body = transcript.trim();

    if (user == null) {
      _resetVoiceOverlay(clearText: false);
      _showMessage('Please sign in to create a memo.');
      return;
    }

    if (body.isEmpty) {
      _resetVoiceOverlay(clearText: true);
      return;
    }

    if (!mounted) {
      return;
    }

    _updateVoiceUi((current) => current.copyWith(isCreatingVoiceMemo: true));

    try {
      final title = _fallbackTitle(body);
      final docRef = await FirebaseFirestore.instance.collection('memos').add({
        'userId': user.uid,
        'title': title,
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      _voiceDraftText = '';
      _updateVoiceUi((current) => current.copyWith(isCreatingVoiceMemo: false));
      _resetVoiceOverlay(clearText: true);

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              MemoDetailScreen(memoId: docRef.id, title: title, body: body),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      _updateVoiceUi((current) => current.copyWith(isCreatingVoiceMemo: false));
      _resetVoiceOverlay(clearText: false);
      _showMessage('Failed to create voice memo. Please try again.');
    }
  }

  Stream<List<MemoRecord>> _memoStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<List<MemoRecord>>.empty();
    }

    return FirebaseFirestore.instance
        .collection('memos')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final memos = snapshot.docs.map(MemoRecord.fromFirestore).toList();
          memos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return memos;
        });
  }

  List<_MemoSection> _buildSections(List<MemoRecord> memos) {
    final sections = <_MemoSection>[];
    String? currentKey;
    List<_MemoItem> currentItems = [];

    for (final memo in memos) {
      final key = _sectionKeyForDate(memo.createdAt);
      if (currentKey != key) {
        if (currentKey != null) {
          sections.add(
            _MemoSection(
              title: currentKey,
              items: List.unmodifiable(currentItems),
            ),
          );
        }
        currentKey = key;
        currentItems = [];
      }

      currentItems.add(
        _MemoItem(
          id: memo.id,
          title: memo.title,
          displayTitle: memo.displayTitle,
          dateLabel: _cardDateLabel(memo.createdAt),
          body: memo.body,
        ),
      );
    }

    if (currentKey != null) {
      sections.add(
        _MemoSection(title: currentKey, items: List.unmodifiable(currentItems)),
      );
    }

    return sections;
  }

  String _sectionKeyForDate(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final memoDay = DateTime(localDate.year, localDate.month, localDate.day);
    final difference = today.difference(memoDay).inDays;

    if (difference == 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }
    return DateFormat('yyyy.MM.dd').format(localDate);
  }

  Future<void> _confirmAndDeleteMemo(_MemoItem item) async {
    if (_deletingMemoId != null) {
      return;
    }

    final confirmed = await _showDeleteMemoDialog(item);
    if (!mounted) {
      return;
    }

    if (!confirmed) {
      setState(() {
        _deleteActionMemoId = null;
      });
      return;
    }

    setState(() {
      _deletingMemoId = item.id;
    });

    try {
      await FirebaseFirestore.instance
          .collection('memos')
          .doc(item.id)
          .delete();

      if (!mounted) {
        return;
      }

      setState(() {
        _deleteActionMemoId = null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Memo deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Failed to delete memo. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _deletingMemoId = null;
        });
      }
    }
  }

  Future<bool> _showDeleteMemoDialog(_MemoItem item) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFAC638).withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 45,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.lightBackground,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.error,
                      size: 31,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete this memo?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will permanently remove "${item.title}".',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.mutedText,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(true),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppTheme.accent, AppTheme.accentDark],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.lightBackground),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      backgroundColor: AppTheme.lightBackground,
                      foregroundColor: primaryColor,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> _openMemoDetail(_MemoItem item) async {
    if (_deleteActionMemoId == item.id) {
      setState(() {
        _deleteActionMemoId = null;
      });
      return;
    }

    if (_deleteActionMemoId != null) {
      setState(() {
        _deleteActionMemoId = null;
      });
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoDetailScreen(
          memoId: item.id,
          title: item.title,
          body: item.body,
        ),
      ),
    );

    if (!mounted || _deleteActionMemoId == null) {
      return;
    }

    setState(() {
      _deleteActionMemoId = null;
    });
  }

  String _cardDateLabel(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final memoDay = DateTime(localDate.year, localDate.month, localDate.day);
    final difference = today.difference(memoDay).inDays;

    if (difference == 0 || difference == 1) {
      return DateFormat('h:mm a').format(localDate);
    }
    return DateFormat('yyyy.MM.dd').format(localDate);
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final statusBarHeight = mediaPadding.top;
    final bottomInset = mediaPadding.bottom;
    final fabBottomOffset = bottomInset + 112;
    final contentBottomSpacing = bottomInset + 94;
    final staticBody = _buildStaticBody(
      statusBarHeight: statusBarHeight,
      contentBottomSpacing: contentBottomSpacing,
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: ValueListenableBuilder<_VoiceUiState>(
        valueListenable: _voiceUi,
        child: staticBody,
        builder: (context, voiceUi, child) {
          return Stack(
            children: [
              child!,
              SafeArea(
                bottom: false,
                child: Center(
                  child: Container(
                    width: 430,
                    constraints: const BoxConstraints(maxWidth: 430),
                    height: double.infinity,
                    color: Colors.transparent,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _buildHeader(),
                        ),
                        Positioned(
                          right: 24,
                          bottom: fabBottomOffset,
                          child: _buildFab(),
                        ),
                        if (voiceUi.isOverlayVisible)
                          Positioned.fill(child: _buildVoiceComposerOverlay()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStaticBody({
    required double statusBarHeight,
    required double contentBottomSpacing,
  }) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: statusBarHeight,
          child: const ColoredBox(color: AppTheme.headerBackground),
        ),
        SafeArea(
          bottom: false,
          child: Center(
            child: Container(
              width: 430,
              constraints: const BoxConstraints(maxWidth: 430),
              height: double.infinity,
              color: bgColor,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        const SizedBox(height: 74),
                        Expanded(child: _buildContent()),
                        SizedBox(height: contentBottomSpacing),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AppBottomNavigationBar(
                      currentIndex: _selectedNavIndex,
                      onItemTapped: (index) {
                        navigateFromBottomNav(
                          context,
                          targetIndex: index,
                          currentIndex: _selectedNavIndex,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return const AppHeader(title: 'Memos', useBlur: false);
  }

  Widget _buildContent() {
    return StreamBuilder<List<MemoRecord>>(
      stream: _memoStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Unable to load memos right now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Please sign in to view your memos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        final sections = _buildSections(snapshot.data ?? const <MemoRecord>[]);
        if (sections.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No memos yet. Tap the plus button to create one.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 128),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections
                  .map((section) => _buildSection(section))
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(_MemoSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            section.title.toUpperCase(),
            style: const TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...section.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _MemoCard(
              item: item,
              showDeleteAction: _deleteActionMemoId == item.id,
              isDeleting: _deletingMemoId == item.id,
              onLongPress: () {
                setState(() {
                  _deleteActionMemoId = item.id;
                });
              },
              onTap: () {
                _openMemoDetail(item);
              },
              onDeleteTap: () => _confirmAndDeleteMemo(item),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFab() {
    final isBusy = _isVoiceTransitioning || _isCreatingVoiceMemo;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isBusy || _isVoiceOverlayVisible ? null : _openNewMemo,
      onLongPressStart: isBusy || _isVoiceOverlayVisible
          ? null
          : (_) => _startVoiceMemoCreation(),
      onLongPressMoveUpdate: _isVoiceOverlayVisible
          ? (details) => _updateCancelZoneState(details.globalPosition)
          : null,
      onLongPressEnd: _isVoiceOverlayVisible
          ? (details) {
              _updateCancelZoneState(details.globalPosition);
              _stopVoiceMemoCreation(cancel: _isCancelZoneActive);
            }
          : null,
      onLongPressCancel: _isVoiceOverlayVisible
          ? () => _stopVoiceMemoCreation(cancel: true)
          : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        opacity: _isVoiceOverlayVisible ? 0.02 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [accentColor, secondaryAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.3),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.add_rounded, size: 34, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceComposerOverlay() {
    final releaseLabel = _isCancelZoneActive
        ? 'Release to cancel'
        : 'Release to save';
    final helperLabel = _isCancelZoneActive
        ? 'Lift your finger now to cancel this memo.'
        : 'Keep holding and slide left to cancel.';
    final rightLabel = _isVoiceTransitioning && !_isListening
        ? 'Preparing'
        : 'New Memo';

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: const Color(0xFFF8F7F6).withValues(alpha: 0.32),
              ),
            ),
          ),
          Container(color: const Color(0xFF0F172A).withValues(alpha: 0.08)),
          Align(
            alignment: const Alignment(0, -0.08),
            child: RepaintBoundary(child: _buildVoiceWaveBubble()),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              child: _buildVoiceBottomTray(
                releaseLabel: releaseLabel,
                helperLabel: helperLabel,
                rightLabel: rightLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceWaveBubble() {
    final bubbleColor = _isCancelZoneActive
        ? const Color(0xFFFDE8E6)
        : const Color(0xFFFFF1C9);
    final waveColor = _isCancelZoneActive
        ? const Color(0xFFDC2626)
        : const Color(0xFF9A6B00);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          width: 236,
          height: 128,
          decoration: BoxDecoration(
            color: bubbleColor.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: waveColor.withValues(alpha: 0.14),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: _VoiceBars(
              animation: _voiceBarsController,
              level: _soundLevel,
              color: waveColor,
            ),
          ),
        ),
        Positioned(
          bottom: -9,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: bubbleColor.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceBottomTray({
    required String releaseLabel,
    required String helperLabel,
    required String rightLabel,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 244,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -22,
            right: -22,
            bottom: 0,
            child: Container(
              height: 172,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(220),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 26,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 22,
            bottom: 118,
            child: SizedBox(
              key: _cancelVoiceZoneKey,
              width: 160,
              height: 76,
              child: Transform.rotate(
                angle: -0.24,
                child: Container(
                  width: 152,
                  height: 68,
                  decoration: BoxDecoration(
                    color: _isCancelZoneActive
                        ? const Color(0xFFFDE8E6).withValues(alpha: 0.98)
                        : const Color(0xFFF8F2E6).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _isCancelZoneActive
                          ? const Color(0xFFFCA5A5)
                          : Colors.white.withValues(alpha: 0.62),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isCancelZoneActive
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFFFAC638))
                                .withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _isCancelZoneActive
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 118,
            child: Transform.rotate(
              angle: 0.24,
              child: Container(
                width: 158,
                height: 68,
                decoration: BoxDecoration(
                  color: _isCancelZoneActive
                      ? Colors.white.withValues(alpha: 0.6)
                      : const Color(0xFFFFF3CD).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFAC638).withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    rightLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _isCancelZoneActive
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF9A6B00),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  releaseLabel,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  helperLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceUiState {
  const _VoiceUiState({
    this.isListening = false,
    this.isVoiceTransitioning = false,
    this.isVoiceHoldActive = false,
    this.isCancelZoneActive = false,
    this.isCreatingVoiceMemo = false,
    this.soundLevel = 0,
  });

  final bool isListening;
  final bool isVoiceTransitioning;
  final bool isVoiceHoldActive;
  final bool isCancelZoneActive;
  final bool isCreatingVoiceMemo;
  final double soundLevel;

  bool get isOverlayVisible {
    return isListening || isVoiceTransitioning || isVoiceHoldActive;
  }

  _VoiceUiState copyWith({
    bool? isListening,
    bool? isVoiceTransitioning,
    bool? isVoiceHoldActive,
    bool? isCancelZoneActive,
    bool? isCreatingVoiceMemo,
    double? soundLevel,
  }) {
    return _VoiceUiState(
      isListening: isListening ?? this.isListening,
      isVoiceTransitioning: isVoiceTransitioning ?? this.isVoiceTransitioning,
      isVoiceHoldActive: isVoiceHoldActive ?? this.isVoiceHoldActive,
      isCancelZoneActive: isCancelZoneActive ?? this.isCancelZoneActive,
      isCreatingVoiceMemo: isCreatingVoiceMemo ?? this.isCreatingVoiceMemo,
      soundLevel: soundLevel ?? this.soundLevel,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _VoiceUiState &&
        other.isListening == isListening &&
        other.isVoiceTransitioning == isVoiceTransitioning &&
        other.isVoiceHoldActive == isVoiceHoldActive &&
        other.isCancelZoneActive == isCancelZoneActive &&
        other.isCreatingVoiceMemo == isCreatingVoiceMemo &&
        other.soundLevel == soundLevel;
  }

  @override
  int get hashCode => Object.hash(
    isListening,
    isVoiceTransitioning,
    isVoiceHoldActive,
    isCancelZoneActive,
    isCreatingVoiceMemo,
    soundLevel,
  );
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
          mainAxisSize: MainAxisSize.min,
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

class MemoRecord {
  static const int _cardTitleLimit = _MemoScreenState._cardTitleLimit;

  const MemoRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  String get displayTitle {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isNotEmpty) {
      return _truncateForCard(trimmedTitle);
    }

    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return 'Untitled Memo';
    }

    final firstLine = trimmedBody.split('\n').first.trim();
    if (firstLine.length <= _cardTitleLimit) {
      return firstLine;
    }
    return firstLine.substring(0, _cardTitleLimit).trimRight();
  }

  static String _truncateForCard(String value) {
    if (value.length <= _cardTitleLimit) {
      return value;
    }
    return '${value.substring(0, _cardTitleLimit).trimRight()}...';
  }

  factory MemoRecord.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final timestamp = data['createdAt'];

    return MemoRecord(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      createdAt: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _MemoSection {
  final String title;
  final List<_MemoItem> items;

  const _MemoSection({required this.title, required this.items});
}

class _MemoItem {
  final String id;
  final String title;
  final String displayTitle;
  final String dateLabel;
  final String body;

  const _MemoItem({
    required this.id,
    required this.title,
    required this.displayTitle,
    required this.dateLabel,
    required this.body,
  });
}

class _MemoCard extends StatelessWidget {
  final _MemoItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDeleteTap;
  final bool showDeleteAction;
  final bool isDeleting;

  const _MemoCard({
    required this.item,
    this.onTap,
    this.onLongPress,
    this.onDeleteTap,
    this.showDeleteAction = false,
    this.isDeleting = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _MemoScreenState.borderColor),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _MemoScreenState.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                item.dateLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF64748B),
              height: 1.6,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -10,
            right: -8,
            child: AnimatedScale(
              scale: showDeleteAction ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: showDeleteAction ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !showDeleteAction || isDeleting,
                  child: GestureDetector(
                    onTap: onDeleteTap,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.error.withValues(alpha: 0.16),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.error,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                color: AppTheme.error,
                                size: 23,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
