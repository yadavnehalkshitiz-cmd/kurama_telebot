import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/services/api_client.dart';

void main() {
  test('HTTP 400 is classified as unsupported media', () {
    final error = ApiException('No supported media', statusCode: 400);
    expect(error.isUnsupportedMedia, isTrue);
  });

  test('authentication and server errors are not unsupported media', () {
    expect(
      ApiException('Unauthorized', statusCode: 401).isUnsupportedMedia,
      isFalse,
    );
    expect(
      ApiException('Server error', statusCode: 500).isUnsupportedMedia,
      isFalse,
    );
  });
}
