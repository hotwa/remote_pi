import 'package:flutter/material.dart';
import 'api_client.dart';

/// Optional, explicit catalog lookup; never saves or enables a feature.
class ModelDiscovery extends StatefulWidget {
  const ModelDiscovery({
    super.key,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.api,
    this.enabled = true,
  });

  final TextEditingController baseUrl, apiKey, model;
  final AddonApiClient api;
  final bool enabled;

  @override
  State<ModelDiscovery> createState() => _ModelDiscoveryState();
}

class _ModelDiscoveryState extends State<ModelDiscovery>
    with WidgetsBindingObserver {
  AddonCancellation? _request;
  List<String> _models = const [];
  String? _status;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.baseUrl.addListener(_endpointChanged);
    widget.apiKey.addListener(_endpointChanged);
    widget.model.addListener(_modelChanged);
  }

  @override
  void didUpdateWidget(covariant ModelDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.apiKey != widget.apiKey ||
        oldWidget.model != widget.model) {
      oldWidget.baseUrl.removeListener(_endpointChanged);
      oldWidget.apiKey.removeListener(_endpointChanged);
      oldWidget.model.removeListener(_modelChanged);
      widget.baseUrl.addListener(_endpointChanged);
      widget.apiKey.addListener(_endpointChanged);
      widget.model.addListener(_modelChanged);
      _invalidate();
      _models = const [];
      _status = null;
    }
    if (!widget.enabled) _invalidate();
  }

  void _invalidate() {
    _request?.cancel();
    _request = null;
  }

  void _endpointChanged() {
    _invalidate();
    setState(() {
      _models = const [];
      _status = null;
      _failed = false;
    });
  }

  void _modelChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _request != null) _cancel();
  }

  void _cancel() {
    _invalidate();
    setState(() {
      _status = 'Model lookup cancelled. You can retry when ready.';
      _failed = false;
    });
  }

  Future<void> _loadModels() async {
    if (!widget.enabled || _request != null) return;
    FocusScope.of(context).unfocus();
    final cancellation = AddonCancellation();
    final watch = Stopwatch()..start();
    setState(() {
      _request = cancellation;
      _models = const [];
      _status = null;
      _failed = false;
    });
    try {
      final models = await widget.api.listModels(
        baseUrl: widget.baseUrl.text.trim(),
        apiKey: widget.apiKey.text.trim(),
        cancellation: cancellation,
      );
      if (!mounted || _request != cancellation) return;
      setState(() {
        _models = models;
        _status =
            '${models.length} models returned in ${watch.elapsedMilliseconds} ms. '
            'Choose one or keep your manual model name. This checks the catalog only.';
        _request = null;
      });
    } on Object catch (error) {
      if (!mounted || _request != cancellation) return;
      setState(() {
        _status =
            '${error is AddonException ? error.message : 'Unable to read the model list.'} '
            'If this service has no /models endpoint, enter the model manually.';
        _failed = true;
        _request = null;
      });
    } finally {
      watch.stop();
    }
  }

  @override
  void dispose() {
    _invalidate();
    WidgetsBinding.instance.removeObserver(this);
    widget.baseUrl.removeListener(_endpointChanged);
    widget.apiKey.removeListener(_endpointChanged);
    widget.model.removeListener(_modelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_models.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _models.contains(widget.model.text)
                ? widget.model.text
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Models returned by this service',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final id in _models)
                DropdownMenuItem(
                  value: id,
                  child: Text(id, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: widget.enabled
                ? (value) {
                    FocusScope.of(context).unfocus();
                    if (value != null) widget.model.text = value;
                  }
                : null,
          ),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: widget.enabled && _request == null
                  ? _loadModels
                  : null,
              icon: const Icon(Icons.refresh),
              label: Text(_request == null ? 'Load models' : 'Loading models…'),
            ),
            if (_request != null)
              TextButton(
                onPressed: _cancel,
                child: const Text('Cancel lookup'),
              ),
          ],
        ),
        Text(
          _status ??
              'Optional: reads /models only when tapped. Does not enable or save a tool.',
          style: _failed
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
      ],
    ),
  );
}
