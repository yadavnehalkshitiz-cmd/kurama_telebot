import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_file_type.dart';
import '../models/playback_entry.dart';
import '../services/playback_position_store.dart';
import '../widgets/audio_player_surface.dart';

class PlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String format;
  final String? artist;
  final String? artworkUrl;

  /// Optional queue: when provided, prev/next controls appear and playback
  /// moves through [entries]. [initialIndex] picks the starting item.
  final List<PlaybackEntry>? entries;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.format = 'video',
    this.artist,
    this.artworkUrl,
    this.entries,
    this.initialIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Object? _error;
  bool _checkingFile = true;
  double _dragStartVolume = 1;
  _GestureFeedback? _gesture;
  Timer? _gestureTimer;
  Timer? _positionTimer;
  bool _reduceMotion = false;
  double _speed = 1.0;
  late int _index;

  /// Resolve the queue (or a single implicit entry for old callers).
  List<PlaybackEntry> get _entries {
    final entries = widget.entries;
    if (entries != null && entries.isNotEmpty) return entries;
    return [
      PlaybackEntry(
        path: widget.filePath,
        title: widget.title,
        format: widget.format,
        artist: widget.artist,
        artworkUrl: widget.artworkUrl,
      ),
    ];
  }

  PlaybackEntry get _current => _entries[_index.clamp(0, _entries.length - 1)];
  bool get _hasQueue => _entries.length > 1;

  MediaFileType get _mediaType =>
      classifyMediaFile(format: _current.format, path: _current.path);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _entries.length - 1);
    _initialize();
    // Persist the video position every few seconds so reopening resumes.
    _positionTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
  }

  Future<void> _initialize() async {
    // Tear down any previous controller (queue navigation between files,
    // including mixed video/audio queues where the video branch is skipped).
    _chewieController?.dispose();
    _videoController?.dispose();
    _chewieController = null;
    _videoController = null;

    final file = File(_current.path);
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
      final saved = await PlaybackPositionStore.load(_current.path);
      if (saved > Duration.zero &&
          (video.value.duration == Duration.zero ||
              saved < video.value.duration)) {
        await video.seekTo(saved);
      }
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
    _positionTimer?.cancel();
    _gestureTimer?.cancel();
    _savePosition(); // final best-effort save
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _savePosition() async {
    final video = _videoController;
    if (video != null && video.value.isInitialized) {
      await PlaybackPositionStore.save(_current.path, video.value.position);
    }
  }

  /// Move within the queue (previous/next).
  Future<void> _goTo(int delta) async {
    final next = _index + delta;
    if (next < 0 || next >= _entries.length) return;
    await _savePosition();
    if (!mounted) return;
    setState(() {
      _index = next;
      _checkingFile = true;
      _error = null;
    });
    _initialize();
  }

  void _cycleSpeed() {
    final idx = _speedOptions.indexOf(_speed);
    _speed = _speedOptions[(idx + 1) % _speedOptions.length];
    _videoController?.setPlaybackSpeed(_speed);
    if (mounted) setState(() {});
    final label = _speed == _speed.roundToDouble()
        ? '${_speed.toInt()}×'
        : '${_speed.toStringAsFixed(2)}×'.replaceAll('.00', '');
    _showGesture(icon: Icons.speed_rounded, label: 'Speed $label');
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _current.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_hasQueue && _mediaType == MediaFileType.video) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '${_index + 1}/${_entries.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: _index > 0 ? () => _goTo(-1) : null,
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: _index < _entries.length - 1 ? () => _goTo(1) : null,
            ),
          ],
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AmbientBackdrop(),
          // Top scrim so the header stays legible over bright video
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 130,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC0A0A0E), Color(0x000A0A0E)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(child: _buildBody()),
        ],
      ),
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
        // Rebuild per file so queue navigation restarts cleanly.
        key: ValueKey(_current.path),
        filePath: _current.path,
        title: _current.title,
        artist: _current.artist,
        artworkUrl: _current.artworkUrl,
        onPrev: _hasQueue && _index > 0 ? () => _goTo(-1) : null,
        onNext: _hasQueue && _index < _entries.length - 1
            ? () => _goTo(1)
            : null,
        queueLabel: _hasQueue ? '${_index + 1}/${_entries.length}' : null,
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
          _showGesture(
            icon: Icons.volume_up_rounded,
            label: 'Volume ${(next * 100).round()}%',
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Cinematic rounded frame
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Chewie(controller: chewie),
                ),
              ),
            ),
            // Playback speed chip
            Positioned(
              top: 10,
              right: 28,
              child: GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded,
                          size: 14, color: Color(0xFFFF8A65)),
                      const SizedBox(width: 5),
                      Text(
                        _speed == _speed.roundToDouble()
                            ? '${_speed.toInt()}×'
                            : '${_speed.toStringAsFixed(2)}×',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_gesture != null)
              IgnorePointer(
                child: AnimatedSwitcher(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: _GesturePill(
                    key: ValueKey(_gesture!.label),
                    feedback: _gesture!,
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
    _showGesture(
      icon: seconds < 0
          ? Icons.fast_rewind_rounded
          : Icons.fast_forward_rounded,
      label: seconds < 0 ? '10 seconds back' : '10 seconds forward',
    );
  }

  void _showGesture({required IconData icon, required String label}) {
    if (!mounted) return;
    _gestureTimer?.cancel();
    setState(() => _gesture = _GestureFeedback(icon: icon, label: label));
    _gestureTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _gesture = null);
    });
  }
}

// ── Ambient obsidian backdrop ───────────────────────────────

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.45),
          radius: 1.25,
          colors: [Color(0xFF331810), Color(0xFF0A0A0E)],
          stops: [0.0, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

// ── Gesture feedback ────────────────────────────────────────

class _GestureFeedback {
  final IconData icon;
  final String label;

  const _GestureFeedback({required this.icon, required this.label});
}

class _GesturePill extends StatelessWidget {
  final _GestureFeedback feedback;

  const _GesturePill({super.key, required this.feedback});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(feedback.icon, size: 18, color: const Color(0xFFFF8A65)),
            const SizedBox(width: 8),
            Text(
              feedback.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error ───────────────────────────────────────────────────

class _PlayerError extends StatelessWidget {
  final String message;

  const _PlayerError({this.message = 'Could not play this media file'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF5722).withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: Color(0xFFFF8A65),
            ),
          ),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
