import 'package:flutter/foundation.dart';

import '../models/video_info.dart';

enum BrowserDetectionPhase { idle, checking, detected, unsupported, error }

typedef MediaProbe = Future<VideoInfo> Function(String url);

class UnsupportedMediaException implements Exception {
  final String message;

  const UnsupportedMediaException(this.message);

  @override
  String toString() => message;
}

class BrowserDetectionState {
  final BrowserDetectionPhase phase;
  final String? url;
  final VideoInfo? info;
  final String? message;

  const BrowserDetectionState(
    this.phase, {
    this.url,
    this.info,
    this.message,
  });

  static const idle = BrowserDetectionState(BrowserDetectionPhase.idle);
}

class BrowserDetectionController extends ChangeNotifier {
  final MediaProbe probe;
  final Duration debounceDuration;

  BrowserDetectionState _state = BrowserDetectionState.idle;
  int _generation = 0;
  bool _disposed = false;

  BrowserDetectionController({
    required this.probe,
    this.debounceDuration = const Duration(milliseconds: 350),
  });

  BrowserDetectionState get state => _state;

  void beginNavigation() {
    _generation++;
    _setState(BrowserDetectionState.idle);
  }

  Future<void> detect(String url) async {
    if ((_state.phase == BrowserDetectionPhase.checking ||
            _state.phase == BrowserDetectionPhase.detected ||
            _state.phase == BrowserDetectionPhase.unsupported) &&
        _state.url == url) {
      return;
    }

    final generation = ++_generation;
    _setState(
      BrowserDetectionState(BrowserDetectionPhase.checking, url: url),
    );

    if (debounceDuration > Duration.zero) {
      await Future<void>.delayed(debounceDuration);
      if (generation != _generation || _disposed) return;
    }

    try {
      final info = await probe(url);
      if (generation != _generation || _disposed) return;
      _setState(
        BrowserDetectionState(
          BrowserDetectionPhase.detected,
          url: url,
          info: info,
        ),
      );
    } on UnsupportedMediaException catch (error) {
      if (generation != _generation || _disposed) return;
      _setState(
        BrowserDetectionState(
          BrowserDetectionPhase.unsupported,
          url: url,
          message: error.message,
        ),
      );
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _setState(
        BrowserDetectionState(
          BrowserDetectionPhase.error,
          url: url,
          message: error.toString(),
        ),
      );
    }
  }

  void _setState(BrowserDetectionState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
