# Phase 1 Browser Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Android-first in-app browser that automatically probes the current public page through KuramaBot's backend and exposes downloads only for confirmed media.

**Architecture:** Keep WebView rendering in `BrowserScreen`, move address parsing and detection concurrency into independently tested services, and reuse `ApiClient.fetchInfo` plus `VideoInfoScreen` for the existing download flow. Detection is top-level URL based; request generations discard stale responses and no browser session data leaves the device.

**Tech Stack:** Flutter, Dart, `flutter_inappwebview`, Provider, `http`, `flutter_test`, FastAPI/yt-dlp backend, GitHub Actions Android build.

## Global Constraints

- Android is the Phase 1 release target; Dart services remain platform-neutral.
- Only public HTTP(S) page URLs are submitted to `POST /api/fetch-info`.
- Never send cookies, WebView headers, page HTML, form data, or login tokens.
- Never intercept raw media streams or attempt DRM/private-content extraction.
- The download action appears only after a current-generation `VideoInfo` response.
- Preserve existing user changes outside the files named by each task.
- New behavior follows red-green-refactor; every production behavior has a failing test first.

---

### Task 1: Safe browser address resolution

**Files:**
- Create: `kurama_mobile/lib/services/browser_address.dart`
- Create: `kurama_mobile/test/services/browser_address_test.dart`

**Interfaces:**
- Produces: `Uri? resolveBrowserInput(String input)` and `bool isSafeBrowserUri(Uri uri)`.
- Consumed by: `BrowserScreen` navigation and WebView policy in Task 4.

- [ ] **Step 1: Write the failing URL tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/services/browser_address.dart';

void main() {
  group('resolveBrowserInput', () {
    test('keeps a valid HTTPS URL', () {
      expect(resolveBrowserInput('https://vimeo.com/123').toString(),
          'https://vimeo.com/123');
    });

    test('upgrades a hostname-like input to HTTPS', () {
      expect(resolveBrowserInput('example.com/watch?v=1').toString(),
          'https://example.com/watch?v=1');
    });

    test('turns plain text into an encoded search URL', () {
      expect(resolveBrowserInput('funny fox video').toString(),
          'https://www.google.com/search?q=funny+fox+video');
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
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `flutter test test/services/browser_address_test.dart`

Expected: compilation fails because `browser_address.dart` does not exist.

- [ ] **Step 3: Implement the resolver**

```dart
bool isSafeBrowserUri(Uri uri) {
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

Uri? resolveBrowserInput(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    return isSafeBrowserUri(parsed) ? parsed : null;
  }

  final looksLikeHost = !value.contains(RegExp(r'\s')) && value.contains('.');
  if (looksLikeHost) {
    final uri = Uri.tryParse('https://$value');
    return uri != null && isSafeBrowserUri(uri) ? uri : null;
  }

  return Uri.https('www.google.com', '/search', {'q': value});
}
```

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run: `flutter test test/services/browser_address_test.dart`

Expected: all address tests pass.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- kurama_mobile/lib/services/browser_address.dart kurama_mobile/test/services/browser_address_test.dart
git commit -m "feat: validate browser navigation addresses"
```

---

### Task 2: Race-safe media detection state machine

**Files:**
- Create: `kurama_mobile/lib/services/browser_detection_controller.dart`
- Create: `kurama_mobile/test/services/browser_detection_controller_test.dart`

**Interfaces:**
- Consumes: `VideoInfo` and an injected `Future<VideoInfo> Function(String)`.
- Produces: `BrowserDetectionController`, `BrowserDetectionState`, `BrowserDetectionPhase`, and `UnsupportedMediaException`.
- Consumed by: browser status/action UI in Task 4.

- [ ] **Step 1: Write failing state-machine tests**

```dart
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
      probe: (url) async { calls++; return infoFor(url); },
      debounceDuration: Duration.zero,
    );
    await controller.detect('https://example.com/video');
    await controller.detect('https://example.com/video');
    expect(calls, 1);
  });
}
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `flutter test test/services/browser_detection_controller_test.dart`

Expected: compilation fails because the controller types do not exist.

- [ ] **Step 3: Implement the minimal controller**

Create the controller with this complete behavior:

```dart
import 'package:flutter/foundation.dart';
import '../models/video_info.dart';

enum BrowserDetectionPhase { idle, checking, detected, unsupported, error }
typedef MediaProbe = Future<VideoInfo> Function(String url);

class UnsupportedMediaException implements Exception {
  final String message;
  const UnsupportedMediaException(this.message);
}

class BrowserDetectionState {
  final BrowserDetectionPhase phase;
  final String? url;
  final VideoInfo? info;
  final String? message;
  const BrowserDetectionState(this.phase, {this.url, this.info, this.message});
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
    _setState(BrowserDetectionState(BrowserDetectionPhase.checking, url: url));

    if (debounceDuration > Duration.zero) {
      await Future<void>.delayed(debounceDuration);
      if (generation != _generation || _disposed) return;
    }

    try {
      final info = await probe(url);
      if (generation != _generation || _disposed) return;
      _setState(BrowserDetectionState(
        BrowserDetectionPhase.detected,
        url: url,
        info: info,
      ));
    } on UnsupportedMediaException catch (error) {
      if (generation != _generation || _disposed) return;
      _setState(BrowserDetectionState(
        BrowserDetectionPhase.unsupported,
        url: url,
        message: error.message,
      ));
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _setState(BrowserDetectionState(
        BrowserDetectionPhase.error,
        url: url,
        message: error.toString(),
      ));
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
```

- [ ] **Step 4: Run the focused test and confirm GREEN**

Run: `flutter test test/services/browser_detection_controller_test.dart`

Expected: all controller tests pass.

- [ ] **Step 5: Commit Task 2**

```powershell
git add -- kurama_mobile/lib/services/browser_detection_controller.dart kurama_mobile/test/services/browser_detection_controller_test.dart
git commit -m "feat: add race-safe browser media detection"
```

---

### Task 3: Typed unsupported-media API errors

**Files:**
- Modify: `kurama_mobile/lib/services/api_client.dart`
- Create: `kurama_mobile/test/services/api_exception_test.dart`

**Interfaces:**
- Produces: `ApiException.statusCode` and `ApiException.isUnsupportedMedia`.
- Consumed by: the `BrowserScreen` probe adapter in Task 4.

- [ ] **Step 1: Write the failing classification tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kurama_mobile/services/api_client.dart';

void main() {
  test('HTTP 400 is classified as unsupported media', () {
    final error = ApiException('No supported media', statusCode: 400);
    expect(error.isUnsupportedMedia, isTrue);
  });

  test('authentication and server errors are not unsupported media', () {
    expect(ApiException('Unauthorized', statusCode: 401).isUnsupportedMedia, isFalse);
    expect(ApiException('Server error', statusCode: 500).isUnsupportedMedia, isFalse);
  });
}
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `flutter test test/services/api_exception_test.dart`

Expected: compilation fails because `statusCode` and `isUnsupportedMedia` do not exist.

- [ ] **Step 3: Add typed status information**

Change `ApiException` to:

```dart
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  bool get isUnsupportedMedia => statusCode == 400;
  @override
  String toString() => message;
}
```

In `fetchInfo`, throw `ApiException(_extractError(resp), statusCode: resp.statusCode)` for non-200 responses. Preserve the existing behavior of every unrelated API method.

- [ ] **Step 4: Run tests and confirm GREEN**

Run: `flutter test test/services/api_exception_test.dart test/services/browser_detection_controller_test.dart`

Expected: both suites pass.

- [ ] **Step 5: Commit Task 3**

```powershell
git add -- kurama_mobile/lib/services/api_client.dart kurama_mobile/test/services/api_exception_test.dart
git commit -m "feat: classify unsupported media responses"
```

---

### Task 4: Integrate automatic detection into the browser UI

**Files:**
- Create: `kurama_mobile/lib/widgets/browser_detection_action.dart`
- Create: `kurama_mobile/test/widgets/browser_detection_action_test.dart`
- Modify: `kurama_mobile/lib/screens/browser_screen.dart`

**Interfaces:**
- Consumes: `resolveBrowserInput`, `isSafeBrowserUri`, `BrowserDetectionController`, `ApiClient.fetchInfo`, and `VideoInfoScreen(info:)`.
- Produces: a browser that probes after top-level load completion and a testable `BrowserDetectionAction` presentation widget.

- [ ] **Step 1: Write failing presentation tests**

Create `browser_detection_action_test.dart` with the full phase contract:

```dart
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
}) => tester.pumpWidget(MaterialApp(
  home: Scaffold(
    body: BrowserDetectionAction(
      state: state,
      onDownload: onDownload ?? () {},
      onRetry: onRetry ?? () {},
    ),
  ),
));

void main() {
  testWidgets('checking shows progress without download', (tester) async {
    await pumpAction(tester, const BrowserDetectionState(
      BrowserDetectionPhase.checking,
      url: 'https://example.com',
    ));
    expect(find.text('Checking this page...'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('unsupported media has no action', (tester) async {
    await pumpAction(tester, const BrowserDetectionState(
      BrowserDetectionPhase.unsupported,
      url: 'https://example.com',
    ));
    expect(find.text('No supported media found'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('error retries exactly once', (tester) async {
    var retries = 0;
    await pumpAction(
      tester,
      const BrowserDetectionState(BrowserDetectionPhase.error, message: 'Offline'),
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
    await tester.tap(find.text('Download'));
    expect(downloads, 1);
  });
}
```

The key assertions are:

```dart
expect(find.text('Checking this page…'), findsOneWidget); // checking
expect(find.byType(FilledButton), findsNothing);          // unsupported/error
expect(find.text('Download'), findsOneWidget);            // detected
expect(find.text('Fox clip'), findsOneWidget);             // detected metadata
```

The detected test passes a callback, taps `Download`, and expects that callback exactly once. The error test expects `Retry` and taps it once. The unsupported test expects `No supported media found` without a retry button.

- [ ] **Step 2: Run the widget test and confirm RED**

Run: `flutter test test/widgets/browser_detection_action_test.dart`

Expected: compilation fails because `BrowserDetectionAction` does not exist.

- [ ] **Step 3: Implement the focused presentation widget**

Create `browser_detection_action.dart` with this complete widget:

```dart
import 'package:flutter/material.dart';
import '../services/browser_detection_controller.dart';

class BrowserDetectionAction extends StatelessWidget {
  final BrowserDetectionState state;
  final VoidCallback onDownload;
  final VoidCallback onRetry;

  const BrowserDetectionAction({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case BrowserDetectionPhase.idle:
        return const SizedBox.shrink();
      case BrowserDetectionPhase.checking:
        return const _StatusCard(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFFFFB02E))),
            SizedBox(width: 10),
            Text('Checking this page...'),
          ]),
        );
      case BrowserDetectionPhase.unsupported:
        return const _StatusCard(child: Text('No supported media found'));
      case BrowserDetectionPhase.error:
        return _StatusCard(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 18),
            const SizedBox(width: 8),
            const Text('Detection unavailable'),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        );
      case BrowserDetectionPhase.detected:
        final info = state.info!;
        return AnimatedScale(
          scale: 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: _StatusCard(
            borderColor: const Color(0xFF3DDC97),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF3DDC97)),
                const SizedBox(width: 10),
                Flexible(child: Text(info.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                ),
              ]),
            ),
          ),
        );
    }
  }
}

class _StatusCard extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  const _StatusCard({
    required this.child,
    this.borderColor = const Color(0x33FFFFFF),
  });

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF171720),
    elevation: 8,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    ),
  );
}
```

Its public fields are:

```dart
final BrowserDetectionState state;
final VoidCallback onDownload;
final VoidCallback onRetry;
```

Render nothing for `idle`; a compact amber status chip for `checking`; quiet ash copy for `unsupported`; an error chip with `Retry` for `error`; and an `AnimatedScale` card plus one `FilledButton.icon` for `detected`. Use the design tokens from the specification and do not claim “HD.”

- [ ] **Step 4: Run the widget test and confirm GREEN**

Run: `flutter test test/widgets/browser_detection_action_test.dart`

Expected: all presentation tests pass.

- [ ] **Step 5: Refactor `BrowserScreen` around the controller**

Use these controller, navigation, and download adapters:

```dart
late final BrowserDetectionController _detectionController;

@override
void initState() {
  super.initState();
  _detectionController = BrowserDetectionController(probe: (url) async {
    try {
      return await context.read<AppState>().client.fetchInfo(url);
    } on ApiException catch (error) {
      if (error.isUnsupportedMedia) {
        throw UnsupportedMediaException(error.message);
      }
      rethrow;
    }
  });
}

void _loadInput(String input) {
  final uri = resolveBrowserInput(input);
  if (uri == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enter a valid web address or search phrase')),
    );
    return;
  }
  _urlController.text = uri.toString();
  _webViewController?.loadUrl(
    urlRequest: URLRequest(url: WebUri(uri.toString())),
  );
}

void _openDetectedMedia() {
  final info = _detectionController.state.info;
  if (info == null) return;
  Navigator.push(context,
    MaterialPageRoute(builder: (_) => VideoInfoScreen(info: info)));
}

void _retryDetection() {
  final url = _detectionController.state.url ?? _urlController.text;
  final uri = Uri.tryParse(url);
  if (uri != null && isSafeBrowserUri(uri)) {
    _detectionController.beginNavigation();
    _detectionController.detect(uri.toString());
  }
}
```

Use these WebView callbacks:

```dart
onLoadStart: (_, url) {
  _detectionController.beginNavigation();
  if (url != null) setState(() => _urlController.text = url.toString());
},
onLoadStop: (_, url) {
  if (url == null) return;
  final uri = Uri.tryParse(url.toString());
  if (uri != null && isSafeBrowserUri(uri)) {
    setState(() => _urlController.text = uri.toString());
    _detectionController.detect(uri.toString());
  }
},
shouldOverrideUrlLoading: (_, action) async {
  final raw = action.request.url?.toString();
  final uri = raw == null ? null : Uri.tryParse(raw);
  return uri != null && isSafeBrowserUri(uri)
      ? NavigationActionPolicy.ALLOW
      : NavigationActionPolicy.CANCEL;
},
```

Replace the prototype floating button with:

```dart
Positioned(
  left: 16,
  right: 16,
  bottom: 20,
  child: AnimatedBuilder(
    animation: _detectionController,
    builder: (_, __) => BrowserDetectionAction(
      state: _detectionController.state,
      onDownload: _openDetectedMedia,
      onRetry: _retryDetection,
    ),
  ),
),
```

Apply these integration constraints:

- Replace `_detectedVideoUrl` and `_isSniffing` with one owned `BrowserDetectionController`.
- Create its probe adapter with `context.read<AppState>().client.fetchInfo(url)` and convert `ApiException.isUnsupportedMedia` to `UnsupportedMediaException`.
- Use `resolveBrowserInput` in address submission and refuse null results with inline feedback.
- Call `beginNavigation()` from `onLoadStart`.
- Call `detect(url.toString())` from `onLoadStop` only for safe HTTP(S) URLs.
- Add `shouldOverrideUrlLoading` and cancel non-HTTP(S) navigation.
- Render `BrowserDetectionAction` from an `AnimatedBuilder` listening to the controller.
- On download, read `controller.state.info` and push `VideoInfoScreen(info: info)` without another backend request.
- On retry, call `detect` with the current safe top-level URL.
- Dispose both the text controller and detection controller.
- Keep webpage progress, refresh, search, bookmarks, and the existing bottom-navigation integration.

- [ ] **Step 6: Run all Phase 1 tests**

Run: `flutter test test/services test/widgets/browser_detection_action_test.dart`

Expected: all tests pass.

- [ ] **Step 7: Commit Task 4**

```powershell
git add -- kurama_mobile/lib/screens/browser_screen.dart kurama_mobile/lib/widgets/browser_detection_action.dart kurama_mobile/test/widgets/browser_detection_action_test.dart
git commit -m "feat: confirm media automatically in browser"
```

---

### Task 5: Android configuration and CI quality gates

**Files:**
- Modify: `kurama_mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `.github/workflows/flutter_build.yml`

**Interfaces:**
- Consumes: the Phase 1 tests from Tasks 1–4.
- Produces: Android WebView/network permissions and CI enforcement before APK creation.

- [ ] **Step 1: Verify the manifest contract before editing**

Run:

```powershell
rg -n "android.permission.INTERNET|android.permission.ACCESS_NETWORK_STATE|usesCleartextTraffic" kurama_mobile/android/app/src/main/AndroidManifest.xml
```

Expected: each required setting appears exactly once. Preserve the existing share intent and `${applicationName}` declaration.

- [ ] **Step 2: Add CI test and analysis steps**

In `build_android`, after `flutter pub get` and before `flutter build apk`, add:

```yaml
      - name: Run Flutter tests
        run: flutter test
        working-directory: ./kurama_mobile

      - name: Analyze Flutter app
        run: flutter analyze --no-fatal-infos
        working-directory: ./kurama_mobile
```

Use `--no-fatal-infos` only for existing informational lints; warnings and errors remain fatal.

- [ ] **Step 3: Run local static checks**

Run:

```powershell
flutter pub get
flutter test
flutter analyze --no-fatal-infos
```

Working directory: `kurama_mobile`.

Expected: dependency resolution succeeds, all tests pass, and analysis has no errors or warnings.

- [ ] **Step 4: Build the Android release APK**

Run:

```powershell
flutter create --platforms=android .
flutter build apk --release --no-tree-shake-icons
```

Working directory: `kurama_mobile`.

Expected artifact: `kurama_mobile/build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 5: Commit Task 5**

```powershell
git add -- .github/workflows/flutter_build.yml kurama_mobile/android/app/src/main/AndroidManifest.xml
git commit -m "ci: verify phase 1 Flutter browser build"
```

---

### Task 6: Final verification and scope audit

**Files:**
- Verify only; no production files expected.

**Interfaces:**
- Consumes: every Phase 1 task.
- Produces: evidence that the implemented change matches the design and preserves user work.

- [ ] **Step 1: Run the complete Flutter verification suite**

Run in `kurama_mobile`:

```powershell
flutter pub get
flutter test
flutter analyze --no-fatal-infos
flutter build apk --release --no-tree-shake-icons
```

Expected: every command exits zero and the release APK exists.

- [ ] **Step 2: Check scope and security invariants**

Run from the repository root:

```powershell
rg -n "Cookie|cookie|shouldInterceptRequest|evaluateJavascript|javascript:|data:|file:" kurama_mobile/lib/screens/browser_screen.dart kurama_mobile/lib/services/browser_detection_controller.dart
```

Expected: no cookie transfer, raw-resource interception, or arbitrary JavaScript evaluation exists; unsafe schemes appear only in explicit rejection logic/tests.

- [ ] **Step 3: Confirm the working tree contains no accidental files**

Run:

```powershell
git status --short
git diff --check
```

Expected: only intentional pre-existing user changes and Phase 1 changes are present; no temporary SDK, build artifact, credential, or cache file is staged.

- [ ] **Step 4: Record the final implementation commit**

Stage only any intentional Phase 1 files not already committed, then commit with:

```powershell
git commit -m "feat: complete phase 1 browser detection"
```

Do not stage unrelated Python backend changes or later-phase Flutter prototype screens.
