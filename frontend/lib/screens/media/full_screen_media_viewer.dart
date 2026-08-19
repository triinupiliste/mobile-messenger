import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../services/api_service.dart';
import '../../services/media_save_service.dart';
import '../../utils/snackbar_helper.dart';

/// Full-screen overlay for viewing a sent or received photo/video at full
/// size. Images support pinch-to-zoom; videos play inline with basic
/// controls. Either can be saved to the device's photo gallery.
class FullScreenMediaViewer extends StatefulWidget {
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'

  const FullScreenMediaViewer({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
  });

  static Route<void> route({required String mediaUrl, required String mediaType}) {
    return PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: FullScreenMediaViewer(mediaUrl: mediaUrl, mediaType: mediaType),
      ),
    );
  }

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  bool _isSaving = false;

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final result = await MediaSaveService.saveNetworkMedia(
      url: widget.mediaUrl,
      mediaType: widget.mediaType,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    final message = switch (result) {
      MediaSaveResult.saved =>
        '${widget.mediaType == 'video' ? 'Video' : 'Photo'} saved to gallery',
      MediaSaveResult.permissionDenied => 'Permission to access the gallery was denied',
      MediaSaveResult.failed => 'Failed to save. Please try again.',
    };
    SnackBarHelper.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: widget.mediaType == 'video'
                ? _FullScreenVideoPlayer(url: widget.mediaUrl)
                : InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: CachedNetworkImage(
                      imageUrl: ApiService.mediaUrl(widget.mediaUrl),
                      fit: BoxFit.contain,
                      fadeInDuration: const Duration(milliseconds: 200),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64,
                      ),
                      progressIndicatorBuilder: (context, url, progress) => Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          value: progress.progress,
                        ),
                      ),
                    ),
                  ),
          ),
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                _isSaving
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_rounded, color: Colors.white, size: 28),
                        tooltip: 'Save to gallery',
                        onPressed: _handleSave,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenVideoPlayer extends StatefulWidget {
  final String url;

  const _FullScreenVideoPlayer({required this.url});

  @override
  State<_FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<_FullScreenVideoPlayer> {
  late final VideoPlayerController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // Without this header, ngrok returns its HTML interstitial page instead of video bytes.
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(ApiService.mediaUrl(widget.url)),
      httpHeaders: ApiService.ngrokHeader,
    )
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      }).catchError((_) {
        if (mounted) setState(() => _hasError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Icon(Icons.broken_image, color: Colors.white54, size: 64);
    }

    if (!_controller.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: GestureDetector(
        onTap: _togglePlayback,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            if (!_controller.value.isPlaying)
              Container(
                decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                padding: const EdgeInsets.all(8),
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
