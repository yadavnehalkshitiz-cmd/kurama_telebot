import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/app_state.dart';
import '../services/browser_address.dart';
import '../services/browser_detection_controller.dart';
import '../widgets/browser_detection_action.dart';
import 'video_info_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const _initialUrl = 'https://m.youtube.com';

  final _urlController = TextEditingController(text: _initialUrl);
  InAppWebViewController? _webViewController;
  late final BrowserDetectionController _detectionController;
  double _progress = 0;

  static const _quickBookmarks = [
    _QuickBookmark('YouTube', 'https://m.youtube.com', Icons.smart_display_rounded),
    _QuickBookmark('Instagram', 'https://www.instagram.com', Icons.camera_alt_rounded),
    _QuickBookmark('TikTok', 'https://www.tiktok.com', Icons.music_note_rounded),
    _QuickBookmark('X', 'https://x.com', Icons.alternate_email_rounded),
    _QuickBookmark('Facebook', 'https://m.facebook.com', Icons.public_rounded),
    _QuickBookmark('Pinterest', 'https://www.pinterest.com', Icons.push_pin_rounded),
  ];

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

  @override
  void dispose() {
    _detectionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _loadInput(String input) {
    final uri = resolveBrowserInput(input);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid web address or search phrase'),
        ),
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoInfoScreen(info: info)),
    );
  }

  void _retryDetection() {
    final url = _detectionController.state.url ?? _urlController.text;
    final uri = Uri.tryParse(url);
    if (uri != null && isSafeBrowserUri(uri)) {
      _detectionController.beginNavigation();
      _detectionController.detect(uri.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            if (await _webViewController?.canGoBack() ?? false) {
              await _webViewController?.goBack();
            }
          },
        ),
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'Search or type web address',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
              prefixIcon: const Icon(Icons.language_rounded, size: 18),
              suffixIcon: IconButton(
                tooltip: 'Go',
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                onPressed: () => _loadInput(_urlController.text),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            style: const TextStyle(fontSize: 13),
            textInputAction: TextInputAction.go,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: _loadInput,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_progress > 0 && _progress < 1)
                LinearProgressIndicator(
                  value: _progress,
                  color: primary,
                  minHeight: 2,
                ),
              Container(
                height: 46,
                color: const Color(0xFF12121A),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  itemCount: _quickBookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final bookmark = _quickBookmarks[index];
                    return ActionChip(
                      avatar: Icon(bookmark.icon, size: 15),
                      label: Text(bookmark.name),
                      onPressed: () => _loadInput(bookmark.url),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_initialUrl)),
                  initialSettings: InAppWebViewSettings(
                    useShouldOverrideUrlLoading: true,
                    mediaPlaybackRequiresUserGesture: true,
                    allowsInlineMediaPlayback: true,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    // JS Handler for video detection
                    controller.addJavaScriptHandler(
                      handlerName: 'videoDetected',
                      callback: (args) {
                        if (args.isNotEmpty && mounted) {
                          // If we haven't detected anything via URL probe yet,
                          // we can use this signal to show the download prompt.
                          if (_detectionController.state.phase == BrowserDetectionPhase.unsupported ||
                              _detectionController.state.phase == BrowserDetectionPhase.idle) {
                             _detectionController.detect(_urlController.text);
                          }
                        }
                      },
                    );
                  },
                  onLoadStart: (_, url) {
                    _detectionController.beginNavigation();
                    if (url != null && mounted) {
                      setState(() => _urlController.text = url.toString());
                    }
                  },
                  onLoadStop: (controller, url) {
                    if (url == null) return;

                    // Inject video sniffer script
                    controller.evaluateJavascript(source: """
                      (function() {
                        function check() {
                          var v = document.getElementsByTagName('video');
                          if (v.length > 0 && v[0].src) {
                            window.flutter_inappwebview.callHandler('videoDetected', { src: v[0].src });
                          }
                        }
                        var observer = new MutationObserver(check);
                        observer.observe(document.body, { childList: true, subtree: true });
                        check();
                      })();
                    """);

                    final uri = Uri.tryParse(url.toString());
                    if (uri != null && isSafeBrowserUri(uri)) {
                      if (mounted) {
                        setState(() => _urlController.text = uri.toString());
                      }
                      _detectionController.detect(uri.toString());
                    }
                  },
                  onProgressChanged: (_, progress) {
                    if (mounted) setState(() => _progress = progress / 100);
                  },
                  shouldOverrideUrlLoading: (_, action) async {
                    final raw = action.request.url?.toString();
                    final uri = raw == null ? null : Uri.tryParse(raw);
                    return uri != null && isSafeBrowserUri(uri)
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                ),
              ),
            ],
          ),
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
        ],
      ),
    );
  }
}

class _QuickBookmark {
  final String name;
  final String url;
  final IconData icon;

  const _QuickBookmark(this.name, this.url, this.icon);
}
