import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../services/playback_position_store.dart';

const _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
const _sleepOptions = [
  (Duration(minutes: 5), '5 min'),
  (Duration(minutes: 10), '10 min'),
  (Duration(minutes: 15), '15 min'),
  (Duration(minutes: 30), '30 min'),
  (Duration(minutes: 60), '60 min'),
];

String _speedLabel(double speed) {
  return switch (speed) {
    0.5 => '0.5×',
    0.75 => '0.75×',
    1.0 => '1×',
    1.25 => '1.25×',
    1.5 => '1.5×',
    2.0 => '2×',
    _ => '${speed.toStringAsFixed(1)}×',
  };
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

Future<void> _seekRelative(AudioPlayer player, int seconds) async {
  final target = player.position + Duration(seconds: seconds);
  final duration = player.duration;
  final bounded = target < Duration.zero
      ? Duration.zero
      : duration != null && target > duration
          ? duration
          : target;
  await player.seek(bounded);
}

/// Rich full-screen audio playback surface.
///
/// Obsidian backdrop with fox-amber accents and the signature amber "media
/// rail" seek bar. Playback continues with the screen locked via
/// `just_audio_background`. Supports queue navigation, per-file position
/// resume, playback speed, repeat-one, and a sleep timer.
class AudioPlayerSurface extends StatefulWidget {
  final String filePath;
  final String title;
  final String? artist;
  final String? artworkUrl;

  /// Queue navigation (optional — shown when the player has neighbours).
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String? queueLabel;

  const AudioPlayerSurface({
    super.key,
    required this.filePath,
    required this.title,
    this.artist,
    this.artworkUrl,
    this.onPrev,
    this.onNext,
    this.queueLabel,
  });

  @override
  State<AudioPlayerSurface> createState() => _AudioPlayerSurfaceState();
}

class _AudioPlayerSurfaceState extends State<AudioPlayerSurface> {
  late final AudioPlayer _player;
  Object? _error;
  Timer? _sleepTimer;
  DateTime? _sleepUntil;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<ProcessingState>? _processingSub;
  int _lastSavedSeconds = -10;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _load();
    _initPositionSaving();
    // Auto-advance to the next queue item when a track finishes.
    _processingSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) widget.onNext?.call();
    });
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
      // Resume from where the user left off (throttled persistence below).
      final saved = await PlaybackPositionStore.load(widget.filePath);
      final duration = _player.duration;
      if (saved > Duration.zero && (duration == null || saved < duration)) {
        await _player.seek(saved);
      }
      await _player.play();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _initPositionSaving() {
    _positionSub = _player.positionStream.listen((position) {
      if (position.inSeconds - _lastSavedSeconds >= 5) {
        _lastSavedSeconds = position.inSeconds;
        PlaybackPositionStore.save(widget.filePath, position);
      }
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _positionSub?.cancel();
    _processingSub?.cancel();
    PlaybackPositionStore.save(widget.filePath, _player.position);
    _player.dispose();
    super.dispose();
  }

  void _setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    setState(() => _sleepUntil = null);
    if (duration == null) return;
    setState(() => _sleepUntil = DateTime.now().add(duration));
    _sleepTimer = Timer(duration, () {
      if (!mounted) return;
      _player.pause();
      setState(() => _sleepUntil = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (_error != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const _Backdrop(artworkUrl: null),
          const _PlayerNotice(
            icon: Icons.error_outline_rounded,
            title: 'Could not play this audio file',
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _Backdrop(artworkUrl: widget.artworkUrl),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ── Artwork ──────────────────────────
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          return _ArtworkTile(
                            artworkUrl: widget.artworkUrl,
                            playing: playing,
                            reduceMotion: reduceMotion,
                          );
                        },
                      ),
                      const SizedBox(height: 30),

                      // ── Title & artist ───────────────────
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.artist ?? 'KuramaBot audio',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // ── Media rail seek bar ──────────────
                      _SeekRail(player: _player),
                      const SizedBox(height: 22),

                      // ── Transport ────────────────────────
                      if (widget.queueLabel != null) ...[
                        Text(
                          widget.queueLabel!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _Transport(
                        player: _player,
                        onPrev: widget.onPrev,
                        onNext: widget.onNext,
                      ),
                      const SizedBox(height: 22),

                      // ── Speed, repeat & sleep ────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SpeedControl(player: _player),
                          const SizedBox(width: 12),
                          _RepeatToggle(player: _player),
                          const SizedBox(width: 12),
                          _SleepTimerButton(
                            until: _sleepUntil,
                            onSelect: _setSleepTimer,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // ── Lock-screen hint ─────────────────
                      const _LockHint(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Backdrop ────────────────────────────────────────────────

class _Backdrop extends StatelessWidget {
  final String? artworkUrl;

  const _Backdrop({this.artworkUrl});

  @override
  Widget build(BuildContext context) {
    final artwork = artworkUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base obsidian gradient
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.15,
              colors: [
                const Color(0xFF3A1A10),
                const Color(0xFF0A0A0E),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
        // Blurred artwork over the base gradient (later children paint on top)
        if (artwork != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 56, sigmaY: 56),
            child: Image.network(
              artwork,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        // Legibility scrim on top of the artwork
        if (artwork != null)
          Container(
            color: const Color(0xB30A0A0E),
            child: const SizedBox.expand(),
          ),
      ],
    );
  }
}

// ── Artwork tile ────────────────────────────────────────────

class _ArtworkTile extends StatelessWidget {
  final String? artworkUrl;
  final bool playing;
  final bool reduceMotion;

  const _ArtworkTile({
    required this.artworkUrl,
    required this.playing,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: playing ? 1.03 : 1.0,
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 550),
      curve: Curves.easeInOut,
      child: Container(
        width: 210,
        height: 210,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55FF5722),
              blurRadius: 48,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: artworkUrl != null
              ? Image.network(
                  artworkUrl!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const _ArtworkFallback(),
                )
              : const _ArtworkFallback(),
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7A3D), Color(0xFF5A1B12)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 84),
      ),
    );
  }
}

// ── Seek rail (signature amber seek bar) ────────────────────

class _SeekRail extends StatelessWidget {
  final AudioPlayer player;

  const _SeekRail({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final maximum = math.max(1, duration.inMilliseconds);
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final playedMs = math.min(position.inMilliseconds, maximum);
            return StreamBuilder<Duration>(
              stream: player.bufferedPositionStream,
              builder: (context, bufferedSnapshot) {
                final bufferedMs = math.min(
                  (bufferedSnapshot.data ?? Duration.zero).inMilliseconds,
                  maximum,
                );
                return Column(
                  children: [
                    _TimeRow(position: position, duration: duration),
                    const SizedBox(height: 6),
                    _MediaRail(
                      fraction: playedMs / maximum,
                      bufferedFraction: bufferedMs / maximum,
                      onSeek: (fraction) => player.seek(
                        Duration(milliseconds: (fraction * maximum).round()),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TimeRow extends StatelessWidget {
  final Duration position;
  final Duration duration;

  const _TimeRow({required this.position, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TimeLabel(text: _formatDuration(position), color: Colors.white60),
        _TimeLabel(text: _formatDuration(duration), color: Colors.white38),
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _TimeLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    );
  }
}

class _MediaRail extends StatelessWidget {
  final double fraction;
  final double bufferedFraction;
  final ValueChanged<double> onSeek;

  const _MediaRail({
    required this.fraction,
    required this.bufferedFraction,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final played = fraction.clamp(0.0, 1.0);
        final buffered = bufferedFraction.clamp(0.0, 1.0);
        const trackHeight = 5.0;

        void seekFrom(double dx) {
          onSeek((dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekFrom(details.localPosition.dx),
          onHorizontalDragUpdate: (details) =>
              seekFrom(details.localPosition.dx),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Base track
                Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(trackHeight / 2),
                  ),
                ),
                // Buffered portion
                FractionallySizedBox(
                  widthFactor: buffered,
                  child: Container(
                    height: trackHeight,
                    color: Colors.white24,
                  ),
                ),
                // Played amber rail
                FractionallySizedBox(
                  widthFactor: played,
                  child: Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9100), Color(0xFFFF5722)],
                      ),
                    ),
                  ),
                ),
                // Thumb
                Positioned(
                  left: (played * width - 7).clamp(0.0, width - 14),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFB74D),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99FF5722),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Transport / controls ────────────────────────────────────

class _Transport extends StatelessWidget {
  final AudioPlayer player;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _Transport({
    required this.player,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state?.processingState == ProcessingState.loading ||
            state?.processingState == ProcessingState.buffering) {
          return const SizedBox.square(
            dimension: 68,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFFFF5722),
            ),
          );
        }
        final playing = state?.playing ?? false;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onPrev != null) ...[
              IconButton.filledTonal(
                onPressed: onPrev,
                icon: const Icon(Icons.skip_previous_rounded),
                tooltip: 'Previous',
              ),
              const SizedBox(width: 24),
            ],
            IconButton.filledTonal(
              onPressed: () => _seekRelative(player, -10),
              icon: const Icon(Icons.replay_10_rounded),
              tooltip: 'Back 10 seconds',
            ),
            const SizedBox(width: 24),
            _PlayPauseButton(
              playing: playing,
              reduceMotion: reduceMotion,
              onPressed: playing ? player.pause : player.play,
            ),
            const SizedBox(width: 24),
            IconButton.filledTonal(
              onPressed: () => _seekRelative(player, 10),
              icon: const Icon(Icons.forward_10_rounded),
              tooltip: 'Forward 10 seconds',
            ),
            if (onNext != null) ...[
              const SizedBox(width: 24),
              IconButton.filledTonal(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded),
                tooltip: 'Next',
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool playing;
  final bool reduceMotion;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.playing,
    required this.reduceMotion,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: playing ? 'Pause' : 'Play',
      iconSize: 42,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFFF5722),
        foregroundColor: Colors.white,
        minimumSize: const Size(68, 68),
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: const Color(0x66FF5722),
      ),
      icon: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: child,
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(playing),
        ),
      ),
    );
  }
}

class _SpeedControl extends StatelessWidget {
  final AudioPlayer player;

  const _SpeedControl({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.speedStream,
      builder: (context, snapshot) {
        final speed = snapshot.data ?? 1.0;
        return PopupMenuButton<double>(
          tooltip: 'Playback speed',
          initialValue: speed,
          onSelected: (value) => player.setSpeed(value).catchError((_) {}),
          itemBuilder: (context) => [
            for (final option in _speedOptions)
              PopupMenuItem<double>(
                value: option,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_speedLabel(option)),
                    if ((option - speed).abs() < 0.001) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Color(0xFFFF8A65),
                      ),
                    ],
                  ],
                ),
              ),
          ],
          child: _ControlChip(
            icon: Icons.speed_rounded,
            label: _speedLabel(speed),
          ),
        );
      },
    );
  }
}

class _RepeatToggle extends StatelessWidget {
  final AudioPlayer player;

  const _RepeatToggle({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LoopMode>(
      stream: player.loopModeStream,
      builder: (context, snapshot) {
        final repeat = snapshot.data == LoopMode.one;
        return IconButton(
          onPressed: () => player.setLoopMode(
            repeat ? LoopMode.off : LoopMode.one,
          ),
          tooltip: repeat ? 'Repeat one · on' : 'Repeat one',
          icon: Icon(
            repeat ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            color: repeat ? const Color(0xFFFF8A65) : Colors.white54,
          ),
        );
      },
    );
  }
}

class _SleepTimerButton extends StatelessWidget {
  final DateTime? until;
  final ValueChanged<Duration?> onSelect;

  const _SleepTimerButton({required this.until, required this.onSelect});

  String get _label {
    if (until == null) return 'Sleep';
    final remaining = until!.difference(DateTime.now());
    final minutes = math.max(1, remaining.inMinutes.ceil());
    if (minutes >= 60) return 'Sleep ${minutes ~/ 60}h';
    return 'Sleep ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final active = until != null;
    return PopupMenuButton<Duration?>(
      tooltip: active ? 'Sleep timer · tap to cancel' : 'Sleep timer',
      onSelected: onSelect,
      itemBuilder: (context) => [
        PopupMenuItem<Duration?>(
          value: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_off_outlined, size: 18),
              const SizedBox(width: 8),
              Text(active ? 'Cancel sleep timer' : 'Sleep timer off'),
            ],
          ),
        ),
        for (final (duration, label) in _sleepOptions)
          PopupMenuItem<Duration?>(value: duration, child: Text(label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF5722).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFFFF8A65)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bedtime_rounded,
              size: 16,
              color: active ? const Color(0xFFFF8A65) : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              _label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? const Color(0xFFFFC9A0) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ControlChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockHint extends StatelessWidget {
  const _LockHint();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 13, color: Colors.white38),
        SizedBox(width: 6),
        Text(
          'Playback continues with the screen locked',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Notice ──────────────────────────────────────────────────

class _PlayerNotice extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlayerNotice({required this.icon, required this.title});

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
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
