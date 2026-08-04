import 'package:flutter/foundation.dart';
import '../models/download_task.dart';
import 'api_client.dart';
import 'download_storage.dart';

/// Central app state managed via Provider.
/// Automatically persists download history to device storage on every change.
class AppState extends ChangeNotifier {
  final DownloadStorage _storage;
  final int userId;
  ApiClient _client;
  final List<DownloadTask> _downloads = [];

  AppState(this._storage, this._client, {required this.userId}) {
    _loadPersistedState();
  }

  // ── Getters ──────────────────────────────────────────

  ApiClient get client => _client;
  List<DownloadTask> get downloads => List.unmodifiable(_downloads);

  // ── Initial load from disk ───────────────────────────

  void _loadPersistedState() {
    final saved = _storage.loadDownloads();
    if (saved.isNotEmpty) {
      _downloads.addAll(saved);
      notifyListeners();
    }
  }

  // ── Mutations (all auto-save) ────────────────────────

  void updateClient(ApiClient newClient) {
    _client = newClient;
    // Persist server config
    _storage.saveServerConfig(newClient.baseUrl, newClient.apiKey);
    notifyListeners();
  }

  void addDownload(DownloadTask task) {
    _downloads.insert(0, task);
    _persistDownloads();
    notifyListeners();
  }

  void updateDownload(String taskId, DownloadTask updated) {
    final idx = _downloads.indexWhere((t) => t.taskId == taskId);
    if (idx >= 0) {
      _downloads[idx] = updated;
      _persistDownloads();
      notifyListeners();
    }
  }

  void removeDownload(String taskId) {
    _downloads.removeWhere((t) => t.taskId == taskId);
    _persistDownloads();
    notifyListeners();
  }

  Future<void> moveToVault(String taskId, String vaultPath) async {
    final idx = _downloads.indexWhere((task) => task.taskId == taskId);
    if (idx < 0) return;
    final task = _downloads[idx];
    task
      ..isPrivate = true
      ..vaultPath = vaultPath
      ..localPath = null;
    await _persistDownloads();
    notifyListeners();
  }

  Future<void> restoreFromVault(String taskId, String localPath) async {
    final idx = _downloads.indexWhere((task) => task.taskId == taskId);
    if (idx < 0) return;
    final task = _downloads[idx];
    task
      ..isPrivate = false
      ..vaultPath = null
      ..localPath = localPath;
    await _persistDownloads();
    notifyListeners();
  }

  /// Save current download list to device storage.
  Future<void> _persistDownloads() async {
    try {
      await _storage.saveDownloads(_downloads);
    } catch (e) {
      debugPrint('[AppState] Failed to persist downloads: $e');
    }
  }
}
