import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';

/// Keys used in SharedPreferences.
const _kDownloadHistory = 'download_history';
const _kServerUrl = 'server_url';
const _kApiKey = 'api_key';
const _kInstallationUserId = 'installation_user_id';

/// Persists download history and server config to device storage.
class DownloadStorage {
  final SharedPreferences _prefs;

  DownloadStorage(this._prefs);

  // ── Download history ─────────────────────────────────

  List<DownloadTask> loadDownloads() {
    final raw = _prefs.getString(_kDownloadHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => DownloadTask.fromJson(e as Map<String, dynamic>))
          .where((t) => t.taskId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDownloads(List<DownloadTask> downloads) async {
    final list = downloads.map((t) => t.toJson()).toList();
    await _prefs.setString(_kDownloadHistory, jsonEncode(list));
  }

  // ── Server config ────────────────────────────────────

  String? loadServerUrl() => _prefs.getString(_kServerUrl);
  String? loadApiKey() => _prefs.getString(_kApiKey);

  Future<void> saveServerConfig(String url, String apiKey) async {
    await _prefs.setString(_kServerUrl, url);
    await _prefs.setString(_kApiKey, apiKey);
  }

  Future<void> clearServerConfig() async {
    await _prefs.remove(_kServerUrl);
    await _prefs.remove(_kApiKey);
  }

  Future<int> loadOrCreateUserId() async {
    final existing = _prefs.getInt(_kInstallationUserId);
    if (existing != null && existing > 0) return existing;
    final created = Random.secure().nextInt(0x7ffffffe) + 1;
    await _prefs.setInt(_kInstallationUserId, created);
    return created;
  }
}
