import 'package:flutter/material.dart';

/// Shows a persistent banner when the app cannot reach the server.
class ConnectionBanner extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (isConnected) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTapSettings,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFC62828),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cannot reach server — tap to configure',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.settings, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}
