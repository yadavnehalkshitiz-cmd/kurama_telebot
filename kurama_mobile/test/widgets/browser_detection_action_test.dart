import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/models/video_info.dart';
import 'package:kurama_mobile/services/browser_detection_controller.dart';
import 'package:kurama_mobile/widgets/browser_detection_action.dart';

VideoInfo media() => VideoInfo(
      url: 'https://example.com/video',
      platform: 'Test',
      icon: 'video',
      title: 'Fox clip',
      uploader: 'Creator',
      durationStr: '0:10',
      filesizeStr: '1 MB',
    );

Future<void> pumpAction(
  WidgetTester tester,
  BrowserDetectionState state, {
  VoidCallback? onDownload,
  VoidCallback? onRetry,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BrowserDetectionAction(
            state: state,
            onDownload: onDownload ?? () {},
            onRetry: onRetry ?? () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('idle renders no detection surface', (tester) async {
    await pumpAction(tester, BrowserDetectionState.idle);

    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Checking this page...'), findsNothing);
  });

  testWidgets('checking shows progress without download', (tester) async {
    await pumpAction(
      tester,
      const BrowserDetectionState(
        BrowserDetectionPhase.checking,
        url: 'https://example.com',
      ),
    );

    expect(find.text('Checking this page...'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('unsupported media has no action', (tester) async {
    await pumpAction(
      tester,
      const BrowserDetectionState(
        BrowserDetectionPhase.unsupported,
        url: 'https://example.com',
      ),
    );

    expect(find.text('No supported media found'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('error retries exactly once', (tester) async {
    var retries = 0;
    await pumpAction(
      tester,
      const BrowserDetectionState(
        BrowserDetectionPhase.error,
        message: 'Offline',
      ),
      onRetry: () => retries++,
    );

    await tester.tap(find.text('Retry'));

    expect(retries, 1);
  });

  testWidgets('detected media downloads exactly once', (tester) async {
    var downloads = 0;
    await pumpAction(
      tester,
      BrowserDetectionState(
        BrowserDetectionPhase.detected,
        url: 'https://example.com/video',
        info: media(),
      ),
      onDownload: () => downloads++,
    );

    expect(find.text('Fox clip'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    await tester.tap(find.text('Download'));

    expect(downloads, 1);
  });
}
