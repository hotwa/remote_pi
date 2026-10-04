import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'config.dart';

class AddonException implements Exception {
  const AddonException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AddonCancellation {
  AddonCancellation({this.generation = 0});
  final int generation;
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}

class AddonApiClient {
  AddonApiClient({this.timeout = const Duration(seconds: 45)});
  final Duration timeout;
  static const maxWavBytes = 2000000;
  static const maxTextCharacters = 16000;
  static const maxResponseBytes = 262144;

  /// Explicit catalog lookup, independent of saved feature enable switches.
  /// Returning a catalog does not prove that a model supports STT or cleanup.
  Future<List<String>> listModels({
    required String baseUrl,
    String apiKey = '',
    AddonCancellation? cancellation,
  }) async {
    _validate(baseUrl, 'catalog', apiKey);
    final response = await _request(
      baseUrl,
      'models',
      apiKey,
      cancellation: cancellation,
    );
    final data = response['data'];
    if (data is! List || data.length > 256) {
      throw const AddonException('The service returned an invalid model list.');
    }
    final models = <String>{};
    for (final entry in data) {
      final id = entry is Map ? entry['id'] : null;
      if (id is! String ||
          id.trim().isEmpty ||
          id.length > 256 ||
          RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(id)) {
        throw const AddonException(
          'The service returned an invalid model list.',
        );
      }
      models.add(id.trim());
    }
    if (models.isEmpty) {
      throw const AddonException(
        'No models were listed. You can enter a model name manually.',
      );
    }
    return List.unmodifiable(models);
  }

  Future<String> transcribe({
    required SttProfile profile,
    required Uint8List wav,
    AddonCancellation? cancellation,
  }) async {
    if (!profile.enabled) {
      throw const AddonException('Transcription is disabled.');
    }
    _validate(profile.baseUrl, profile.model, profile.apiKey);
    _validateWav(wav);
    try {
      validateLanguage(profile.language);
    } on FormatException {
      throw const AddonException('Invalid language code.');
    }
    final boundary = 'pimic-${DateTime.now().microsecondsSinceEpoch}';
    final bytes = BytesBuilder();
    void field(String name, String value) {
      bytes.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n',
        ),
      );
    }

    field('model', profile.model.trim());
    if (profile.language.trim().isNotEmpty) {
      field('language', profile.language.trim());
    }
    field('response_format', 'json');
    bytes.add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="recording.wav"\r\nContent-Type: audio/wav\r\n\r\n',
      ),
    );
    bytes.add(wav);
    bytes.add(utf8.encode('\r\n--$boundary--\r\n'));
    final response = await _post(
      profile.baseUrl,
      'audio/transcriptions',
      profile.apiKey,
      'multipart/form-data; boundary=$boundary',
      bytes.takeBytes(),
      cancellation,
    );
    if (response['text'] is String &&
        (response['text'] as String).trim().isEmpty) {
      throw const AddonException(
        'No speech was detected. Check the microphone input and try again.',
      );
    }
    return _text(response['text']);
  }

  Future<String> optimize({
    required OptimizerProfile profile,
    required String text,
    AddonCancellation? cancellation,
  }) async {
    if (!profile.enabled) {
      throw const AddonException('Draft cleanup is disabled.');
    }
    _validate(profile.baseUrl, profile.model, profile.apiKey);
    if (text.trim().isEmpty || text.length > maxTextCharacters) {
      throw const AddonException('Draft must contain 1–16000 characters.');
    }
    if (isControlDraft(text)) return text;
    final response = await _post(
      profile.baseUrl,
      'chat/completions',
      profile.apiKey,
      'application/json',
      utf8.encode(
        jsonEncode({
          'model': profile.model.trim(),
          'stream': false,
          'max_tokens': 4096,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Clean up this draft for a coding assistant. Preserve the original intent, language and all technical details. Do not answer or execute the request, add requirements, or change control commands. Return only the cleaned draft.',
            },
            {'role': 'user', 'content': text},
          ],
        }),
      ),
      cancellation,
    );
    try {
      final choice = (response['choices'] as List).first as Map;
      final message = choice['message'] as Map;
      if (choice['finish_reason'] != 'stop' ||
          message['tool_calls'] != null ||
          message['function_call'] != null) {
        throw const AddonException(
          'The service returned an incomplete draft or a tool call.',
        );
      }
      final draft = _text(message['content']);
      if (isControlDraft(draft)) {
        throw const AddonException(
          'Draft cleanup changed the request into a control command.',
        );
      }
      return draft;
    } on AddonException {
      rethrow;
    } on Object {
      throw const AddonException('The service returned an invalid response.');
    }
  }

  void _validate(String url, String model, String key) {
    try {
      validateProfile(url, model);
    } on FormatException {
      throw const AddonException(
        'Check the service URL and model in settings.',
      );
    }
    try {
      validateApiKey(key);
    } on FormatException {
      throw const AddonException('Invalid API key.');
    }
  }

  static String _text(Object? value) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > maxTextCharacters) {
      throw const AddonException(
        'The service returned an invalid or oversized response.',
      );
    }
    return value.trim();
  }

  static void _validateWav(Uint8List wav) {
    if (wav.length < 44 || wav.length > maxWavBytes) {
      throw const AddonException('Record up to 60 seconds of audio.');
    }
    final data = ByteData.sublistView(wav);
    String tag(int start) =>
        String.fromCharCodes(wav.sublist(start, start + 4));
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WAVE' ||
        data.getUint32(4, Endian.little) != wav.length - 8) {
      throw const AddonException('Invalid WAV recording.');
    }
    bool format = false;
    int pcm = 0;
    int offset = 12;
    while (offset + 8 <= wav.length) {
      final size = data.getUint32(offset + 4, Endian.little);
      if (offset + 8 + size > wav.length) {
        throw const AddonException('Invalid WAV recording.');
      }
      if (tag(offset) == 'fmt ') {
        if (size < 16 ||
            data.getUint16(offset + 8, Endian.little) != 1 ||
            data.getUint16(offset + 10, Endian.little) != 1 ||
            data.getUint32(offset + 12, Endian.little) != 16000 ||
            data.getUint16(offset + 22, Endian.little) != 16) {
          throw const AddonException('Audio must be mono 16 kHz PCM16 WAV.');
        }
        format = true;
      }
      if (tag(offset) == 'data') pcm += size;
      offset += 8 + size + size % 2;
    }
    if (!format ||
        pcm == 0 ||
        pcm > 1920000 ||
        pcm.isOdd ||
        offset != wav.length) {
      throw const AddonException('Invalid WAV recording.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String baseUrl,
    String path,
    String key,
    String contentType,
    List<int> body,
    AddonCancellation? cancellation,
  ) => _request(
    baseUrl,
    path,
    key,
    method: 'POST',
    contentType: contentType,
    body: body,
    cancellation: cancellation,
  );

  Future<Map<String, dynamic>> _request(
    String baseUrl,
    String path,
    String key, {
    String method = 'GET',
    String? contentType,
    List<int>? body,
    AddonCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const AddonException('Request cancelled.');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    final cancelled = Completer<Map<String, dynamic>>();
    void cancel() {
      client.close(force: true);
      if (!cancelled.isCompleted) {
        cancelled.completeError(const AddonException('Request cancelled.'));
      }
    }

    cancellation?._listeners.add(cancel);
    try {
      final task = () async {
        final uri = Uri.parse(
          '${baseUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/$path',
        );
        final request = await client.openUrl(method, uri);
        request.followRedirects = false;
        if (contentType != null) {
          request.headers.set(HttpHeaders.contentTypeHeader, contentType);
        }
        if (key.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        }
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw AddonException(
            'Service request failed (HTTP ${response.statusCode}).',
          );
        }
        final bytes = BytesBuilder();
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const AddonException('The service response is too large.');
          }
          bytes.add(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        if (decoded is! Map<String, dynamic>) {
          throw const AddonException(
            'The service returned an invalid response.',
          );
        }
        return decoded;
      }();
      return await Future.any([task, cancelled.future]).timeout(timeout);
    } on AddonException {
      rethrow;
    } on TimeoutException {
      throw const AddonException('Service request timed out.');
    } on Object {
      throw const AddonException(
        'Unable to contact the service or read its response.',
      );
    } finally {
      cancellation?._listeners.remove(cancel);
      client.close(force: true);
    }
  }
}

/// Preserve spoken stop commands and gateway steering without model mediation.
bool isControlDraft(String text) {
  final message = text.trim();
  return RegExp(
        r'^(停止|停一下|取消|别执行了|別執行了|stop|cancel)(?:$|[\s。！？!?.,，；;：:、…])',
        caseSensitive: false,
      ).hasMatch(message) ||
      const ['等等', '先别', '先別', '改成', '不是这个', '不是這個'].any(message.startsWith);
}
