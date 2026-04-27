import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:just_audio/just_audio.dart';

import '../themes/app_theme.dart';

class RecordedVoiceMemoDetailScreen extends StatefulWidget {
  const RecordedVoiceMemoDetailScreen({
    super.key,
    required this.memoId,
    required this.title,
    required this.body,
    required this.audioUrl,
    required this.localAudioPath,
    required this.audioStoragePath,
    required this.duration,
    required this.createdAt,
  });

  final String memoId;
  final String title;
  final String body;
  final String audioUrl;
  final String localAudioPath;
  final String audioStoragePath;
  final Duration duration;
  final DateTime createdAt;

  @override
  State<RecordedVoiceMemoDetailScreen> createState() =>
      _RecordedVoiceMemoDetailScreenState();
}

class _RecordedVoiceMemoDetailScreenState
    extends State<RecordedVoiceMemoDetailScreen> {
  static const _background = AppTheme.pageBackground;
  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFFFAC638);
  static const _voiceTint = Color(0xFFFFF8E3);
  static const int _maxTitleLength = 30;

  late final AudioPlayer _player;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _bodyFocusNode;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _autosaveTimer;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoadingAudio = true;
  bool _isPlaying = false;
  bool _isSaving = false;
  late String _originalTitle;
  late String _originalBody;
  String? _audioError;

  bool get _hasChanges {
    return _titleController.text.trim() != _originalTitle.trim() ||
        _bodyController.text.trim() != _originalBody.trim();
  }

  @override
  void initState() {
    super.initState();
    _duration = widget.duration;
    _player = AudioPlayer();
    _originalTitle = _isUnsetTitle(widget.title)
        ? _autoTitle(widget.createdAt)
        : widget.title;
    _originalBody = widget.body;
    _titleController = TextEditingController(text: _originalTitle)
      ..addListener(_scheduleAutosave);
    _bodyController = TextEditingController(text: _originalBody)
      ..addListener(_scheduleAutosave);
    _titleFocusNode = FocusNode();
    _bodyFocusNode = FocusNode();
    _bindPlayer();
    _loadAudio();
  }

  void _bindPlayer() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
        }
      });
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (!mounted || duration == null) {
        return;
      }
      setState(() {
        _duration = duration;
      });
    });
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
      });
    });
  }

  Future<void> _loadAudio() async {
    try {
      if (widget.localAudioPath.isNotEmpty &&
          File(widget.localAudioPath).existsSync()) {
        await _player.setFilePath(widget.localAudioPath);
      } else if (widget.audioUrl.isNotEmpty) {
        await _player.setUrl(widget.audioUrl);
      } else {
        throw StateError('Missing audio source.');
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAudio = false;
        _audioError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingAudio = false;
        _audioError = 'Audio is unavailable on this device.';
      });
    }
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (_isSaving || !_hasChanges) {
      return;
    }
    _autosaveTimer = Timer(const Duration(milliseconds: 700), _flushAutosave);
  }

  Future<void> _flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (_isSaving || !_hasChanges) {
      return;
    }
    await _saveMemo(showMessage: false);
  }

  Future<void> _saveMemo({required bool showMessage}) async {
    final title = _titleController.text.trim().isEmpty
        ? _autoTitle(widget.createdAt)
        : _titleController.text.trim();
    final body = _bodyController.text.trim();

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('memos')
          .doc(widget.memoId)
          .update({
            'title': title,
            'body': body,
            'memoType': 'voice',
            'audioUrl': widget.audioUrl,
            'audioStoragePath': widget.audioStoragePath,
            'localAudioPath': widget.localAudioPath,
            'audioDurationMillis': _duration.inMilliseconds,
            'createdAtLocalMillis': widget.createdAt.millisecondsSinceEpoch,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      _originalTitle = title;
      _originalBody = body;

      if (showMessage) {
        _showMessage('Voice memo saved.');
      }
    } catch (_) {
      _showMessage('Failed to save voice memo. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _handleBackNavigation() async {
    FocusScope.of(context).unfocus();
    await _player.pause();
    await _flushAutosave();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
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

  Future<void> _togglePlayback() async {
    if (_isLoadingAudio || _audioError != null) {
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    if (_duration > Duration.zero && _position >= _duration) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  Future<void> _seekRelative(Duration offset) async {
    if (_isLoadingAudio || _audioError != null) {
      return;
    }
    final duration = _duration > Duration.zero ? _duration : widget.duration;
    final nextMillis = (_position + offset).inMilliseconds
        .clamp(0, math.max(duration.inMilliseconds, 0))
        .toInt();
    await _player.seek(Duration(milliseconds: nextMillis));
  }

  Future<void> _seekToFraction(double fraction) async {
    if (_duration <= Duration.zero) {
      return;
    }
    await _player.seek(
      Duration(milliseconds: (_duration.inMilliseconds * fraction).round()),
    );
  }

  void _dismissKeyboard() {
    final focus = FocusScope.of(context);
    if (!focus.hasPrimaryFocus && focus.focusedChild != null) {
      focus.unfocus();
    }
  }

  String _autoTitle(DateTime createdAt) {
    return '${intl.DateFormat('d MMMM yyyy').format(createdAt.toLocal())} recording';
  }

  bool _isUnsetTitle(String title) {
    final normalized = title.trim();
    return normalized.isEmpty || normalized == 'Voice Memo';
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _player.dispose();
    _titleFocusNode.dispose();
    _bodyFocusNode.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: Scaffold(
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
                    child: Column(
                      children: [
                        _buildAppBar(context),
                        Expanded(child: _buildContent(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
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
          AppTheme.backButton(context, onPressed: _handleBackNavigation),
          const Expanded(
            child: Center(
              child: Text(
                'Voice Memo',
                style: TextStyle(
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
                : () async {
                    await _saveMemo(showMessage: true);
                    if (mounted) {
                      await _handleBackNavigation();
                    }
                  },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFFE3A3)),
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accentColor,
                        ),
                      )
                    : const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF9A6B00),
                        size: 23,
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
      padding: EdgeInsets.fromLTRB(
        24,
        28,
        24,
        math.max(32, keyboardInset + 28),
      ),
      child: Column(
        children: [
          _buildPlayerCard(),
          const SizedBox(height: 18),
          _buildNotesCard(context),
        ],
      ),
    );
  }

  Widget _buildPlayerCard() {
    final duration = _duration > Duration.zero ? _duration : widget.duration;
    final durationMillis = math.max(duration.inMilliseconds, 1);
    final positionMillis = _position.inMilliseconds
        .clamp(0, durationMillis)
        .toDouble();
    final progress = positionMillis / durationMillis;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: _voiceTint,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x33E2B736)),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            maxLength: _maxTitleLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxTitleLength),
            ],
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: 'Voice memo title',
              border: InputBorder.none,
              isCollapsed: true,
              counterText: '',
            ),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _primaryColor,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatClock(widget.createdAt)}  ${_formatDuration(duration)}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 34),
          SizedBox(
            height: 190,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final waveformWidth = math.max(constraints.maxWidth, 1.0);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final fraction = (details.localPosition.dx / waveformWidth)
                        .clamp(0.0, 1.0);
                    _seekToFraction(fraction);
                  },
                  onTapDown: (details) {
                    final fraction = (details.localPosition.dx / waveformWidth)
                        .clamp(0.0, 1.0);
                    _seekToFraction(fraction);
                  },
                  child: CustomPaint(
                    painter: _VoiceWaveformPainter(
                      progress: progress,
                      activeColor: const Color(0xFF2563EB),
                      inactiveColor: const Color(0xFF9CA3AF),
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          Text(
            _formatPreciseDuration(_position),
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 24),
          if (_audioError != null)
            Text(
              _audioError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.error,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundPlayerButton(
                  icon: Icons.replay_10_rounded,
                  onTap: () => _seekRelative(const Duration(seconds: -15)),
                  isPrimary: false,
                ),
                const SizedBox(width: 24),
                _RoundPlayerButton(
                  icon: _isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: _togglePlayback,
                  isPrimary: true,
                  isBusy: _isLoadingAudio,
                ),
                const SizedBox(width: 24),
                _RoundPlayerButton(
                  icon: Icons.forward_10_rounded,
                  onTap: () => _seekRelative(const Duration(seconds: 15)),
                  isPrimary: false,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _bodyController,
        focusNode: _bodyFocusNode,
        keyboardType: TextInputType.multiline,
        minLines: 5,
        maxLines: 9,
        onTapOutside: (_) => _dismissKeyboard(),
        decoration: const InputDecoration(
          hintText: 'Write notes for this voice memo...',
          border: InputBorder.none,
          isCollapsed: true,
        ),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Color(0xFF334155),
          height: 1.6,
        ),
      ),
    );
  }

  String _formatClock(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatPreciseDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final centiseconds = (duration.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds.$centiseconds';
  }
}

class _RoundPlayerButton extends StatelessWidget {
  const _RoundPlayerButton({
    required this.icon,
    required this.onTap,
    required this.isPrimary,
    this.isBusy = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Container(
        width: isPrimary ? 62 : 48,
        height: isPrimary ? 62 : 48,
        decoration: BoxDecoration(
          color: isPrimary ? _RecordedVoiceMemoColors.primary : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isPrimary ? 0.14 : 0.06),
              blurRadius: isPrimary ? 18 : 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: isBusy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  icon,
                  color: isPrimary ? Colors.white : const Color(0xFF111827),
                  size: isPrimary ? 34 : 26,
                ),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * 0.48;
    final barCount = 42;
    final spacing = size.width / barCount;
    final progressX = size.width * progress.clamp(0, 1);

    for (var index = 0; index < barCount; index++) {
      final phase = index * 0.72;
      final wave = (math.sin(phase) * 0.5 + math.sin(phase * 1.7) * 0.5).abs();
      final height = 14 + wave * 38;
      final x = spacing * index + spacing * 0.5;
      final paint = Paint()
        ..color = x <= progressX ? activeColor : inactiveColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }

    final progressPaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(progressX, 10),
      Offset(progressX, size.height - 18),
      progressPaint,
    );
    canvas.drawCircle(Offset(progressX, 10), 5, Paint()..color = activeColor);
    canvas.drawCircle(
      Offset(progressX, size.height - 18),
      5,
      Paint()..color = activeColor,
    );

    final labelStyle = TextStyle(
      color: inactiveColor.withValues(alpha: 0.8),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    _paintLabel(canvas, Offset(0, size.height - 4), '0:00', labelStyle);
  }

  void _paintLabel(Canvas canvas, Offset offset, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class _RecordedVoiceMemoColors {
  static const primary = Color(0xFF111827);
}
