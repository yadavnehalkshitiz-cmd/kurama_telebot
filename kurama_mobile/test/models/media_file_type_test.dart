import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/models/media_file_type.dart';

void main() {
  group('classifyMediaFile', () {
    test('audio format wins even when the saved extension is generic', () {
      expect(
        classifyMediaFile(format: 'audio', path: '/media/download.bin'),
        MediaFileType.audio,
      );
    });

    test('recognizes audio and video extensions case-insensitively', () {
      expect(
        classifyMediaFile(format: 'doc', path: r'C:\Media\TRACK.MP3'),
        MediaFileType.audio,
      );
      expect(
        classifyMediaFile(format: 'doc', path: '/media/clip.mkv'),
        MediaFileType.video,
      );
    });

    test('uses declared video format before falling back to other', () {
      expect(
        classifyMediaFile(format: 'video', path: '/media/download.bin'),
        MediaFileType.video,
      );
      expect(
        classifyMediaFile(format: 'doc', path: '/media/archive.zip'),
        MediaFileType.other,
      );
    });
  });

  group('supportsGalleryExport', () {
    test('allows video and rejects audio and documents', () {
      expect(supportsGalleryExport('video'), isTrue);
      expect(supportsGalleryExport(' VIDEO '), isTrue);
      expect(supportsGalleryExport('audio'), isFalse);
      expect(supportsGalleryExport('doc'), isFalse);
    });
  });
}
