import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers where each file was left off so reopening the player resumes
/// from the same spot instead of starting at 0:00.
class PlaybackPositionStore {
  static const _key = 'playback_positions';

  /// Load the saved position for [path] (0 when never played or stale).
  static Future<Duration> load(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return Duration.zero;
      final map = (jsonDecode(raw) as Map<String, dynamic>)
          .cast<String, dynamic>();
      final seconds = map[path];
      if (seconds is num && seconds > 0) {
        return Duration(seconds: seconds.toInt());
      }
    } catch (_) {}
    return Duration.zero;
  }

  static Future<void> save(String path, Duration position) async {
    if (position <= Duration.zero) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final map = (raw == null || raw.isEmpty)
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map<String, dynamic>).cast<String, dynamic>();
      map[path] = position.inSeconds;
      await prefs.setString(_key, jsonEncode(map));
    } catch (_) {}
  }

  static Future<void> clear(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final map = (jsonDecode(raw) as Map<String, dynamic>)
          .cast<String, dynamic>();
      if (map.remove(path) != null) {
        await prefs.setString(_key, jsonEncode(map));
      }
    } catch (_) {}
  }
}
