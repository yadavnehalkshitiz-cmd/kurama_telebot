import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../services/app_state.dart';
import '../services/vault_cipher.dart';
import '../services/vault_key_store.dart';
import '../services/vault_service.dart';
import 'player_screen.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  late final VaultKeyStore _keys;
  late final VaultService _vault;
  bool _unlocked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keys = VaultKeyStore(FlutterSecureSecretStore());
    _vault = VaultService(VaultCipher(), _keys);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (mounted) setState(() => _unlocked = false);
    }
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    var authenticated = false;
    try {
      if (await _auth.isDeviceSupported()) {
        authenticated = await _auth.authenticate(
          localizedReason: 'Unlock your Kurama private vault',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
      }
    } on PlatformException {
      authenticated = false;
    }
    if (!authenticated && mounted) {
      authenticated = await _verifyPin();
    }
    if (mounted) {
      setState(() {
        _unlocked = authenticated;
        _busy = false;
      });
    }
  }

  Future<bool> _verifyPin() async {
    final hasPin = await _keys.hasPin();
    if (!mounted) return false;
    final first = await _askForPin(hasPin ? 'Enter vault PIN' : 'Create vault PIN');
    if (first == null) return false;
    if (hasPin) return _keys.verifyPin(first);
    final confirmation = await _askForPin('Confirm vault PIN');
    if (confirmation != first) {
      _message('PINs did not match');
      return false;
    }
    try {
      await _keys.setPin(first);
      return true;
    } on ArgumentError {
      _message('Use exactly six digits');
      return false;
    }
  }

  Future<String?> _askForPin(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '6-digit PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _play(DownloadTask task) async {
    File? temporaryFile;
    try {
      setState(() => _busy = true);
      temporaryFile = await _vault.openForPlayback(task);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            filePath: temporaryFile!.path,
            title: task.title,
            format: task.format,
            artist: task.format == 'audio' ? task.platform : null,
            artworkUrl: task.thumbnailUrl,
          ),
        ),
      );
    } catch (error) {
      _message('Could not open private media: $error');
    } finally {
      if (temporaryFile != null) await _vault.removePlaybackCopy(temporaryFile);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final items = context
        .watch<AppState>()
        .downloads
        .where((task) => task.isPrivate)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Vault'),
        actions: [
          if (_unlocked)
            IconButton(
              onPressed: () => setState(() => _unlocked = false),
              icon: const Icon(Icons.lock_rounded),
              tooltip: 'Lock now',
            ),
        ],
      ),
      body: !_unlocked ? _lockedView() : _vaultView(items),
    );
  }

  Widget _lockedView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint_rounded,
                  size: 76, color: Color(0xFFFF6D2D)),
              const SizedBox(height: 22),
              const Text('Vault locked',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Private files stay AES-256 encrypted until you unlock them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: const Text('Unlock securely'),
              ),
            ],
          ),
        ),
      );

  Widget _vaultView(List<DownloadTask> items) {
    if (items.isEmpty) {
      return const Center(child: Text('No private downloads yet'));
    }
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final task = items[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.enhanced_encryption_rounded,
                    color: Color(0xFFFF6D2D)),
                title: Text(task.title, maxLines: 1),
                subtitle: const Text('Encrypted on this device'),
                trailing: IconButton(
                  onPressed: _busy ? null : () => _play(task),
                  icon: const Icon(Icons.play_circle_fill_rounded),
                ),
              ),
            );
          },
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
