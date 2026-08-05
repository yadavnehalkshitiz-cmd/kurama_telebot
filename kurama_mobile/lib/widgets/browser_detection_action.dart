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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFB02E),
                ),
              ),
              SizedBox(width: 10),
              Text('Checking this page...'),
            ],
          ),
        );
      case BrowserDetectionPhase.unsupported:
        return const _StatusCard(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 18, color: Color(0xFFB9B8C3)),
              SizedBox(width: 8),
              Text('No supported media found'),
            ],
          ),
        );
      case BrowserDetectionPhase.error:
        return _StatusCard(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 18),
              const SizedBox(width: 8),
              const Flexible(child: Text('Detection unavailable')),
              const SizedBox(width: 4),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        );
      case BrowserDetectionPhase.detected:
        return _DetectedMediaCard(
          title: state.info!.title,
          onDownload: onDownload,
        );
    }
  }
}

class _DetectedMediaCard extends StatelessWidget {
  final String title;
  final VoidCallback onDownload;

  const _DetectedMediaCard({
    required this.title,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0.94, end: 1),
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: _StatusCard(
        borderColor: const Color(0xFF3DDC97),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Color(0xFF3DDC97)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
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
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171720),
      elevation: 8,
      shadowColor: Colors.black54,
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
}
