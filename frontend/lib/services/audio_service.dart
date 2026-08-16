import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'api_service.dart';

class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordedPath;

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

  // Play audio message
  Future<void> playAudio(String urlOrPath) async {
    if (urlOrPath.startsWith('http')) {
      await _audioPlayer.play(UrlSource(ApiService.mediaUrl(urlOrPath)));
    } else {
      await _audioPlayer.play(DeviceFileSource(urlOrPath));
    }
  }

  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }
}