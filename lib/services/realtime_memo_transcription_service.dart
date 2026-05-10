import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:record/record.dart';

typedef RealtimeTranscriptChanged = void Function(String transcript);
typedef RealtimeSoundLevelChanged = void Function(double level);
typedef RealtimeSessionEnded = void Function();

class RealtimeMemoTranscriptionService {
  RealtimeMemoTranscriptionService({
    FirebaseFunctions? functions,
    AudioRecorder? recorder,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'australia-southeast1'),
       _recorder = recorder ?? AudioRecorder();

  static const int sampleRate = 24000;
  static const String model = 'gpt-realtime-whisper';

  final FirebaseFunctions _functions;
  final AudioRecorder _recorder;
  WebSocket? _socket;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final Map<String, String> _partialTranscripts = <String, String>{};
  String _completedTranscript = '';
  bool _isActive = false;

  bool get isActive => _isActive;

  Future<void> start({
    required RealtimeTranscriptChanged onTranscriptChanged,
    required RealtimeSoundLevelChanged onSoundLevelChanged,
    RealtimeSessionEnded? onSessionEnded,
  }) async {
    if (_isActive) {
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const RealtimeTranscriptionException(
        'Microphone permission is unavailable.',
      );
    }

    final token = await _fetchClientSecret();
    final socket = await WebSocket.connect(
      'wss://api.openai.com/v1/realtime?intent=transcription',
      headers: <String, dynamic>{'Authorization': 'Bearer ${token.value}'},
    );
    _socket = socket;
    _isActive = true;
    _completedTranscript = '';
    _partialTranscripts.clear();

    socket.listen(
      (message) =>
          _handleServerMessage(message, onTranscriptChanged, onSessionEnded),
      onError: (_) => _markEnded(onSessionEnded),
      onDone: () => _markEnded(onSessionEnded),
      cancelOnError: false,
    );

    _sendJson(<String, dynamic>{
      'type': 'session.update',
      'session': <String, dynamic>{
        'type': 'transcription',
        'audio': <String, dynamic>{
          'input': <String, dynamic>{
            'format': <String, dynamic>{
              'type': 'audio/pcm',
              'rate': sampleRate,
            },
            'transcription': <String, dynamic>{'model': model},
          },
        },
      },
    });

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    _audioSubscription = stream.listen((chunk) {
      if (!_isActive) {
        return;
      }
      onSoundLevelChanged(_estimateLevel(chunk));
      _sendJson(<String, dynamic>{
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk),
      });
    });

    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amplitude) {
          if (!_isActive) {
            return;
          }
          onSoundLevelChanged(amplitude.current);
        });
  }

  Future<void> stop() async {
    if (!_isActive && _socket == null) {
      return;
    }

    _isActive = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _recorder.stop();
    } catch (_) {
      // Keep local UI state recoverable if the recorder has already stopped.
    }

    _sendJson(<String, dynamic>{'type': 'input_audio_buffer.commit'});
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await _closeSocket();
  }

  Future<void> cancel() async {
    _isActive = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    try {
      await _recorder.cancel();
    } catch (_) {
      // The stream recorder may already be stopped or unavailable.
    }

    await _closeSocket();
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }

  Future<_RealtimeClientSecret> _fetchClientSecret() async {
    final callable = _functions.httpsCallable(
      'createRealtimeTranscriptionClientSecret',
    );
    final result = await callable.call<Map<String, dynamic>>();
    final data = Map<String, dynamic>.from(result.data);
    final clientSecret = (data['clientSecret'] as String? ?? '').trim();
    if (clientSecret.isEmpty) {
      throw const RealtimeTranscriptionException(
        'Realtime transcription is not configured.',
      );
    }

    return _RealtimeClientSecret(value: clientSecret);
  }

  void _handleServerMessage(
    dynamic message,
    RealtimeTranscriptChanged onTranscriptChanged,
    RealtimeSessionEnded? onSessionEnded,
  ) {
    if (message is! String) {
      return;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(message);
    } catch (_) {
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final type = decoded['type'] as String? ?? '';
    if (type == 'conversation.item.input_audio_transcription.delta') {
      final itemId = decoded['item_id'] as String? ?? 'active';
      final delta = decoded['delta'] as String? ?? '';
      if (delta.isNotEmpty) {
        _partialTranscripts[itemId] =
            '${_partialTranscripts[itemId] ?? ''}$delta';
        onTranscriptChanged(_currentTranscript);
      }
      return;
    }

    if (type == 'conversation.item.input_audio_transcription.completed') {
      final itemId = decoded['item_id'] as String? ?? 'active';
      final transcript = (decoded['transcript'] as String? ?? '').trim();
      _partialTranscripts.remove(itemId);
      if (transcript.isNotEmpty) {
        _completedTranscript = _joinTranscript(
          _completedTranscript,
          transcript,
        );
      }
      onTranscriptChanged(_currentTranscript);
      return;
    }

    if (type == 'error') {
      _markEnded(onSessionEnded);
    }
  }

  String get _currentTranscript {
    final partial = _partialTranscripts.values.join(' ').trim();
    return _joinTranscript(_completedTranscript, partial);
  }

  String _joinTranscript(String first, String second) {
    final left = first.trim();
    final right = second.trim();
    if (left.isEmpty) {
      return right;
    }
    if (right.isEmpty) {
      return left;
    }
    return '$left $right';
  }

  double _estimateLevel(Uint8List chunk) {
    if (chunk.length < 2) {
      return 0;
    }

    var totalSquares = 0.0;
    var samples = 0;
    for (var index = 0; index + 1 < chunk.length; index += 2) {
      var sample = chunk[index] | (chunk[index + 1] << 8);
      if (sample >= 0x8000) {
        sample -= 0x10000;
      }
      final normalized = sample / 32768.0;
      totalSquares += normalized * normalized;
      samples++;
    }

    if (samples == 0) {
      return 0;
    }

    final rms = math.sqrt(totalSquares / samples);
    return (rms * 18 - 2).clamp(0.0, 10.0).toDouble();
  }

  void _sendJson(Map<String, dynamic> event) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return;
    }
    socket.add(jsonEncode(event));
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }

    try {
      await socket.close();
    } catch (_) {
      // Nothing else to clean up locally.
    }
  }

  void _markEnded(RealtimeSessionEnded? onSessionEnded) {
    if (!_isActive) {
      return;
    }

    _isActive = false;
    onSessionEnded?.call();
  }
}

class RealtimeTranscriptionException implements Exception {
  const RealtimeTranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _RealtimeClientSecret {
  const _RealtimeClientSecret({required this.value});

  final String value;
}
