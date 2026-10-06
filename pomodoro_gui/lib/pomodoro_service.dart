import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'service_protocol.dart';

abstract class TimerController extends ChangeNotifier {
  TimerSnapshot get snapshot;
  bool get isConnected;
  String? get errorMessage;
  Future<void> connect();
  Future<void> sendCommand(String type, {int? seconds});
}

class PomodoroService extends TimerController {
  PomodoroService({String? executablePath})
      : executablePath = executablePath ?? defaultExecutablePath();

  final String executablePath;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
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

  @override
  TimerSnapshot get snapshot => _snapshot;

  @override
  bool get isConnected => _isConnected;

  @override
  String? get errorMessage => _errorMessage;

  static String defaultExecutablePath() {
    final configured = Platform.environment['POMODORO_RUST_EXECUTABLE'];
    if (configured != null && configured.isNotEmpty) return configured;

    final debugExecutable = File(
      '${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}..'
      '${Platform.pathSeparator}pomodoro${Platform.pathSeparator}target'
      '${Platform.pathSeparator}debug${Platform.pathSeparator}'
      'locking-pomodoro-timer.exe',
    );
    if (debugExecutable.existsSync()) return debugExecutable.absolute.path;

    final appDirectory = File(Platform.resolvedExecutable).parent;
    final bundledExecutable = File(
      '${appDirectory.path}${Platform.pathSeparator}locking-pomodoro-timer.exe',
    );
    if (bundledExecutable.existsSync()) return bundledExecutable.path;

    return 'locking-pomodoro-timer.exe';
  }

  @override
  Future<void> connect() async {
    if (_process != null || _disposed) return;
    if (!Platform.isWindows) {
      _setError('The Rust service currently supports Windows only.');
      return;
    }

    try {
      final process = await Process.start(executablePath, ['--service']);
      _process = process;
      _stdoutSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleLine, onError: _handleStreamError);
      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('Rust service: $line'));
      unawaited(_watchExit(process));
    } on ProcessException catch (error) {
      _setError('Could not start the Rust timer: ${error.message}');
    } catch (error) {
      _setError('Could not connect to the Rust timer: $error');
    }
  }

  @override
  Future<void> sendCommand(String type, {int? seconds}) async {
    final process = _process;
    if (process == null || !_isConnected) return;

    final command = <String, Object>{'type': type};
    if (seconds != null) command['seconds'] = seconds;
    final request = <String, Object>{
      'protocolVersion': serviceProtocolVersion,
      'command': command,
    };
    try {
      process.stdin.writeln(jsonEncode(request));
      await process.stdin.flush();
    } on IOException catch (error) {
      _setError('Lost connection to the Rust timer: $error');
    }
  }

  void _handleLine(String line) {
    try {
      final event = ServiceEvent.decode(line);
      switch (event.type) {
        case 'ready':
          _isConnected = true;
          _errorMessage = null;
          notifyListeners();
        case 'state':
          _snapshot = event.state!;
          notifyListeners();
        case 'error':
          _setError(event.message ?? 'The Rust timer returned an error.');
        case 'stopped':
          _isConnected = false;
          notifyListeners();
        case 'awaitingStart':
        case 'phaseCompleted':
          break;
      }
    } on FormatException catch (error) {
      _setError('Could not read the Rust timer response: ${error.message}');
    } catch (error) {
      _setError('Received an invalid message from the Rust timer: $error');
    }
  }

  void _handleStreamError(Object error) {
    _setError('Could not read the Rust timer response: $error');
  }

  Future<void> _watchExit(Process process) async {
    final exitCode = await process.exitCode;
    if (_disposed || !identical(_process, process)) return;
    _process = null;
    _isConnected = false;
    if (exitCode != 0 && _errorMessage == null) {
      _errorMessage = 'The Rust timer exited with code $exitCode.';
    }
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final process = _process;
    if (process != null) {
      process.stdin.writeln(
        jsonEncode({
          'protocolVersion': serviceProtocolVersion,
          'command': {'type': 'quit'},
        }),
      );
      unawaited(process.stdin.close());
    }
    unawaited(_stdoutSubscription?.cancel());
    unawaited(_stderrSubscription?.cancel());
    super.dispose();
  }
}