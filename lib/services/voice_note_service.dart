import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Voice note recording and encoding service.
///
/// Matches iOS/Android behavior:
/// - AAC codec (M4A container)
/// - 16 kHz sample rate, mono
/// - 16–20 kbps bitrate (~2.5 KB/sec)
/// - Max 120 seconds recording
class VoiceNoteService {
  VoiceNoteService();

  final AudioRecorder _recorder = AudioRecorder();

  /// Max recording duration (matches iOS maxRecordingDuration).
  static const Duration maxDuration = Duration(seconds: 120);

  /// Whether a recording is currently in progress.
  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Current output file path.
  String? _currentPath;

  /// Recording start time for duration tracking.
  DateTime? _startTime;

  /// Stream of amplitude values (0.0–1.0) for waveform visualization.
  final _amplitudeController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Timer? _amplitudeTimer;
  Timer? _maxDurationTimer;

  /// Check if recording permission is granted.
  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  /// Start recording a voice note. Returns the output file path.
  Future<String?> startRecording() async {
    if (_isRecording) return null;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return null;

    try {
      // Create output directory
      final dir = Directory(p.join(Directory.systemTemp.path, 'bitchat_voice'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final filePath = p.join(dir.path, 'voice_$timestamp.m4a');

      // Configure to match iOS/Android: AAC, 16kHz, mono, 16kbps
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 16000,
        ),
        path: filePath,
      );

      _isRecording = true;
      _currentPath = filePath;
      _startTime = DateTime.now();

      // Start amplitude polling (50ms interval for smooth waveform)
      _amplitudeTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _pollAmplitude(),
      );

      // Auto-stop after max duration
      _maxDurationTimer = Timer(maxDuration, () {
        stopRecording();
      });

      return filePath;
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  /// Stop recording and return the voice note payload.
  Future<VoiceNotePayload?> stopRecording() async {
    if (!_isRecording) return null;

    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null || _currentPath == null) return null;

      final file = File(path);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      final base64Data = base64Encode(bytes);
      final duration = _startTime != null
          ? DateTime.now().difference(_startTime!).inMilliseconds / 1000.0
          : 0.0;

      return VoiceNotePayload(
        base64Data: base64Data,
        durationSeconds: duration,
        sizeBytes: bytes.length,
        filePath: path,
      );
    } catch (e) {
      _isRecording = false;
      return null;
    }
  }

  /// Cancel recording and delete the file.
  Future<void> cancelRecording() async {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    try {
      await _recorder.stop();
      if (_currentPath != null) {
        final file = File(_currentPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    } catch (_) {}

    _isRecording = false;
    _currentPath = null;
    _startTime = null;
  }

  /// Get recording duration so far.
  Duration get currentDuration {
    if (_startTime == null || !_isRecording) return Duration.zero;
    return DateTime.now().difference(_startTime!);
  }

  void _pollAmplitude() async {
    if (!_isRecording) return;
    try {
      final amp = await _recorder.getAmplitude();
      // Normalize: dBFS ranges from -160 (silence) to 0 (max).
      // Map to 0.0–1.0 for UI.
      final normalized = ((amp.current + 50) / 50).clamp(0.0, 1.0);
      _amplitudeController.add(normalized);
    } catch (_) {}
  }

  /// Decode a base64-encoded voice note to bytes for playback.
  static Uint8List? decodeBase64Audio(String base64String) {
    try {
      return base64Decode(base64String);
    } catch (_) {
      return null;
    }
  }

  /// Write base64 audio data to a temp file for playback.
  static Future<String?> writeToTempFile(String base64Data) async {
    try {
      final bytes = base64Decode(base64Data);
      final dir = Directory(
        p.join(Directory.systemTemp.path, 'bitchat_voice', 'incoming'),
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final filePath = p.join(
        dir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await File(filePath).writeAsBytes(bytes);
      return filePath;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _amplitudeTimer?.cancel();
    _maxDurationTimer?.cancel();
    _amplitudeController.close();
    _recorder.dispose();
  }
}

/// Payload for a recorded voice note ready for transmission.
class VoiceNotePayload {
  const VoiceNotePayload({
    required this.base64Data,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.filePath,
  });

  /// Base64-encoded M4A audio data.
  final String base64Data;

  /// Duration in seconds.
  final double durationSeconds;

  /// File size in bytes.
  final int sizeBytes;

  /// Local file path for playback.
  final String filePath;
}
