import 'src/rust/frb_generated.dart';

/// Shares an in-progress bridge initialization across all Rust entry points.
class RustBridgeInitializer {
  RustBridgeInitializer(this._initialize, this._isInitialized);

  final Future<void> Function() _initialize;
  final bool Function() _isInitialized;
  Future<void>? _inProgress;

  Future<void> ensureInitialized() {
    if (_inProgress case final pending?) return pending;
    if (_isInitialized()) return Future<void>.value();
    return _inProgress = _runInitialization();
  }

  Future<void> _runInitialization() async {
    try {
      await _initialize();
    } finally {
      _inProgress = null;
    }
  }
}

final rustBridgeInitializer = RustBridgeInitializer(
  RustLib.init,
  () => RustLib.instance.initialized,
);
