import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/api_client.dart';
import '../widgets/connection_banner.dart';
import 'video_info_screen.dart';
import 'downloads_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  bool _isConnected = false;
  bool _checkingConnection = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  // Auto-paste from clipboard when app comes to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _urlController.text.isEmpty) {
      _tryAutoFillFromClipboard();
    }
  }

  Future<void> _tryAutoFillFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.startsWith('http://') || text.startsWith('https://')) {
      if (mounted && _urlController.text.isEmpty) {
        setState(() => _urlController.text = text);
      }
    }
  }

  Future<void> _checkConnection() async {
    setState(() => _checkingConnection = true);
    final client = context.read<AppState>().client;
    final ok = await client.healthCheck();
    if (mounted) {
      setState(() {
        _isConnected = ok;
        _checkingConnection = false;
      });
    }
  }

  // ── Server config dialog ─────────────────────────────────

  void _showConfigDialog() {
    final state = context.read<AppState>();
    final api = state.client;
    final urlController = TextEditingController(text: api.baseUrl);
    final keyController = TextEditingController(text: api.apiKey);
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
                  hintText: 'http://192.168.1.100:8000',
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
                      final ok = await newClient.healthCheck();
                      if (!ctx.mounted) return;
                      if (ok) {
                        context.read<AppState>().updateClient(newClient);
                        Navigator.pop(ctx);
                        setState(() => _isConnected = true);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Connected to server'),
                              backgroundColor: Color(0xFF2E7D32),
                            ),
                          );
                        }
                      } else {
                        setDialogState(() => saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('❌ Could not reach server'),
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
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _urlController.text = data.text!.trim());
    }
  }

  Future<void> _fetchInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL')),
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
      // ✅ FIX: access ApiClient through AppState — it's not provided separately
      final api = context.read<AppState>().client;
      final info = await api.fetchInfo(url);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoInfoScreen(info: info)),
      );
    } catch (e) {
      if (!mounted) return;
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
        title: const Text(
          '🦊 KuramaBot',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
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
                : Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isConnected
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFEF5350),
                      boxShadow: [
                        BoxShadow(
                          color: (_isConnected
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFEF5350))
                              .withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
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
          // Connection offline banner
          ConnectionBanner(
            isConnected: _isConnected,
            serverUrl: context.read<AppState>().client.baseUrl,
            onTapSettings: _showConfigDialog,
          ),

          // ── Hero section ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
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
                  'Download from 15+ platforms',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── URL input ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste a video link',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: 'https://youtube.com/watch?v=...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          prefixIcon: const Icon(Icons.link, size: 20),
                        ),
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _fetchInfo(),
                        autocorrect: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Paste from clipboard',
                      child: IconButton.filled(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.08),
                          foregroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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
                        : const Icon(Icons.search_rounded),
                    label: Text(_isLoading ? 'Fetching info...' : 'Get Video Info'),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: const [
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
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
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
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.15),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.3),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Center(
          child: Text('🦊', style: TextStyle(fontSize: 44)),
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
