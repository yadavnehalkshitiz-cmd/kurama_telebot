import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/user_profile.dart';
import '../services/app_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _transactionController = TextEditingController();
  UserProfile? _profile;
  String _method = 'esewa';
  String? _receiptPath;
  bool _loading = true;
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _profile == null) _load();
  }

  @override
  void dispose() {
    _transactionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = context.read<AppState>();
      final profile = await state.client.getUserProfile(state.userId);
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      _show('Could not load profile: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claim() async {
    try {
      final state = context.read<AppState>();
      final result = await state.client.claimDailyReward(state.userId);
      _show('Reward claimed: +${result['reward']} credits');
      await _load();
    } catch (error) {
      _show(error.toString());
    }
  }

  Future<void> _pickReceipt() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && mounted) {
      setState(() => _receiptPath = result.files.single.path);
    }
  }

  Future<void> _submit() async {
    final transaction = _transactionController.text.trim();
    if (transaction.isEmpty) {
      _show('Enter your transaction or reference ID');
      return;
    }
    setState(() => _submitting = true);
    try {
      final state = context.read<AppState>();
      final result = await state.client.submitPayment(
        userId: state.userId,
        txId: transaction,
        method: _method,
        receiptPath: _receiptPath,
      );
      _transactionController.clear();
      setState(() => _receiptPath = null);
      _show(result['message']?.toString() ?? 'Submitted for review');
    } catch (error) {
      _show('Submission failed: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & membership'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading && profile == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  _identityCard(profile),
                  const SizedBox(height: 14),
                  _rewardCard(profile),
                  const SizedBox(height: 24),
                  Text('Upgrade securely',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 6),
                  Text(
                    profile == null
                        ? 'Payment configuration unavailable'
                        : 'NPR ${profile.monthlyPriceNpr} / month',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 14),
                  if (profile != null) _paymentCard(profile),
                ],
              ),
            ),
    );
  }

  Widget _identityCard(UserProfile? profile) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF392015), Color(0xFF17141D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x66FF6D2D)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Color(0x33FF6D2D),
              child: Icon(Icons.person_rounded,
                  size: 34, color: Color(0xFFFF8A50)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Kurama member',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    if (profile?.isPro ?? false) ...[
                      const SizedBox(width: 8),
                      const Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('PRO'),
                      ),
                    ],
                  ]),
                  Text('ID ${profile?.userId ?? 'offline'}',
                      style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            Column(children: [
              Text('${profile?.credits ?? '—'}',
                  style: const TextStyle(
                      color: Color(0xFFFFA060),
                      fontSize: 28,
                      fontWeight: FontWeight.w900)),
              const Text('credits', style: TextStyle(color: Colors.white54)),
            ]),
          ],
        ),
      );

  Widget _rewardCard(UserProfile? profile) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.redeem_rounded,
                size: 34, color: Color(0xFFFFA060)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Daily drop',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Text('+${profile?.dailyReward ?? 2} free credits every 24h',
                      style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            FilledButton(onPressed: profile == null ? null : _claim, child: const Text('Claim')),
          ]),
        ),
      );

  Widget _paymentCard(UserProfile profile) {
    final payload = profile.paymentMethods[_method] ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'esewa', label: Text('eSewa')),
                ButtonSegment(value: 'khalti', label: Text('Khalti')),
                ButtonSegment(value: 'bank', label: Text('Bank')),
              ],
              selected: {_method},
              onSelectionChanged: (selection) =>
                  setState(() => _method = selection.first),
            ),
            const SizedBox(height: 18),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(10),
                child: QrImageView(data: payload, size: 170),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(payload, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            TextField(
              controller: _transactionController,
              decoration: const InputDecoration(
                labelText: 'Transaction / reference ID',
                prefixIcon: Icon(Icons.receipt_long_rounded),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickReceipt,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(_receiptPath == null
                  ? 'Attach receipt (optional)'
                  : _receiptPath!.split(RegExp(r'[/\\]')).last),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Submitting…' : 'Submit for review'),
            ),
          ],
        ),
      ),
    );
  }
}
