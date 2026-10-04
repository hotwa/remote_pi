import 'package:app/domain/contracts/service.dart';
import 'package:flutter/foundation.dart';
import 'package:pimic_addons/pimic_addons.dart';

/// Thin host adapter: no audio, API requests or changes to Pi protocol here.
class PimicHost extends ChangeNotifier implements Service {
  PimicHost({AddonConfigStore? store}) : store = store ?? AddonConfigStore();

  final AddonConfigStore store;
  AddonConfig _config = const AddonConfig();
  Future<void>? _loading;
  bool _disposed = false;
  int _revision = 0;

  AddonConfig get config => _config;
  int get revision => _revision;
  bool get enabled => _config.stt.enabled || _config.optimizer.enabled;

  // Called on entering chat/tools, never from app bootstrap. Storage only.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final revision = _revision;
    final config = await store.load();
    if (_disposed || revision != _revision) return;
    _config = config;
    notifyListeners();
  }

  void acceptSaved(AddonConfig config) {
    if (_disposed) return;
    _revision++;
    _config = config;
    _loading = Future<void>.value();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
