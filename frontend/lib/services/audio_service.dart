import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'api_service.dart';

class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordedPath;

  // Exposed so a voice-message bubble can show a live seek bar/duration.
  Stream<Duration> get onDurationChanged => _audioPlayer.onDurationChanged;
  Stream<Duration> get onPositionChanged => _audioPlayer.onPositionChanged;
  Stream<void> get onPlayerComplete => _audioPlayer.onPlayerComplete;

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      _recordedPath = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _recordedPath!,
      );
    }
  }

  Future<String?> stopRecording() async {
    final path = await _audioRecorder.stop();
    return path ?? _recordedPath;
  }

  // "Remote" means an absolute http(s) URL (legacy rows) or a server-relative
  // upload path like '/uploads/xyz.m4a' (what's stored today); anything else is
  // a local, not-yet-uploaded file path.
  bool _isRemote(String urlOrPath) =>
      urlOrPath.startsWith('http://') ||
      urlOrPath.startsWith('https://') ||
      urlOrPath.startsWith('/uploads/');

  // Loads a voice message's audio without starting playback, so its total
  // duration can be shown (via onDurationChanged) before the user taps play.
  Future<void> preload(String urlOrPath) async {
    if (_isRemote(urlOrPath)) {
      await _audioPlayer.setSourceUrl(ApiService.mediaUrl(urlOrPath));
    } else {
      await _audioPlayer.setSourceDeviceFile(urlOrPath);
    }
  }

  // Voice messages store a server-relative path like '/uploads/xyz.m4a', not a full URL.
  Future<void> playAudio(String urlOrPath) async {
    if (_isRemote(urlOrPath)) {
      await _audioPlayer.play(UrlSource(ApiService.mediaUrl(urlOrPath)));
    } else {
      await _audioPlayer.play(DeviceFileSource(urlOrPath));
    }
  }

  Future<void> pauseAudio() async {
    await _audioPlayer.pause();
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  // Must be called by the owning widget's dispose(), otherwise the native
  // recorder/player session leaks for the app's lifetime.
  Future<void> dispose() async {
    await _audioRecorder.dispose();
    await _audioPlayer.dispose();
  }
}