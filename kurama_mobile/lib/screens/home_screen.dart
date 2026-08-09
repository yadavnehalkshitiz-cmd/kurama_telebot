import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/app_state.dart';
import '../services/api_client.dart';
import '../services/media_library.dart';
import '../widgets/connection_banner.dart';
import 'video_info_screen.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.offline;
  bool _checkingConnection = true;
  bool _promptedForKey = false;
  String? _pendingFetchUrl;
  StreamSubscription? _intentSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConnection();
    _initShareIntentListener();
  }

  @override
  void dispose() {
    _intentSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  /// Listen for shared video links from external apps (YouTube, TikTok, Instagram, Twitter, etc.)
  void _initShareIntentListener() {
    try {
      // Shared text/links while app is running
      _intentSubscription =
          ReceiveSharingIntent.instance.getMediaStream().listen((value) {
        if (value.isNotEmpty) {
          for (var file in value) {
            _handleSharedItem(file.path);
          }
        }
      }, onError: (err) {
        debugPrint('Share intent stream error: $err');
      });

      // Shared text/links when app is opened from closed state
      ReceiveSharingIntent.instance.getInitialMedia().then((value) {
        if (value.isNotEmpty) {
          for (var file in value) {
            _handleSharedItem(file.path);
          }
        }
      }).catchError((err) {
        debugPrint('Share intent initial media error: $err');
      });
    } catch (e) {
      debugPrint('ReceiveSharingIntent not supported on this platform: $e');
    }
  }

  void _handleSharedItem(String path) {
    // Local media files shared into the app are imported + played; text and
    // links go through the normal URL flow.
    if (isMediaFile(path) && File(path).existsSync()) {
      _handleSharedMediaFile(path);
      return;
    }
    _handleSharedUrl(path);
  }

  Future<void> _handleSharedMediaFile(String path) async {
    final state = context.read<AppState>();
    final task = await importLocalFile(state, path);
    if (!mounted) return;
    if (task == null || task.localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Could not import that file')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          filePath: task.localPath!,
          title: task.title,
          format: task.format,
          artist: task.format == 'audio' ? task.platform : null,
        ),
      ),
    );
  }

  void _handleSharedUrl(String text) {
    final extractedUrl = _extractFirstUrl(text);
    if (extractedUrl != null && extractedUrl.isNotEmpty) {
      if (mounted) {
        setState(() => _urlController.text = extractedUrl);
        _fetchInfo();
      }
    }
  }

  String? _extractFirstUrl(String text) {
    final exp = RegExp(r'https?://[^\s]+');
    final match = exp.firstMatch(text);
    return match?.group(0);
  }

  // Check clipboard for links when app comes to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForLink();
    }
  }

  Future<void> _checkClipboardForLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      final url = _extractFirstUrl(text);
      if (url != null && url.isNotEmpty) {
        if (!mounted) return;
        // If current input is empty, just auto-fill
        if (_urlController.text.isEmpty) {
          setState(() => _urlController.text = url);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('📋 Auto-pasted link from clipboard'),
              action: SnackBarAction(
                label: 'Fetch',
                onPressed: _fetchInfo,
              ),
              duration: const Duration(seconds: 3),
            ),
          );
          return;
        }
        // If it's a DIFFERENT link, show a suggestion snackbar
        if (_urlController.text != url) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('🔗 Link detected in clipboard'),
              action: SnackBarAction(
                label: 'Paste',
                onPressed: () {
                  setState(() => _urlController.text = url);
                  _fetchInfo();
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (_) {
      // Clipboard access might be restricted on some OS versions/states
    }
  }

  Future<void> _checkConnection() async {
    setState(() => _checkingConnection = true);
    final client = context.read<AppState>().client;
    final status = await client.checkConnection();
    if (!mounted) return;
    setState(() {
      _connectionStatus = status;
      _checkingConnection = false;
    });
    // Fresh installs ship a placeholder API key: `/api/health` still answers
    // 200 so the app used to look "connected" while every request 401'd.
    // Prompt for the real key once instead of leaving the user confused.
    if (!_promptedForKey && status == ConnectionStatus.invalidKey) {
      final key = client.apiKey;
      if (key.isEmpty || key == 'changeme-in-production') {
        _promptedForKey = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showConfigDialog();
        });
      }
    }
  }

  // ── Server config dialog ─────────────────────────────────

  void _showConfigDialog({String? url, String? key}) {
    final state = context.read<AppState>();
    final api = state.client;
    final urlController = TextEditingController(text: url ?? api.baseUrl);
    final keyController = TextEditingController(text: key ?? api.apiKey);
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('⚙️ Server Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://kurama-telebot.onrender.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  prefixIcon: Icon(Icons.key_outlined),
                  helperText: 'Same as KURAMA_API_KEY on your server',
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      final newClient = ApiClient(
                        baseUrl: urlController.text.trim(),
                        apiKey: keyController.text.trim(),
                      );
                      final status = await newClient.checkConnection();
                      if (!mounted) return;
                      if (!ctx.mounted) return;
                      if (status == ConnectionStatus.connected) {
                        context.read<AppState>().updateClient(newClient);
                        Navigator.pop(ctx);
                        setState(
                          () => _connectionStatus = ConnectionStatus.connected,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Connected to server'),
                              backgroundColor: Color(0xFF2E7D32),
                            ),
                          );
                        }
                        // Auto-retry the link that failed with the old key.
                        final pending = _pendingFetchUrl;
                        if (pending != null) {
                          _pendingFetchUrl = null;
                          _fetchInfo(pending);
                        }
                      } else if (status == ConnectionStatus.invalidKey) {
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '❌ Server reached, but the API key was rejected'),
                            backgroundColor: Color(0xFFC62828),
                          ),
                        );
                      } else {
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '❌ Could not reach server. Check URL and network.'),
                            backgroundColor: Color(0xFFC62828),
                          ),
                        );
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.link),
              label: Text(saving ? 'Connecting...' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    final url = _extractFirstUrl(text);
    if (url != null && url.isNotEmpty) {
      setState(() => _urlController.text = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Pasted link from clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No valid video link found in clipboard'),
        ),
      );
    }
  }

  Future<void> _fetchInfo([String? overrideUrl]) async {
    final rawText = overrideUrl ?? _urlController.text.trim();
    final url = _extractFirstUrl(rawText) ?? rawText;

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste or enter a video URL')),
      );
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('URL must start with http:// or https://')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = context.read<AppState>().client;
      final info = await api.fetchInfo(url);
      _pendingFetchUrl = null;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoInfoScreen(info: info)),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.isAuthError) {
        // The server is reachable but rejected the key — flip the banner to
        // "Fix Key" and open Server Settings once so the user can paste the
        // correct key instead of hitting a dead-end error snackbar. The URL
        // is remembered so the fetch auto-retries after the key is fixed.
        setState(() => _connectionStatus = ConnectionStatus.invalidKey);
        _pendingFetchUrl = url;
        if (!_promptedForKey) {
          _promptedForKey = true;
          _showConfigDialog();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('❌ API key rejected — update it in Server Settings'),
            backgroundColor: Color(0xFFC62828),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.toString()}'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/logo.png',
                width: 26,
                height: 26,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Text('🦊', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'KuramaBot',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  fontSize: 18),
            ),
          ],
        ),
        actions: [
          // Connection status dot
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
            child: _checkingConnection
                ? const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _StatusDot(status: _connectionStatus),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showConfigDialog,
            tooltip: 'Server Settings',
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DownloadsScreen()),
            ),
            tooltip: 'Downloads',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          ConnectionBanner(
            status: _connectionStatus,
            serverUrl: context.read<AppState>().client.baseUrl,
            onTapSettings: _showConfigDialog,
            onUseCloud: () => _showConfigDialog(
              url: 'https://kurama-telebot.onrender.com',
            ),
            onRetry: _checkConnection,
          ),

          // ── Hero section ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.18),
                  primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Column(
              children: [
                _AnimatedFoxIcon(color: primary),
                const SizedBox(height: 12),
                Text(
                  'Share link from any app or paste below',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── URL input section ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Video Link',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                    InkWell(
                      onTap: _pasteFromClipboard,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.paste_rounded,
                                size: 14, color: Color(0xFFFF8A65)),
                            SizedBox(width: 4),
                            Text(
                              'Paste Clipboard',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFFF8A65),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: 'Paste video link here...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          prefixIcon: const Icon(Icons.link_rounded, size: 20),
                          suffixIcon: _urlController.text.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () =>
                                      setState(() => _urlController.clear()),
                                )
                              : null,
                        ),
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _fetchInfo(),
                        autocorrect: false,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _fetchInfo,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(_isLoading
                        ? 'Fetching details...'
                        : 'Fetch & Download Video'),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── Platform chips ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              children: [
                Text(
                  'Supported Platforms',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                const Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _PlatformChip('🎬', 'YouTube'),
                    _PlatformChip('📸', 'Instagram'),
                    _PlatformChip('🎵', 'TikTok'),
                    _PlatformChip('🐦', 'Twitter/X'),
                    _PlatformChip('🌐', 'Facebook'),
                    _PlatformChip('🤖', 'Reddit'),
                    _PlatformChip('🔵', 'Vimeo'),
                    _PlatformChip('🎮', 'Twitch'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated 🦊 hero icon ─────────────────────────────────
class _AnimatedFoxIcon extends StatefulWidget {
  final Color color;
  const _AnimatedFoxIcon({required this.color});

  @override
  State<_AnimatedFoxIcon> createState() => _AnimatedFoxIconState();
}

class _AnimatedFoxIconState extends State<_AnimatedFoxIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5722).withValues(alpha: 0.45),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: widget.color.withValues(alpha: 0.2),
              child: const Center(
                child: Text('🦊', style: TextStyle(fontSize: 44)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Platform chip ─────────────────────────────────────────
class _PlatformChip extends StatelessWidget {
  final String emoji;
  final String label;
  const _PlatformChip(this.emoji, this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connection status dot ──────────────────────────────────
class _StatusDot extends StatelessWidget {
  final ConnectionStatus status;

  const _StatusDot({required this.status});

  Color get _color => switch (status) {
        ConnectionStatus.connected => const Color(0xFF4CAF50),
        ConnectionStatus.invalidKey => const Color(0xFFFFB300),
        ConnectionStatus.offline => const Color(0xFFFF8A65),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color,
        boxShadow: [
          BoxShadow(
            color: _color.withValues(alpha: 0.6),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
