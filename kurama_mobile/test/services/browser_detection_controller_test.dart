import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/models/video_info.dart';
import 'package:kurama_mobile/services/browser_detection_controller.dart';

VideoInfo infoFor(String url, {String title = 'Fox clip'}) => VideoInfo(
      url: url,
      platform: 'Test',
      icon: 'video',
      title: title,
      uploader: 'Creator',
      durationStr: '0:10',
      filesizeStr: '1 MB',
    );

void main() {
  test('publishes detected metadata after a successful probe', () async {
    final controller = BrowserDetectionController(
      probe: (url) async => infoFor(url),
      debounceDuration: Duration.zero,
    );

    await controller.detect('https://example.com/video');

    expect(controller.state.phase, BrowserDetectionPhase.detected);
    expect(controller.state.info?.title, 'Fox clip');
  });

  test('maps unsupported media separately from connection errors', () async {
    final controller = BrowserDetectionController(
      probe: (_) async => throw const UnsupportedMediaException('No media'),
      debounceDuration: Duration.zero,
    );

    await controller.detect('https://example.com/article');

    expect(controller.state.phase, BrowserDetectionPhase.unsupported);
  });

  test('maps unexpected probe failures to error', () async {
    final controller = BrowserDetectionController(
      probe: (_) async => throw Exception('Offline'),
      debounceDuration: Duration.zero,
    );

    await controller.detect('https://example.com/video');

    expect(controller.state.phase, BrowserDetectionPhase.error);
    expect(controller.state.message, contains('Offline'));
  });

  test('ignores a late response from the previous page', () async {
    final first = Completer<VideoInfo>();
    final second = Completer<VideoInfo>();
    final controller = BrowserDetectionController(
      probe: (url) => url.endsWith('/one') ? first.future : second.future,
      debounceDuration: Duration.zero,
    );

    final oldRequest = controller.detect('https://example.com/one');
    final newRequest = controller.detect('https://example.com/two');
    second.complete(infoFor('https://example.com/two', title: 'Two'));
    await newRequest;
    first.complete(infoFor('https://example.com/one', title: 'One'));
    await oldRequest;

    expect(controller.state.info?.title, 'Two');
  });

  test('suppresses a duplicate completed URL', () async {
    var calls = 0;
    final controller = BrowserDetectionController(
      probe: (url) async {
        calls++;
        return infoFor(url);
      },
      debounceDuration: Duration.zero,
    );

    await controller.detect('https://example.com/video');
    await controller.detect('https://example.com/video');

    expect(calls, 1);
  });

  test('navigation invalidates an in-flight response', () async {
    final response = Completer<VideoInfo>();
    final controller = BrowserDetectionController(
      probe: (_) => response.future,
      debounceDuration: Duration.zero,
    );

    final request = controller.detect('https://example.com/video');
    controller.beginNavigation();
    response.complete(infoFor('https://example.com/video'));
    await request;

    expect(controller.state.phase, BrowserDetectionPhase.idle);
  });
}
