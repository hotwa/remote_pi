import 'package:flutter/material.dart';
import 'config.dart';
import 'api_client.dart';
import 'model_discovery.dart';

/// Opening this page is an explicit action; no app startup hook is required.
class AddonSettingsPage extends StatefulWidget {
  const AddonSettingsPage({super.key, required this.store, this.api});
  final AddonConfigStore store;
  final AddonApiClient? api;
  @override
  State<AddonSettingsPage> createState() => _AddonSettingsPageState();
}

class _AddonSettingsPageState extends State<AddonSettingsPage> {
  late final _api =
      widget.api ?? AddonApiClient(timeout: const Duration(seconds: 15));
  final _sttUrl = TextEditingController();
  final _sttModel = TextEditingController();
  final _language = TextEditingController();
  final _sttKey = TextEditingController();
  final _optimizerUrl = TextEditingController();
  final _optimizerModel = TextEditingController();
  final _optimizerKey = TextEditingController();
  bool _sttEnabled = false,
      _optimizerEnabled = false,
      _loading = true,
      _saving = false;
  String? _error;
  List<TextEditingController> get _controllers => [
    _sttUrl,
    _sttModel,
    _language,
    _sttKey,
    _optimizerUrl,
    _optimizerModel,
    _optimizerKey,
  ];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await widget.store.load();
    if (!mounted) return;
    _sttUrl.text = config.stt.baseUrl;
    _sttModel.text = config.stt.model;
    _language.text = config.stt.language;
    _sttKey.text = config.stt.apiKey;
    _optimizerUrl.text = config.optimizer.baseUrl;
    _optimizerModel.text = config.optimizer.model;
    _optimizerKey.text = config.optimizer.apiKey;
    setState(() {
      _sttEnabled = config.stt.enabled;
      _optimizerEnabled = config.optimizer.enabled;
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final config = AddonConfig(
      stt: SttProfile(
        enabled: _sttEnabled,
        baseUrl: _sttUrl.text.trim(),
        model: _sttModel.text.trim(),
        language: _language.text.trim(),
        apiKey: _sttKey.text.trim(),
      ),
      optimizer: OptimizerProfile(
        enabled: _optimizerEnabled,
        baseUrl: _optimizerUrl.text.trim(),
        model: _optimizerModel.text.trim(),
        apiKey: _optimizerKey.text.trim(),
      ),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(config);
      if (!mounted) return;
      Navigator.of(context).pop(config);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _saving = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save settings securely. Please try again.';
        _saving = false;
      });
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      controller: controller,
      enabled: !_saving,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: label == 'Base URL'
          ? TextInputType.url
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _section({
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> toggle,
    required List<Widget> fields,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(subtitle),
            value: enabled,
            onChanged: _saving ? null : toggle,
          ),
          ...fields,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Voice & draft tools')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Optional tools use your configured services. Both are off by default. Saving a URL does not enable a tool. Results return to your draft for review.',
              ),
              const SizedBox(height: 20),
              _section(
                title: 'Speech to text',
                subtitle:
                    'Transcribe a recording using an OpenAI-compatible API.',
                enabled: _sttEnabled,
                toggle: (value) => setState(() => _sttEnabled = value),
                fields: [
                  _field(
                    _sttUrl,
                    'Base URL',
                    hint: 'http://192.168.11.130:50060/v1',
                  ),
                  _field(_sttModel, 'Model', hint: 'large-v3-turbo'),
                  _field(
                    _language,
                    'Language (optional)',
                    hint: 'zh / en — leave blank for automatic detection',
                  ),
                  _field(_sttKey, 'API key (optional)', secret: true),
                  ModelDiscovery(
                    key: const Key('stt-model-discovery'),
                    baseUrl: _sttUrl,
                    apiKey: _sttKey,
                    model: _sttModel,
                    api: _api,
                    enabled: !_saving,
                  ),
                ],
              ),
              _section(
                title: 'Draft cleanup',
                subtitle: 'Polish draft wording using your language model.',
                enabled: _optimizerEnabled,
                toggle: (value) => setState(() => _optimizerEnabled = value),
                fields: [
                  _field(
                    _optimizerUrl,
                    'Base URL',
                    hint: 'http://your-server:port/v1',
                  ),
                  _field(_optimizerModel, 'Model'),
                  _field(_optimizerKey, 'API key (optional)', secret: true),
                  ModelDiscovery(
                    key: const Key('optimizer-model-discovery'),
                    baseUrl: _optimizerUrl,
                    apiKey: _optimizerKey,
                    model: _optimizerModel,
                    api: _api,
                    enabled: !_saving,
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save settings'),
              ),
              const SizedBox(height: 16),
              const Text(
                'API keys are stored in secure device storage. Requests begin only when you explicitly use a tool.',
              ),
            ],
          ),
  );
}
