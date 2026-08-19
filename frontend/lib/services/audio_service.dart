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

  // Start recording voice note
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

  // Stop recording and return file path
  Future<String?> stopRecording() async {
    final path = await _audioRecorder.stop();
    return path ?? _recordedPath;
  }

  // A path/URL is "remote" if it's an already-absolute http(s) URL (legacy
  // rows, see ApiService.mediaUrl's doc comment) or one of our own
  // server-relative upload paths (e.g. '/uploads/xyz.m4a', what every voice
  // message saved today actually stores). Anything else is a local device
  // filesystem path (e.g. a just-recorded, not-yet-uploaded file).
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

  // Play audio message. Previously this only resolved the playable server
  // URL (host + auth token, see ApiService.mediaUrl) when the raw value
  // already started with "http" — but every voice message actually stores a
  // server-relative path like '/uploads/xyz.m4a', so that check always
  // failed and this silently fell through to treating the string as a local
  // file path that doesn't exist, playing nothing.
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

  // Releases the underlying recorder/player native resources. Must be called
  // by whichever widget owns this instance (from its own dispose()) once the
  // instance is no longer needed, otherwise the native recorder/player
  // session is leaked for the lifetime of the app.
  Future<void> dispose() async {
    await _audioRecorder.dispose();
    await _audioPlayer.dispose();
  }
}