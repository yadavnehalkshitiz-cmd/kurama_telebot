import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/services/browser_address.dart';

void main() {
  group('resolveBrowserInput', () {
    test('keeps a valid HTTPS URL', () {
      expect(
        resolveBrowserInput('https://vimeo.com/123').toString(),
        'https://vimeo.com/123',
      );
    });

    test('upgrades a hostname-like input to HTTPS', () {
      expect(
        resolveBrowserInput('example.com/watch?v=1').toString(),
        'https://example.com/watch?v=1',
      );
    });

    test('turns plain text into an encoded search URL', () {
      expect(
        resolveBrowserInput('funny fox video').toString(),
        'https://www.google.com/search?q=funny+fox+video',
      );
    });

    test('rejects unsafe schemes', () {
      expect(resolveBrowserInput('javascript:alert(1)'), isNull);
      expect(resolveBrowserInput('file:///tmp/video.mp4'), isNull);
      expect(resolveBrowserInput('data:text/html,hello'), isNull);
    });

    test('rejects blank input', () {
      expect(resolveBrowserInput('   '), isNull);
    });
  });

  test('safe browser URLs require HTTP or HTTPS and a host', () {
    expect(isSafeBrowserUri(Uri.parse('https://example.com')), isTrue);
    expect(isSafeBrowserUri(Uri.parse('http://localhost:8000')), isTrue);
    expect(isSafeBrowserUri(Uri.parse('content://media/1')), isFalse);
    expect(isSafeBrowserUri(Uri.parse('https:///missing-host')), isFalse);
  });
}
