import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'prompt_template.dart';

class SttProfile {
  const SttProfile({
    this.enabled = false,
    this.baseUrl = 'http://192.168.11.130:50060/v1',
    this.model = 'large-v3-turbo',
    this.language = '',
    this.apiKey = '',
  });
  final bool enabled;
  final String baseUrl, model, language, apiKey;
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'baseUrl': baseUrl,
    'model': model,
    'language': language,
    'apiKey': apiKey,
  };
}

class OptimizerProfile {
  const OptimizerProfile({
    this.enabled = false,
    this.baseUrl = '',
    this.model = '',
    this.apiKey = '',
    this.templateJson = '',
  });
  final bool enabled;
  final String baseUrl, model, apiKey, templateJson;
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
    'templateJson': templateJson,
  };
}

class AddonConfig {
  const AddonConfig({
    this.stt = const SttProfile(),
    this.optimizer = const OptimizerProfile(),
    this.workspaceToolsEnabled = false,
  });
  final SttProfile stt;
  final OptimizerProfile optimizer;
  final bool workspaceToolsEnabled;
  Map<String, Object> toJson() => {
    'version': 1,
    'stt': stt.toJson(),
    'optimizer': optimizer.toJson(),
    'workspaceToolsEnabled': workspaceToolsEnabled,
  };

  factory AddonConfig.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported configuration');
    }
    final s = json['stt'] as Map<String, dynamic>;
    final o = json['optimizer'] as Map<String, dynamic>;
    final config = AddonConfig(
      workspaceToolsEnabled: json['workspaceToolsEnabled'] as bool? ?? false,
      stt: SttProfile(
        enabled: s['enabled'] as bool,
        baseUrl: s['baseUrl'] as String,
        model: s['model'] as String,
        language: s['language'] as String,
        apiKey: s['apiKey'] as String,
      ),
      optimizer: OptimizerProfile(
        enabled: o['enabled'] as bool,
        baseUrl: o['baseUrl'] as String,
        model: o['model'] as String,
        apiKey: o['apiKey'] as String,
        templateJson: o['templateJson'] as String? ?? '',
      ),
    );
    config.validate();
    return config;
  }

  void validate() {
    if (stt.enabled) validateProfile(stt.baseUrl, stt.model);
    if (optimizer.enabled) validateProfile(optimizer.baseUrl, optimizer.model);
    validateApiKey(stt.apiKey);
    validateApiKey(optimizer.apiKey);
    validateLanguage(stt.language);
    if (optimizer.templateJson.isNotEmpty) {
      PromptTemplate.parse(optimizer.templateJson);
    }
  }
}

void validateProfile(String baseUrl, String model) {
  if (baseUrl.length > 2048 || _hasControlCharacters(baseUrl)) {
    throw const FormatException(
      'Base URL must contain up to 2048 characters without control characters.',
    );
  }
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Enter an HTTP or HTTPS base URL without credentials, query or fragment.',
    );
  }
  if (model.trim().isEmpty ||
      model.length > 256 ||
      _hasControlCharacters(model)) {
    throw const FormatException(
      'Enter a model name (up to 256 characters, without control characters).',
    );
  }
}

bool _hasControlCharacters(String value) =>
    RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value);

void validateApiKey(String key) {
  if (key.length > 8192 || _hasControlCharacters(key)) {
    throw const FormatException(
      'API key must contain up to 8192 characters without control characters.',
    );
  }
}

void validateLanguage(String language) {
  if (_hasControlCharacters(language) ||
      !RegExp(r'^[A-Za-z0-9_-]{0,32}$').hasMatch(language)) {
    throw const FormatException(
      'Language must contain up to 32 letters, digits, hyphens or underscores.',
    );
  }
}

abstract interface class AddonStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class _SecureAddonStorage implements AddonStorage {
  static const _key = 'pimic.optional.addons.v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Instantiate freely; secure storage is accessed only by explicit load/save.
class AddonConfigStore {
  AddonConfigStore({AddonStorage? storage}) : _storage = storage;
  AddonStorage? _storage;
  AddonStorage get _activeStorage => _storage ??= _SecureAddonStorage();
  Future<AddonConfig> load() async {
    try {
      final raw = await _activeStorage.read();
      if (raw == null) return const AddonConfig();
      return AddonConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Unreadable or corrupt settings must never opt a user into networking.
      return const AddonConfig();
    }
  }

  Future<void> save(AddonConfig config) async {
    config.validate();
    await _activeStorage.write(jsonEncode(config.toJson()));
  }
}
