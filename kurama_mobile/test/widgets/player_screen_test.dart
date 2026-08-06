import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/screens/player_screen.dart';
import 'package:kurama_mobile/widgets/audio_player_surface.dart';

/// Lets real async I/O (file checks, plugin futures) complete and re-renders.
Future<void> settleIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
}

void main() {
  testWidgets('missing file shows a graceful error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayerScreen(
          filePath: r'C:\kurama\definitely-missing.mp4',
          title: 'Ghost clip',
          format: 'video',
        ),
      ),
    );
    await settleIo(tester);

    expect(find.text('Could not play this media file'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('audio files route to the audio player surface', (tester) async {
    late File file;
    late Directory tempDir;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('kurama_audio_test');
      file = File('${tempDir.path}${Platform.pathSeparator}track.mp3');
      await file.writeAsBytes(const [0, 0, 0]);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          filePath: file.path,
          title: 'Test track',
          format: 'audio',
          artist: 'YouTube',
        ),
      ),
    );
    await settleIo(tester);
    await settleIo(tester);

    expect(find.byType(AudioPlayerSurface), findsOneWidget);
    // Without a real playback platform the load fails and the surface shows
    // its graceful error notice instead of crashing.
    expect(find.text('Could not play this audio file'), findsOneWidget);

    await tester.runAsync(() async {
      if (await file.exists()) await file.delete();
      await tempDir.delete(recursive: true);
    });
  });
}
