import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'app_logging.dart';
import 'src/rust/api/simple.dart' as rust_api;
import 'src/rust/frb_generated.dart';
import 'service_protocol.dart';

abstract class TimerController extends ChangeNotifier {
  TimerSnapshot get snapshot;
  bool get isConnected;
  String? get errorMessage;
  Future<TimerOptions> loadSettings();
  Future<void> connect();
  Future<void> sendCommand(String type, {int? seconds});
  Future<void> updateSettings(TimerOptions options);
}

abstract interface class TimerServiceConnection {
  Stream<String> events();
  Future<void> sendCommand(String type, {int? seconds});
  Future<void> updateSettings(TimerOptions options);
}

typedef TimerServiceFactory = Future<TimerServiceConnection> Function();
typedef TimerSettingsLoader = Future<TimerOptions> Function();
typedef TimerSettingsSaver = Future<void> Function(TimerOptions options);

class PomodoroService extends TimerController {
  PomodoroService({
    TimerServiceFactory? serviceFactory,
    TimerSettingsLoader? settingsLoader,
    TimerSettingsSaver? settingsSaver,
    bool Function()? isSupportedPlatform,
  }) : _serviceFactory = serviceFactory ?? _createTimerService,
       _settingsLoader = settingsLoader ?? _loadRustTimerSettings,
       _settingsSaver = settingsSaver ?? _saveRustTimerSettings,
       _isSupportedPlatform =
           isSupportedPlatform ??
           (() => serviceFactory != null || Platform.isWindows);

  final TimerServiceFactory _serviceFactory;
  final TimerSettingsLoader _settingsLoader;
  final TimerSettingsSaver _settingsSaver;
  final bool Function() _isSupportedPlatform;
  TimerServiceConnection? _service;
  StreamSubscription<String>? _eventSubscription;
  TimerSnapshot _snapshot = const TimerSnapshot(
    status: TimerStatus.idle,
    phase: null,
    elapsedSeconds: 0,
    durationSeconds: 0,
    completedPomodoros: 0,
  );
  String? _errorMessage;
  bool _isConnected = false;
  bool _disposed = false;
  bool _connecting = false;
  TimerOptions? _pendingSettings;

  @override
  TimerSnapshot get snapshot => _snapshot;

  @override
  bool get isConnected => _isConnected;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<TimerOptions> loadSettings() => _settingsLoader();

  @override
  Future<void> connect() async {
    if (_service != null || _connecting || _disposed) return;
    if (!_isSupportedPlatform()) {
      _setError('The Rust service currently supports Windows only.');
      return;
    }
    _connecting = true;
    appTalker.info('Connecting to the Rust timer service.');

    try {
      final service = await _serviceFactory();
      if (_disposed) {
        await service.sendCommand('quit');
        return;
      }
      final subscription = service.events().listen(
        _handleLine,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
      );
      _service = service;
      _eventSubscription = subscription;
      appTalker.info('Connected to the Rust timer service.');
    } on Object catch (error) {
      _setError('Could not connect to the Rust timer: $error');
    } finally {
      _connecting = false;
    }
  }

  @override
  Future<void> sendCommand(String type, {int? seconds}) async {
    final service = _service;
    if (service == null || !_isConnected) return;

    try {
      final command = switch (type) {
        'start' || 'pause' || 'resume' || 'skip' || 'cancel' || 'quit' => type,
        _ => throw ArgumentError.value(type, 'type', 'Unknown timer command'),
      };
      appTalker.debug(
        seconds == null
            ? 'Sending timer command: $type.'
            : 'Sending timer command: $type ($seconds seconds).',
      );
      await service.sendCommand(command, seconds: seconds);
    } on Object catch (error) {
      _setError('Could not send a command to the Rust timer: $error');
    }
  }

  @override
  Future<void> updateSettings(TimerOptions options) async {
    options.validate();
    await _settingsSaver(options);
    final service = _service;
    if (service == null || !_isConnected) {
      _pendingSettings = options;
      return;
    }

    try {
      await service.updateSettings(options);
      appTalker.info('Updated Rust timer settings.');
    } on Object catch (error, stackTrace) {
      final message = 'Could not update Rust timer settings: $error';
      _setError(message);
      Error.throwWithStackTrace(StateError(message), stackTrace);
    }
  }

  void _handleLine(String line) {
    if (_disposed) return;
    try {
      final event = ServiceEvent.decode(line);
      switch (event.type) {
        case 'ready':
          _isConnected = true;
          _errorMessage = null;
          appTalker.info('Rust timer is ready.');
          notifyListeners();
          final pendingSettings = _pendingSettings;
          if (pendingSettings != null) {
            _pendingSettings = null;
            unawaited(_applyPendingSettings(pendingSettings));
          }
        case 'state':
          final previousSnapshot = _snapshot;
          _snapshot = event.state!;
          if (previousSnapshot.phase != _snapshot.phase ||
              previousSnapshot.status != _snapshot.status ||
              previousSnapshot.completedPomodoros !=
                  _snapshot.completedPomodoros) {
            appTalker.info(
              'Timer state: ${_snapshot.status.name}'
              '${_snapshot.phase == null ? '' : ' (${_snapshot.phase!.name})'}.',
            );
          }
          notifyListeners();
        case 'error':
          _setError(event.message ?? 'The Rust timer returned an error.');
        case 'stopped':
          _isConnected = false;
          appTalker.warning('Rust timer stopped.');
          notifyListeners();
        case 'awaitingStart':
          appTalker.info('Waiting for the next timer phase to be started.');
        case 'phaseCompleted':
          appTalker.info('Timer phase ${event.phase!.name} completed.');
          break;
      }
    } on FormatException catch (error) {
      _setError('Could not read the Rust timer response: ${error.message}');
    } catch (error) {
      _setError('Received an invalid message from the Rust timer: $error');
    }
  }

  void _handleStreamError(Object error) {
    if (_disposed) return;
    _setError('Could not read the Rust timer response: $error');
  }

  void _handleStreamDone() {
    if (_disposed) return;
    _isConnected = false;
    _errorMessage ??= 'The Rust timer stopped unexpectedly.';
    appTalker.warning('Rust timer event stream closed.');
    notifyListeners();
  }

  void _setError(String message) {
    if (_disposed) return;
    _errorMessage = message;
    appTalker.error(message);
    notifyListeners();
  }

  Future<void> _stopService(TimerServiceConnection service) async {
    try {
      await service.sendCommand('quit');
      await _eventSubscription?.asFuture<void>();
    } on Object catch (error) {
      appTalker.handle(error, StackTrace.current, 'Could not stop Rust timer.');
      await _eventSubscription?.cancel();
    }
  }

  Future<void> _applyPendingSettings(TimerOptions options) async {
    try {
      await _service?.updateSettings(options);
      appTalker.info('Applied saved Rust timer settings.');
    } on Object catch (error, stackTrace) {
      appTalker.handle(
        error,
        stackTrace,
        'Could not apply saved timer settings.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final service = _service;
    if (service != null) {
      unawaited(_stopService(service));
    } else {
      unawaited(_eventSubscription?.cancel());
    }
    super.dispose();
  }
}

Future<TimerServiceConnection> _createTimerService() async {
  await RustLib.init();
  return RustTimerServiceConnection(await rust_api.createTimerService());
}

Future<TimerOptions> _loadRustTimerSettings() async {
  await RustLib.init();
  return TimerOptions.decode(await rust_api.loadTimerSettings());
}

Future<void> _saveRustTimerSettings(TimerOptions options) async {
  await RustLib.init();
  await rust_api.saveTimerSettings(settingsJson: jsonEncode(options.toJson()));
}

@visibleForTesting
class RustTimerServiceConnection implements TimerServiceConnection {
  const RustTimerServiceConnection(this._service);

  final rust_api.TimerService _service;

  @override
  Stream<String> events() => _service.events();

  @override
  Future<void> sendCommand(String type, {int? seconds}) {
    final command = switch (type) {
      'start' => rust_api.TimerCommand.start,
      'pause' => rust_api.TimerCommand.pause,
      'resume' => rust_api.TimerCommand.resume,
      'skip' => rust_api.TimerCommand.skip,
      'cancel' => rust_api.TimerCommand.cancel,
      'quit' => rust_api.TimerCommand.quit,
      _ => throw ArgumentError.value(type, 'type', 'Unknown timer command'),
    };
    return _service.sendCommand(command: command, seconds: seconds);
  }

  @override
  Future<void> updateSettings(TimerOptions options) {
    return _service.updateSettings(
      durationPomodoro: options.durationPomodoro,
      additionalDuration: options.additionalDuration,
      durationShortBreak: options.durationShortBreak,
      durationLongBreak: options.durationLongBreak,
      intervalLongBreak: options.intervalLongBreak,
      autoStartBreak: options.autoStartBreak,
      autoStartPomodoro: options.autoStartPomodoro,
    );
  }
}
