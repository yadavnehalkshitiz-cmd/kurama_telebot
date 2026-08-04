import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';

// ── Timeouts ────────────────────────────────────────────────
const _kShortTimeout = Duration(seconds: 10);
const _kFetchTimeout = Duration(seconds: 30);
const _kDownloadTimeout = Duration(minutes: 10);

class ApiClient {
  final String baseUrl;
  final String apiKey;

  ApiClient({required this.baseUrl, required this.apiKey});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// Returns a copy with updated fields.
  ApiClient copyWith({String? baseUrl, String? apiKey}) {
    return ApiClient(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  /// Test the connection to the API server.
  Future<bool> healthCheck() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/health'), headers: _headers)
          .timeout(_kShortTimeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch video metadata from a URL.
  Future<VideoInfo> fetchInfo(String url) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/fetch-info'),
          headers: _headers,
          body: jsonEncode({'url': url}),
        )
        .timeout(_kFetchTimeout, onTimeout: () {
      throw ApiException('Server took too long to respond. Check your connection.');
    });
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp));
    }
    return VideoInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Start a download and return the task ID.
  Future<String> startDownload({
    required String url,
    String format = 'video',
    String videoQuality = 'best',
    String audioQuality = 'best',
  }) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/download'),
          headers: _headers,
          body: jsonEncode({
            'url': url,
            'format': format,
            'video_quality': videoQuality,
            'audio_quality': audioQuality,
          }),
        )
        .timeout(_kFetchTimeout, onTimeout: () {
      throw ApiException('Server did not respond. Try again.');
    });
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['task_id'] as String;
  }

  /// Poll the status of a download task.
  Future<DownloadTask> getDownloadStatus(String taskId, {String? url}) async {
    final resp = await http
        .get(
          Uri.parse('$baseUrl/api/download/$taskId'),
          headers: _headers,
        )
        .timeout(_kShortTimeout);
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp));
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DownloadTask.fromJson(data, taskId: taskId, url: url ?? '');
  }

  /// Stream-download the completed file to device. Returns the local path.
  Future<String> downloadFile(String taskId, {String? filename}) async {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/api/download/$taskId/file'),
    );
    _headers.forEach((k, v) => request.headers[k] = v);

    final streamedResp = await request
        .send()
        .timeout(_kDownloadTimeout, onTimeout: () {
      throw ApiException('Download timed out. The file may be too large.');
    });

    if (streamedResp.statusCode != 200) {
      final body = await streamedResp.stream.bytesToString();
      String detail = 'HTTP ${streamedResp.statusCode}';
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        detail = decoded['detail'] as String? ?? detail;
      } catch (_) {}
      throw ApiException(detail);
    }

    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/KuramaBot');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final name = filename ?? 'download_$taskId.mp4';
    final tempFile = File('${downloadDir.path}/$name.tmp');
    final finalFile = File('${downloadDir.path}/$name');

    // Stream bytes to disk — avoids loading the whole file into RAM
    final sink = tempFile.openWrite();
    try {
      await streamedResp.stream.pipe(sink);
    } finally {
      await sink.close();
    }

    await tempFile.rename(finalFile.path);
    return finalFile.path;
  }

  /// Fetch the list of supported platforms.
  Future<List<Map<String, String>>> getPlatforms() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/platforms'), headers: _headers)
          .timeout(_kShortTimeout);
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['platforms'] as List;
      return list
          .map((p) => {
                'name': p['name'] as String,
                'emoji': p['emoji'] as String,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch user profile (credits balance & subscription status).
  Future<Map<String, dynamic>> getUserProfile(int userId) async {
    final resp = await http
        .get(
          Uri.parse('$baseUrl/api/user/$userId/profile'),
          headers: _headers,
        )
        .timeout(_kFetchTimeout);
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp));
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Submit a payment transaction ID for admin verification.
  Future<Map<String, dynamic>> submitPayment({
    required int userId,
    required String txId,
  }) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl/api/user/submit_payment'),
          headers: _headers,
          body: jsonEncode({'user_id': userId, 'tx_id': txId}),
        )
        .timeout(_kFetchTimeout);
    if (resp.statusCode != 200) {
      throw ApiException(_extractError(resp));
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  String _extractError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['detail'] as String? ?? 'HTTP ${resp.statusCode}';
    } catch (_) {
      return 'HTTP ${resp.statusCode}';
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
