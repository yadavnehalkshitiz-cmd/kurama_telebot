import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';

class ApiClient {
  final String baseUrl;
  final String apiKey;

  ApiClient({required this.baseUrl, required this.apiKey});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// Test the connection to the API server.
  Future<bool> healthCheck() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch video metadata from a URL.
  Future<VideoInfo> fetchInfo(String url) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/fetch-info'),
      headers: _headers,
      body: jsonEncode({'url': url}),
    );
    if (resp.statusCode != 200) {
      final err = _extractError(resp);
      throw ApiException(err);
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
    final resp = await http.post(
      Uri.parse('$baseUrl/api/download'),
      headers: _headers,
      body: jsonEncode({
        'url': url,
        'format': format,
        'video_quality': videoQuality,
        'audio_quality': audioQuality,
      }),
    );
    if (resp.statusCode != 200) {
      final err = _extractError(resp);
      throw ApiException(err);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['task_id'] as String;
  }

  /// Poll the status of a download task.
  Future<DownloadTask> getDownloadStatus(String taskId, {String? url}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/download/$taskId'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      final err = _extractError(resp);
      throw ApiException(err);
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DownloadTask.fromJson(data, taskId: taskId, url: url ?? '');
  }

  /// Download the completed file to the device and return the local path.
  Future<String> downloadFile(String taskId, {String? filename}) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/download/$taskId/file'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      final err = _extractError(resp);
      throw ApiException(err);
    }

    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/KuramaBot');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final name = filename ?? 'download_$taskId.mp4';
    final tempFile = File('${downloadDir.path}/$name.tmp');
    final finalFile = File('${downloadDir.path}/$name');
    
    // Write atomically to a temp file, then rename it
    await tempFile.writeAsBytes(resp.bodyBytes, flush: true);
    await tempFile.rename(finalFile.path);
    
    return finalFile.path;
  }

  /// Fetch the list of supported platforms.
  Future<List<Map<String, String>>> getPlatforms() async {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/platforms'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      return [];
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['platforms'] as List;
    return list
        .map((p) => {
              'name': p['name'] as String,
              'emoji': p['emoji'] as String,
            })
        .toList();
  }

  String _extractError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['detail'] as String? ?? 'Unknown error';
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
