import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/api_client.dart';

/// Shows a user-friendly banner when offline with quick 1-tap auto-reconnect options.
class ConnectionBanner extends StatefulWidget {
  final bool isConnected;
  final String serverUrl;
  final VoidCallback onTapSettings;

  const ConnectionBanner({
    super.key,
    required this.isConnected,
    required this.serverUrl,
    required this.onTapSettings,
  });

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}
class _ConnectionBannerState extends State<ConnectionBanner> {
  bool _isConnecting = false;

  Future<void> _switchToCloudServer() async {
    setState(() => _isConnecting = true);
    final cloudClient = ApiClient(
      baseUrl: 'https://kurama-telebot.onrender.com',
      apiKey: 'changeme-in-production',
    );
    final ok = await cloudClient.healthCheck();
    if (mounted) {
      setState(() => _isConnecting = false);
      if (ok) {
        context.read<AppState>().updateClient(cloudClient);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚡ Connected to Kurama Cloud Server!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Server unavailable. Check network or settings.'),
            backgroundColor: Color(0xFFD84315),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isConnected) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD84315).withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: const Color(0xFFD84315).withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: Color(0xFFFF8A65)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Server Offline',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.serverUrl.contains('onrender.com')
                      ? 'Waking up cloud server...'
                      : 'Connecting to ${widget.serverUrl}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!widget.serverUrl.contains('onrender.com')) ...[
            TextButton.icon(
              onPressed: _isConnecting ? null : _switchToCloudServer,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_queue_rounded, size: 14),
              label: const Text('Use Cloud', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF8A65),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            onPressed: widget.onTapSettings,
            icon: const Icon(Icons.settings_outlined, size: 18, color: Colors.white70),
            tooltip: 'Configure Server',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}
