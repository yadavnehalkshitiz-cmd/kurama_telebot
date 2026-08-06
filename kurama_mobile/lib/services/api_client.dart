import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/video_info.dart';
import '../models/download_task.dart';
import '../models/user_profile.dart';

// ── Timeouts ────────────────────────────────────────────────
const _kShortTimeout = Duration(seconds: 12);
const _kFetchTimeout = Duration(seconds: 30);
const _kDownloadTimeout = Duration(minutes: 10);

/// Result of a connectivity + credential probe against the API server.
enum ConnectionStatus { connected, offline, invalidKey }

class ApiClient {
  final String baseUrl;
  final String apiKey;

  /// Tasks whose file transfer is currently in flight — guards the same
  /// `.part` file against concurrent writers (background worker + UI).
  static final Set<String> _inflightTransfers = {};

  ApiClient({required this.baseUrl, required this.apiKey});

  Map<String, String> get _headers => {
        'Authorization': 'Bearer \',
        'Content-Type': 'application/json',
      };

  /// Returns a copy with updated fields.
  ApiClient copyWith({String? baseUrl, String? apiKey}) {
    return ApiClient(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  /// Probe connectivity AND credential validity.
  ///
  /// `/api/health` alone returns 200 even with a wrong API key, which made
  /// the app look "connected" while every real request failed with 401.
  /// We therefore also probe the authenticated `/api/platforms` endpoint.
  ///
  /// Cloud hosts (render.com free tier) cold-start slowly and are throttled
  /// while waking up, so they get a longer window with a few retries instead
  /// of being reported as "offline".
  Future<ConnectionStatus> checkConnection() async {
    final slowHost = baseUrl.contains('onrender.com');
    final attempts = slowHost ? 3 : 1;
    final timeout = slowHost ? const Duration(seconds: 20) : _kShortTimeout;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final status = await _probeConnection(timeout);
      if (status != ConnectionStatus.offline || !slowHost) return status;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return ConnectionStatus.offline;
  }

  Future<ConnectionStatus> _probeConnection(Duration timeout) async {
    try {
      final health = await http
          .get(Uri.parse('$baseUrl/api/health'), headers: _headers)
          .timeout(timeout);
      if (health.statusCode != 200) return ConnectionStatus.offline;

      final probe = await http
          .get(Uri.parse('$baseUrl/api/platforms'), headers: _headers)
          .timeout(timeout);
      if (probe.statusCode == 200) return ConnectionStatus.connected;
      if (probe.statusCode == 401 || probe.statusCode == 403) {
        return ConnectionStatus.invalidKey;
      }
      return ConnectionStatus.offline;
    } catch (_) {
      return ConnectionStatus.offline;
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
      throw ApiException(
        'Server took too long to respond. Check your connection.',
        isTimeout: true,
      );
    });
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
    return VideoInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Start a download and return the task ID.
  Future<String> startDownload({
    required String url,
    required int userId,
    String format = 'video',
    String videoQuality = 'best',
    String audioQuality = 'best',
    String? thumbnail,
    bool playlist = false,
  }) async {
    final resp = await http
        .post(
      Uri.parse('$baseUrl/api/download'),
      headers: _headers,
      body: jsonEncode({
        'url': url,
        'user_id': userId,
        'format': format,
        'video_quality': videoQuality,
        'audio_quality': audioQuality,
        'thumbnail': thumbnail,
        'playlist': playlist,
      }),
    )
        .timeout(_kFetchTimeout, onTimeout: () {
      throw ApiException('Server did not respond. Try again.', isTimeout: true);
    });
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['task_id'] as String;
  }

  /// Re-run a failed download on the server (charges one credit).
  Future<void> retryDownload(String taskId) async {
    final resp = await http
        .post(
      Uri.parse('$baseUrl/api/download/$taskId/retry'),
      headers: _headers,
    )
        .timeout(_kFetchTimeout, onTimeout: () {
      throw ApiException('Server did not respond. Try again.', isTimeout: true);
    });
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
  }

  /// Live task status over Server-Sent Events. Falls back handled by the
  /// caller (plain polling) when streaming is unavailable.
  Stream<DownloadTask> getDownloadStatusStream(String taskId, {String? url}) {
    late final StreamController<DownloadTask> controller;
    StreamSubscription<String>? responseSub;
    var closed = false;

    void safeClose() {
      if (closed) return;
      closed = true;
      if (!controller.isClosed) controller.close();
    }

    void safeAdd(DownloadTask task) {
      if (!closed && !controller.isClosed) controller.add(task);
    }

    void safeAddError(Object error, [StackTrace? stack]) {
      if (closed || controller.isClosed) return;
      controller.addError(error, stack ?? StackTrace.current);
    }

    controller = StreamController<DownloadTask>(
      onListen: () async {
        try {
          final request = http.Request(
            'GET',
            Uri.parse('$baseUrl/api/download/$taskId/stream'),
          );
          _headers.forEach((k, v) => request.headers[k] = v);
          request.headers['Accept'] = 'text/event-stream';
          final streamed = await request.send().timeout(_kShortTimeout);
          if (streamed.statusCode != 200) {
            final body = await streamed.stream.bytesToString();
            safeAddError(ApiException(
              _extractBodyDetail(body, streamed.statusCode),
              statusCode: streamed.statusCode,
            ));
            safeClose();
            return;
          }
          var buffer = '';
          responseSub = streamed.stream.transform(utf8.decoder).listen(
                (chunk) {
                  buffer += chunk;
                  while (true) {
                    final frameEnd = buffer.indexOf('\n\n');
                    if (frameEnd < 0) break;
                    final frame = buffer.substring(0, frameEnd);
                    buffer = buffer.substring(frameEnd + 2);
                    String? event;
                    String? data;
                    for (final line in frame.split('\n')) {
                      if (line.startsWith('event: ')) {
                        event = line.substring(7);
                      } else if (line.startsWith('data: ')) {
                        data = line.substring(6);
                      }
                    }
                    if (data == null) continue;
                    try {
                      final map = jsonDecode(data) as Map<String, dynamic>;
                      if (event == 'error') {
                        safeAddError(ApiException(
                          map['detail']?.toString() ?? 'Server error',
                          statusCode: 404,
                        ));
                        safeClose();
                        continue;
                      }
                      safeAdd(
                        DownloadTask.fromJson(map,
                            taskId: taskId, url: url ?? ''),
                      );
                      if (event == 'done') safeClose();
                    } catch (_) {}
                  }
                },
                onDone: () => safeClose(),
                onError: (Object error, StackTrace stack) {
                  safeAddError(error, stack);
                  safeClose();
                },
              );
        } catch (error) {
          safeAddError(error);
          safeClose();
        }
      },
      onCancel: () async {
        // Cancel the underlying HTTP response so the socket isn't left open
        // until the server's stream deadline.
        await responseSub?.cancel();
        safeClose();
      },
    );
    return controller.stream;
  }

  String _extractBodyDetail(String body, int fallbackStatus) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['detail'] as String? ?? 'HTTP $fallbackStatus';
    } catch (_) {
      return 'HTTP $fallbackStatus';
    }
  }

  /// Poll the status of a download task.
  Future<DownloadTask> getDownloadStatus(String taskId, {String? url}) async {
    final resp = await http
        .get(
      Uri.parse('$baseUrl/api/download/$taskId'),
      headers: _headers,
    )
        .timeout(_kShortTimeout, onTimeout: () {
      throw ApiException('Server timed out while checking progress.',
          isTimeout: true);
    });
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return DownloadTask.fromJson(data, taskId: taskId, url: url ?? '');
  }

  /// Stream-download the completed file to device. Returns the local path.
  ///
  /// Interrupted transfers resume automatically: a partial file (`<name>.part`)
  /// is kept on disk across failures, and the next call continues from its byte
  /// offset with an HTTP `Range` request (206). If the server no longer has the
  /// file, ignores ranges, or the range is unsatisfiable (416), the download
  /// restarts cleanly from zero.
  ///
  /// A per-task in-flight guard prevents the background worker and the
  /// foreground screen from writing the same `.part` file concurrently.
  Future<String> downloadFile(String taskId, {String? filename}) async {
    if (!_inflightTransfers.add(taskId)) {
      throw ApiException('This download is already saving — one moment.');
    }
    try {
      return await _downloadFileImpl(taskId, filename: filename);
    } finally {
      _inflightTransfers.remove(taskId);
    }
  }

  Future<String> _downloadFileImpl(String taskId, {String? filename}) async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/KuramaBot');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    var name = (filename != null && filename.trim().isNotEmpty)
        ? sanitizeFilename(filename)
        : null;

    // The caller didn't know the real filename — probe the file with a 1-byte
    // Range request. One tiny response returns both the Content-Disposition
    // name and the total size (Content-Range), and confirms range support.
    if (name == null) {
      final probe = await _requestFile(taskId, rangeStart: 0, rangeEnd: 0);
      try {
        if (probe.statusCode != 206 && probe.statusCode != 200) {
          throw await _fileHttpError(probe);
        }
        name = sanitizeFilename(
          _filenameFromHeaders(probe.headers) ?? 'download_$taskId.mp4',
        );
      } finally {
        await probe.stream.drain<void>();
      }
    }

    final finalFile = File('${downloadDir.path}/$name');
    final partialFile = File('${downloadDir.path}/$name.part');

    // Resume loop: at most one clean restart (after a 416 or a range-ignored
    // 200), then either the transfer completes or an error is thrown.
    for (var attempt = 0; attempt < 2; attempt++) {
      final existing = await _fileSize(partialFile);
      final streamedResp = await _requestFile(
        taskId,
        rangeStart: existing > 0 ? existing : null,
      );

      final status = streamedResp.statusCode;
      if (status == 416) {
        // Our range start is past the end of the server file — the file was
        // replaced or the partial is already complete/corrupt. Wipe and retry.
        await streamedResp.stream.drain<void>();
        await _deleteIfExists(partialFile);
        continue;
      }
      if (status != 200 && status != 206) {
        throw await _fileHttpError(streamedResp);
      }
      if (status == 200 && existing > 0) {
        // Server ignored the Range header (older server) or the file changed:
        // truncate the partial and start over.
        await streamedResp.stream.drain<void>();
        await _deleteIfExists(partialFile);
        continue;
      }

      final resume = status == 206 && existing > 0;
      final sink = resume
          ? partialFile.openWrite(mode: FileMode.append)
          : partialFile.openWrite(mode: FileMode.write);

      // Stream bytes to disk — avoids loading the whole file into RAM. The
      // transfer is time-boxed and the subscription is cancelled on timeout so
      // the source connection is not left half-consumed. On failure the
      // partial file is KEPT so the next attempt resumes from this offset.
      final completer = Completer<void>();
      final subscription = streamedResp.stream.listen(
        sink.add,
        onDone: () => completer.complete(),
        onError: (Object error, StackTrace stack) =>
            completer.completeError(error, stack),
        cancelOnError: true,
      );
      try {
        await completer.future.timeout(_kDownloadTimeout, onTimeout: () async {
          // Await the cancel so no buffered events can hit the sink after we
          // close it below — otherwise "IOSink is closed" StateErrors leak
          // into the zone.
          await subscription.cancel();
          throw TimeoutException('Download timed out');
        });
      } on TimeoutException {
        await _closeQuietly(sink);
        throw ApiException(
          'Download interrupted — it will resume from where it stopped. '
          'Tap Save to retry.',
          isTimeout: true,
        );
      } catch (error) {
        await _closeQuietly(sink);
        if (error is ApiException) rethrow;
        // Mid-stream failure (e.g. dropped connection) — keep the partial so
        // the next attempt resumes instead of starting from zero.
        throw ApiException(
          'Download interrupted — it will resume from where it stopped. '
          'Tap Save to retry.',
        );
      }
      await _closeQuietly(sink);

      // Transfer complete: replace any stale full copy, then promote the
      // partial to the final filename.
      await _deleteIfExists(finalFile);
      await partialFile.rename(finalFile.path);
      return finalFile.path;
    }

    // Unreachable — the loop above always returns or throws.
    throw ApiException('Download failed — please try again.');
  }

  /// Sends the file GET with an optional single-range header.
  Future<http.StreamedResponse> _requestFile(
    String taskId, {
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/api/download/$taskId/file'),
    );
    _headers.forEach((k, v) => request.headers[k] = v);
    if (rangeStart != null) {
      request.headers['Range'] = rangeEnd != null
          ? 'bytes=$rangeStart-$rangeEnd'
          : 'bytes=$rangeStart-';
    }
    return request.send().timeout(
          _kDownloadTimeout,
          onTimeout: () => throw ApiException(
            'Download timed out. The file may be too large.',
            isTimeout: true,
          ),
        );
  }

  /// Builds a friendly ApiException from a non-success file response.
  Future<ApiException> _fileHttpError(http.StreamedResponse resp) async {
    String detail = 'HTTP ${resp.statusCode}';
    try {
      final body = await resp.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      detail = decoded['detail'] as String? ?? detail;
    } catch (_) {}
    return ApiException(detail, statusCode: resp.statusCode);
  }

  /// Byte size of [file], or 0 when it doesn't exist.
  Future<int> _fileSize(File file) async {
    try {
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  /// Best-effort removal of the on-disk `.part` resume file for a task.
  /// Called when a download entry is deleted so interrupted transfers don't
  /// leak storage. Uses the same sanitized name as [downloadFile].
  Future<void> deletePartialFile({
    required String taskId,
    String? filename,
  }) async {
    try {
      final name = (filename != null && filename.trim().isNotEmpty)
          ? sanitizeFilename(filename)
          : null;
      if (name == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final partial = File('${dir.path}/KuramaBot/$name.part');
      if (await partial.exists()) await partial.delete();
    } catch (_) {}
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
  Future<UserProfile> getUserProfile(int userId) async {
    final resp = await http
        .get(
      Uri.parse('$baseUrl/api/user/$userId/profile'),
      headers: _headers,
    )
        .timeout(_kFetchTimeout, onTimeout: () {
      throw ApiException('Server timed out while loading your profile.',
          isTimeout: true);
    });
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
    return UserProfile.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> claimDailyReward(int userId) async {
    final resp = await http
        .post(
      Uri.parse('$baseUrl/api/user/$userId/claim-daily'),
      headers: _headers,
    )
        .timeout(_kFetchTimeout, onTimeout: () {
      throw ApiException('Server timed out. Try again.', isTimeout: true);
    });
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Submit a payment transaction ID for admin verification.
  Future<Map<String, dynamic>> submitPayment({
    required int userId,
    required String txId,
    required String method,
    String? receiptPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/user/submit-payment'),
    )
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['user_id'] = userId.toString()
      ..fields['tx_id'] = txId
      ..fields['method'] = method;
    if (receiptPath != null && receiptPath.isNotEmpty) {
      request.files
          .add(await http.MultipartFile.fromPath('receipt', receiptPath));
    }
    final streamed = await request.send().timeout(_kFetchTimeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw ApiException(
        _extractError(resp),
        statusCode: resp.statusCode,
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  String _extractError(http.Response resp) {
    try {
      final body = jsonDecode(resp.body);
      if (body is Map<String, dynamic>) {
        final detail = body['detail'];
        if (detail is String) return detail;
        if (detail is Map && detail['message'] != null) {
          return detail['message'].toString();
        }
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] != null) {
            return first['msg'].toString();
          }
        }
      }
      return 'HTTP ${resp.statusCode}';
    } catch (_) {
      return 'HTTP ${resp.statusCode}';
    }
  }

  /// Best-effort filename from `Content-Disposition` on the file response.
  String? _filenameFromHeaders(Map<String, String> headers) {
    final disposition = headers['content-disposition'];
    if (disposition == null) return null;
    final match = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return sanitizeFilename(raw);
  }

  /// Strip path separators / control characters from a downloaded filename.
  static String sanitizeFilename(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[/\\]'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'download_${DateTime.now().millisecondsSinceEpoch}.mp4';
    }
    return cleaned;
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _closeQuietly(IOSink sink) async {
    try {
      await sink.close();
    } catch (_) {}
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isTimeout;

  ApiException(this.message, {this.statusCode, this.isTimeout = false});

  /// Server-side validation / unsupported media (e.g. bad URL).
  bool get isUnsupportedMedia => statusCode == 400;

  /// Wrong or missing API key.
  bool get isAuthError => statusCode == 401 || statusCode == 403;

  /// Free-tier credits exhausted.
  bool get isOutOfCredits => statusCode == 402;

  @override
  String toString() => message;
}



