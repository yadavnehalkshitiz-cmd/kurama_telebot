import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_file_type.dart';
import '../widgets/audio_player_surface.dart';

class PlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String format;
  final String? artist;
  final String? artworkUrl;

  const PlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.format = 'video',
    this.artist,
    this.artworkUrl,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Object? _error;
  bool _checkingFile = true;
  double _dragStartVolume = 1;
  String? _gestureLabel;
  Timer? _gestureTimer;

  MediaFileType get _mediaType => classifyMediaFile(
        format: widget.format,
        path: widget.filePath,
      );

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final file = File(widget.filePath);
    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _error = const FileSystemException('File not found');
          _checkingFile = false;
        });
      }
      return;
    }

    if (_mediaType != MediaFileType.video) {
      if (mounted) setState(() => _checkingFile = false);
      return;
    }

    try {
      final video = VideoPlayerController.file(file);
      await video.initialize();
      final chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: true,
        looping: false,
        aspectRatio: video.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFFF5722),
          handleColor: const Color(0xFFFF9100),
          bufferedColor: Colors.white24,
          backgroundColor: Colors.black26,
        ),
      );
      if (!mounted) {
        chewie.dispose();
        await video.dispose();
        return;
      }
      setState(() {
        _videoController = video;
        _chewieController = chewie;
        _checkingFile = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _checkingFile = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _gestureTimer?.cancel();
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_checkingFile) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF5722)),
      );
    }
    if (_error != null) {
      return const _PlayerError();
    }
    if (_mediaType == MediaFileType.audio) {
      return AudioPlayerSurface(
        filePath: widget.filePath,
        title: widget.title,
        artist: widget.artist,
        artworkUrl: widget.artworkUrl,
      );
    }
    if (_mediaType == MediaFileType.other) {
      return const _PlayerError(message: 'This file type cannot be played');
    }

    final chewie = _chewieController;
    if (chewie == null) return const _PlayerError();
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) {
          final seconds = details.localPosition.dx < constraints.maxWidth / 2
              ? -10
              : 10;
          _seekVideo(seconds);
        },
        onVerticalDragStart: (_) {
          _dragStartVolume = _videoController?.value.volume ?? 1;
        },
        onVerticalDragUpdate: (details) {
          final next = (_dragStartVolume -
                  details.primaryDelta! / constraints.maxHeight)
              .clamp(0.0, 1.0);
          _videoController?.setVolume(next);
          _showGesture('Volume ${(next * 100).round()}%');
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(child: Chewie(controller: chewie)),
            if (_gestureLabel != null)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Text(
                      _gestureLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _seekVideo(int seconds) async {
    final video = _videoController;
    if (video == null) return;
    final duration = video.value.duration;
    final proposed = video.value.position + Duration(seconds: seconds);
    final target = proposed < Duration.zero
        ? Duration.zero
        : proposed > duration
            ? duration
            : proposed;
    await video.seekTo(target);
    _showGesture(seconds < 0 ? '10 seconds back' : '10 seconds forward');
  }

  void _showGesture(String label) {
    if (!mounted) return;
    _gestureTimer?.cancel();
    setState(() => _gestureLabel = label);
    _gestureTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _gestureLabel = null);
    });
  }
}

class _PlayerError extends StatelessWidget {
  final String message;

  const _PlayerError({this.message = 'Could not play this media file'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: Color(0xFFE53935),
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
