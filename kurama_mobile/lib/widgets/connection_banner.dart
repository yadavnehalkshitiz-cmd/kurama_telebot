import 'package:flutter/material.dart';
import '../services/api_client.dart';

/// Shows a user-friendly banner when the server is unreachable or the API key
/// is rejected, with 1-tap recovery actions.
class ConnectionBanner extends StatelessWidget {
  final ConnectionStatus status;
  final String serverUrl;
  final VoidCallback onTapSettings;

  /// Opens server settings with the cloud URL prefilled (replaces the old
  /// "auto-connect" attempt that always failed with the placeholder key).
  final VoidCallback? onUseCloud;

  /// Re-runs the connection probe (handy during slow cloud cold starts).
  final VoidCallback? onRetry;

  const ConnectionBanner({
    super.key,
    required this.status,
    required this.serverUrl,
    required this.onTapSettings,
    this.onUseCloud,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    final isKeyRejected = status == ConnectionStatus.invalidKey;
    final accent =
        isKeyRejected ? const Color(0xFFFFB300) : const Color(0xFFD84315);
    final showUseCloud = !isKeyRejected &&
        !serverUrl.contains('onrender.com') &&
        onUseCloud != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isKeyRejected ? Icons.key_off_rounded : Icons.wifi_off_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isKeyRejected ? 'API key rejected' : 'Server Offline',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isKeyRejected
                      ? 'The server refused this key — update it in Settings'
                      : serverUrl.contains('onrender.com')
                          ? 'Cloud server is waking up — cold starts can take a minute'
                          : 'Connecting to $serverUrl',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onRetry != null && !isKeyRejected) ...[
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Retry connection',
              color: accent,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
            const SizedBox(width: 4),
          ],
          if (showUseCloud) ...[
            TextButton.icon(
              onPressed: onUseCloud,
              icon: const Icon(Icons.cloud_queue_rounded, size: 14),
              label: const Text('Use Cloud', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF8A65),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
            const SizedBox(width: 4),
          ],
          TextButton.icon(
            onPressed: onTapSettings,
            icon: Icon(
              isKeyRejected ? Icons.key_rounded : Icons.settings_outlined,
              size: 14,
            ),
            label: Text(
              isKeyRejected ? 'Fix Key' : 'Settings',
              style: const TextStyle(fontSize: 11),
            ),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}
