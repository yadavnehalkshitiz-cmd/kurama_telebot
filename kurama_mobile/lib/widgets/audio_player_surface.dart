import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class AudioPlayerSurface extends StatefulWidget {
  final String filePath;
  final String title;
  final String? artist;
  final String? artworkUrl;

  const AudioPlayerSurface({
    super.key,
    required this.filePath,
    required this.title,
    this.artist,
    this.artworkUrl,
  });

  @override
  State<AudioPlayerSurface> createState() => _AudioPlayerSurfaceState();
}

class _AudioPlayerSurfaceState extends State<AudioPlayerSurface> {
  late final AudioPlayer _player;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.setAudioSource(
        AudioSource.file(
          widget.filePath,
          tag: MediaItem(
            id: widget.filePath,
            title: widget.title,
            artist: widget.artist ?? 'KuramaBot',
            artUri: widget.artworkUrl == null
                ? null
                : Uri.tryParse(widget.artworkUrl!),
          ),
        ),
      );
      await _player.play();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return const _PlayerMessage(
        icon: Icons.error_outline_rounded,
        title: 'Could not play this audio file',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 176,
            height: 176,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF7A3D), Color(0xFF5A1B12)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55FF5722),
                  blurRadius: 42,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: 76,
            ),
          ),
          const SizedBox(height: 30),
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.artist ?? 'KuramaBot audio',
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 26),
          StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (context, durationSnapshot) {
              final duration = durationSnapshot.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  final maximum = math.max(1, duration.inMilliseconds);
                  final value = math.min(position.inMilliseconds, maximum);
                  return Column(
                    children: [
                      Slider(
                        value: value.toDouble(),
                        max: maximum.toDouble(),
                        onChanged: (milliseconds) => _player.seek(
                          Duration(milliseconds: milliseconds.round()),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(position)),
                          Text(_formatDuration(duration)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 18),
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              if (state?.processingState == ProcessingState.loading ||
                  state?.processingState == ProcessingState.buffering) {
                return const SizedBox.square(
                  dimension: 64,
                  child: CircularProgressIndicator(),
                );
              }
              final playing = state?.playing ?? false;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: () => _seekRelative(-10),
                    icon: const Icon(Icons.replay_10_rounded),
                    tooltip: 'Back 10 seconds',
                  ),
                  const SizedBox(width: 20),
                  IconButton.filled(
                    iconSize: 42,
                    onPressed: playing ? _player.pause : _player.play,
                    icon: Icon(
                      playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    tooltip: playing ? 'Pause' : 'Play',
                  ),
                  const SizedBox(width: 20),
                  IconButton.filledTonal(
                    onPressed: () => _seekRelative(10),
                    icon: const Icon(Icons.forward_10_rounded),
                    tooltip: 'Forward 10 seconds',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Playback continues with the screen locked',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _seekRelative(int seconds) async {
    final target = _player.position + Duration(seconds: seconds);
    final duration = _player.duration;
    final bounded = target < Duration.zero
        ? Duration.zero
        : duration != null && target > duration
            ? duration
            : target;
    await _player.seek(bounded);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PlayerMessage extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlayerMessage({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: const Color(0xFFE53935)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
