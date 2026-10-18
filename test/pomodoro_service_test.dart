import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/app_settings.dart';
import 'package:pomodoro_gui/pomodoro_service.dart';
import 'package:pomodoro_gui/service_protocol.dart';
import 'package:pomodoro_gui/src/rust/api/simple.dart' as rust_api;

class FakeGeneratedTimerService extends Fake implements rust_api.TimerService {
  final StreamController<String> eventController =
      StreamController<String>.broadcast();
  final List<Invocation> commands = [];

  @override
  Stream<String> events() => eventController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendCommand ||
        invocation.memberName == #updateSettings) {
      commands.add(invocation);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeTimerServiceConnection implements TimerServiceConnection {
  final StreamController<String> _events = StreamController<String>();
  final List<String> commands = [];
  final List<int?> commandSeconds = [];
  final List<TimerOptions> settingsUpdates = [];
  Object? sendError;
  Object? settingsError;
  bool closeOnQuit = true;

  Future<void> get done => _events.done;

  void emitEvent(Map<String, Object?> event) {
    _events.add(jsonEncode({'protocolVersion': 1, 'event': event}));
  }

  void emitLine(String line) => _events.add(line);

  void emitError(Object error) => _events.addError(error);

  Future<void> close() => _events.close();

  @override
  Stream<String> events() => _events.stream;

  @override
  Future<void> sendCommand(String type, {int? seconds}) async {
    commands.add(type);
    commandSeconds.add(seconds);
    if (sendError case final error?) throw error;
    if (type == 'quit' && closeOnQuit) unawaited(close());
  }

  @override
  Future<void> updateSettings(TimerOptions options) async {
    if (settingsError case final error?) throw error;
    settingsUpdates.add(options);
  }
}

void main() {
  test('maps controller command names to Rust bridge commands', () async {
    final generatedService = FakeGeneratedTimerService();
    final connection = RustTimerServiceConnection(generatedService);
    final eventStream = connection.events();

    for (final command in [
      'start',
      'pause',
      'resume',
      'skip',
      'nextPhase',
      'continueAdditional',
      'startBreak',
      'cancel',
      'quit',
    ]) {
      await connection.sendCommand(command, seconds: 42);
    }

    expect(eventStream, isA<Stream<String>>());
    expect(
      generatedService.commands.map(
        (invocation) => invocation.namedArguments[#command],
      ),
      [
        rust_api.TimerCommand.start,
        rust_api.TimerCommand.pause,
        rust_api.TimerCommand.resume,
        rust_api.TimerCommand.skip,
        rust_api.TimerCommand.nextPhase,
        rust_api.TimerCommand.continueAdditional,
        rust_api.TimerCommand.startBreak,
        rust_api.TimerCommand.cancel,
        rust_api.TimerCommand.quit,
      ],
    );
    expect(
      generatedService.commands.map(
        (invocation) => invocation.namedArguments[#seconds],
      ),
      everyElement(42),
    );
    const timerOptions = TimerOptions(durationPomodoro: 35);
    await connection.updateSettings(timerOptions);
    final update = generatedService.commands.last;
    expect(update.memberName, #updateSettings);
    expect(update.namedArguments[#durationPomodoro], 35);
    expect(update.namedArguments[#additionalDuration], 5);
    expect(update.namedArguments[#repeatAdditionalPomodoro], isTrue);
    expect(update.namedArguments[#askBeforeBreak], isTrue);
    expect(() => connection.sendCommand('other'), throwsArgumentError);
    await generatedService.eventController.close();
  });

  test('starts idle, connects once, and handles every event kind', () async {
    final connection = FakeTimerServiceConnection();
    var factoryCalls = 0;
    final service = PomodoroService(
      serviceFactory: () async {
        factoryCalls++;
        return connection;
      },
    );

    var notifications = 0;
    service.addListener(() => notifications++);

    expect(service.snapshot.status, TimerStatus.idle);
    expect(service.snapshot.phase, isNull);
    await service.connect();
    await service.connect();
    expect(factoryCalls, 1);
    expect(service.isConnected, isFalse);

    connection.emitEvent({'type': 'ready'});
    await Future<void>.delayed(Duration.zero);
    expect(service.isConnected, isTrue);
    expect(service.errorMessage, isNull);

    connection.emitEvent({
      'type': 'state',
      'status': 'running',
      'phase': 'pomodoro',
      'elapsedSeconds': 10,
      'durationSeconds': 1500,
      'completedPomodoros': 0,
    });
    await Future<void>.delayed(Duration.zero);
    expect(service.snapshot.status, TimerStatus.running);
    expect(service.snapshot.phase, TimerPhase.pomodoro);

    connection.emitEvent({
      'type': 'state',
      'status': 'running',
      'phase': 'pomodoro',
      'elapsedSeconds': 15,
      'durationSeconds': 1500,
      'completedPomodoros': 0,
    });
    connection.emitEvent({
      'type': 'awaitingStart',
      'phase': 'shortBreak',
      'completedPomodoros': 1,
    });
    connection.emitEvent({
      'type': 'phaseCompleted',
      'phase': 'pomodoro',
      'completedPomodoros': 1,
    });
    connection.emitEvent({'type': 'error', 'message': 'timer failed'});
    await Future<void>.delayed(Duration.zero);
    expect(service.errorMessage, 'timer failed');

    connection.emitEvent({'type': 'ready'});
    connection.emitEvent({'type': 'stopped'});
    await Future<void>.delayed(Duration.zero);
    expect(service.isConnected, isFalse);
    expect(notifications, greaterThanOrEqualTo(6));

    service.dispose();
    await connection.done;
  });

  test('queues settings until connected and reports update failures', () async {
    final connection = FakeTimerServiceConnection()..closeOnQuit = false;
    final persistedSettings = <TimerOptions>[];
    final service = PomodoroService(
      serviceFactory: () async => connection,
      settingsLoader: () async => const TimerOptions(durationPomodoro: 35),
      settingsSaver: (options) async => persistedSettings.add(options),
    );
    const options = TimerOptions(durationPomodoro: 40);

    expect((await service.loadSettings()).durationPomodoro, 35);
    await service.updateSettings(options);
    expect(persistedSettings, [options]);
    await service.connect();
    connection.emitEvent({'type': 'ready'});
    await Future<void>.delayed(Duration.zero);

    expect(connection.settingsUpdates, [options]);

    connection.settingsError = StateError('settings rejected');
    await expectLater(service.updateSettings(options), throwsStateError);
    expect(service.errorMessage, contains('settings rejected'));

    service.dispose();
    await connection.close();
    await connection.done;
  });

  test(
    'sends supported commands and reports invalid or failed sends',
    () async {
      final connection = FakeTimerServiceConnection()..closeOnQuit = false;
      final service = PomodoroService(serviceFactory: () async => connection);
      await service.connect();
      connection.emitEvent({'type': 'ready'});
      await Future<void>.delayed(Duration.zero);

      for (final command in [
        'start',
        'pause',
        'resume',
        'skip',
        'nextPhase',
        'cancel',
        'quit',
      ]) {
        await service.sendCommand(command, seconds: 60);
      }
      expect(connection.commands, [
        'start',
        'pause',
        'resume',
        'skip',
        'nextPhase',
        'cancel',
        'quit',
      ]);
      expect(connection.commandSeconds, everyElement(60));

      await service.sendCommand('invalid');
      expect(service.errorMessage, contains('Unknown timer command'));
      connection.sendError = StateError('send failed');
      await service.sendCommand('pause');
      expect(service.errorMessage, contains('send failed'));

      service.dispose();
      await connection.close();
      await connection.done;
    },
  );

  test('reports unsupported platforms without creating the service', () async {
    var factoryCalled = false;
    final service = PomodoroService(
      serviceFactory: () async {
        factoryCalled = true;
        return FakeTimerServiceConnection();
      },
      isSupportedPlatform: () => false,
    );

    await service.connect();

    expect(factoryCalled, isFalse);
    expect(service.errorMessage, contains('Windows only'));
    service.dispose();
  });

  test('surfaces connection failures and permits a later retry', () async {
    final connection = FakeTimerServiceConnection();
    var attempts = 0;
    final service = PomodoroService(
      serviceFactory: () async {
        attempts++;
        if (attempts == 1) throw StateError('not ready');
        return connection;
      },
    );

    await service.connect();
    expect(service.errorMessage, contains('not ready'));
    await service.connect();
    expect(attempts, 2);
    expect(service.errorMessage, contains('not ready'));

    connection.emitEvent({'type': 'ready'});
    await Future<void>.delayed(Duration.zero);
    expect(service.errorMessage, isNull);
    service.dispose();
    await connection.done;
  });

  test(
    'advances only after phase completion and serializes rapid requests',
    () async {
      final connection = FakeTimerServiceConnection()..closeOnQuit = false;
      final service = PomodoroService(serviceFactory: () async => connection);
      await service.connect();
      connection.emitEvent({'type': 'ready'});
      connection.emitEvent({
        'type': 'state',
        'status': 'running',
        'phase': 'pomodoro',
        'elapsedSeconds': 300,
        'durationSeconds': 1500,
        'completedPomodoros': 0,
      });
      await Future<void>.delayed(Duration.zero);

      final first = service.advanceToNextPhase();
      final second = service.advanceToNextPhase();
      await Future<void>.delayed(Duration.zero);
      expect(connection.commands, ['nextPhase']);
      connection.emitEvent({
        'type': 'state',
        'status': 'paused',
        'phase': 'pomodoro',
        'elapsedSeconds': 300,
        'durationSeconds': 1500,
        'completedPomodoros': 0,
      });
      await Future<void>.delayed(Duration.zero);
      expect(connection.commands, ['nextPhase']);
      connection.emitEvent({
        'type': 'phaseCompleted',
        'phase': 'pomodoro',
        'completedPomodoros': 1,
      });
      connection.emitEvent({
        'type': 'state',
        'status': 'running',
        'phase': 'additionalPomodoro',
        'elapsedSeconds': 0,
        'durationSeconds': 300,
        'completedPomodoros': 1,
      });
      expect(await first, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(connection.commands, ['nextPhase', 'nextPhase']);
      connection.emitEvent({
        'type': 'phaseCompleted',
        'phase': 'additionalPomodoro',
        'completedPomodoros': 1,
      });
      connection.emitEvent({
        'type': 'state',
        'status': 'waiting',
        'phase': 'shortBreak',
        'elapsedSeconds': 0,
        'durationSeconds': 300,
        'completedPomodoros': 1,
      });
      expect(await second, isTrue);
      service.dispose();
      await connection.close();
    },
  );

  test('restores saved timer options when live update fails', () async {
    final connection = FakeTimerServiceConnection()
      ..closeOnQuit = false
      ..settingsError = StateError('update failed');
    final saved = <TimerOptions>[];
    const previous = TimerOptions(durationPomodoro: 25);
    const requested = TimerOptions(durationPomodoro: 30);
    final service = PomodoroService(
      serviceFactory: () async => connection,
      settingsLoader: () async => previous,
      settingsSaver: (options) async => saved.add(options),
    );
    await service.connect();
    connection.emitEvent({'type': 'ready'});
    await Future<void>.delayed(Duration.zero);
    await expectLater(service.updateSettings(requested), throwsStateError);
    expect(saved, [requested, previous]);
    service.dispose();
    await connection.close();
  });

  test('does not send a phase advance while the timer is idle', () async {
    final connection = FakeTimerServiceConnection()..closeOnQuit = false;
    final service = PomodoroService(serviceFactory: () async => connection);
    await service.connect();
    connection.emitEvent({'type': 'ready'});
    await Future<void>.delayed(Duration.zero);

    expect(await service.advanceToNextPhase(), isFalse);
    expect(connection.commands, isEmpty);
    service.dispose();
    await connection.close();
  });

  test('reports a Rust error during phase advance', () async {
    final connection = FakeTimerServiceConnection()..closeOnQuit = false;
    final service = PomodoroService(serviceFactory: () async => connection);
    await service.connect();
    connection.emitEvent({'type': 'ready'});
    connection.emitEvent({
      'type': 'state',
      'status': 'running',
      'phase': 'pomodoro',
      'elapsedSeconds': 10,
      'durationSeconds': 1500,
      'completedPomodoros': 0,
    });
    await Future<void>.delayed(Duration.zero);

    final advance = service.advanceToNextPhase();
    await Future<void>.delayed(Duration.zero);
    connection.emitEvent({'type': 'error', 'message': 'advance refused'});
    await expectLater(advance, throwsStateError);
    expect(service.errorMessage, contains('advance refused'));
    service.dispose();
    await connection.close();
  });

  test('reports when saved timer options cannot be restored', () async {
    final connection = FakeTimerServiceConnection()
      ..closeOnQuit = false
      ..settingsError = StateError('update failed');
    const previous = TimerOptions(durationPomodoro: 25);
    const requested = TimerOptions(durationPomodoro: 30);
    var saves = 0;
    final service = PomodoroService(
      serviceFactory: () async => connection,
      settingsLoader: () async => previous,
      settingsSaver: (options) async {
        saves++;
        if (saves == 2) throw StateError('restore failed');
      },
    );
    await service.connect();
    connection.emitEvent({'type': 'ready'});
    await Future<void>.delayed(Duration.zero);

    await expectLater(service.updateSettings(requested), throwsStateError);
    expect(saves, 2);
    expect(service.errorMessage, contains('restore failed'));
    service.dispose();
    await connection.close();
  });

  test(
    'failed phase advance reports the send error and discards queued skips',
    () async {
      final connection = FakeTimerServiceConnection()..closeOnQuit = false;
      final service = PomodoroService(serviceFactory: () async => connection);
      await service.connect();
      connection.emitEvent({'type': 'ready'});
      connection.emitEvent({
        'type': 'state',
        'status': 'running',
        'phase': 'pomodoro',
        'elapsedSeconds': 10,
        'durationSeconds': 1500,
        'completedPomodoros': 0,
      });
      await Future<void>.delayed(Duration.zero);
      connection.sendError = StateError('send failed');
      final first = service.advanceToNextPhase();
      final second = service.advanceToNextPhase();
      await expectLater(first, throwsStateError);
      expect(await second, isFalse);
      expect(connection.commands, ['nextPhase']);
      expect(service.errorMessage, contains('send failed'));
      connection.sendError = null;
      service.dispose();
      await connection.close();
    },
  );

  test('reports malformed events and asynchronous stream errors', () async {
    final connection = FakeTimerServiceConnection();
    final service = PomodoroService(serviceFactory: () async => connection);
    await service.connect();

    connection.emitLine('{');
    await Future<void>.delayed(Duration.zero);
    expect(service.errorMessage, contains('Could not read'));

    connection.emitLine(
      '{"protocolVersion":1,"event":{"type":"state","status":4}}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.errorMessage, contains('invalid message'));

    connection.emitError(StateError('stream failed'));
    await Future<void>.delayed(Duration.zero);
    expect(service.errorMessage, contains('stream failed'));

    service.dispose();
    await connection.done;
  });

  test(
    'reports unexpected stream completion and stops cleanly on dispose',
    () async {
      final connection = FakeTimerServiceConnection()..closeOnQuit = false;
      final service = PomodoroService(serviceFactory: () async => connection);
      await service.connect();
      connection.emitEvent({'type': 'ready'});
      await Future<void>.delayed(Duration.zero);
      await connection.close();
      expect(service.errorMessage, 'The Rust timer stopped unexpectedly.');
      expect(service.isConnected, isFalse);
      service.dispose();

      final stoppingConnection = FakeTimerServiceConnection();
      final stoppingService = PomodoroService(
        serviceFactory: () async => stoppingConnection,
      );
      await stoppingService.connect();
      stoppingConnection.emitEvent({'type': 'ready'});
      await Future<void>.delayed(Duration.zero);
      stoppingService.dispose();
      await stoppingConnection.done;
      expect(stoppingConnection.commands, ['quit']);
    },
  );

  test(
    'quits a service created after the controller has been disposed',
    () async {
      final created = Completer<FakeTimerServiceConnection>();
      final service = PomodoroService(serviceFactory: () => created.future);
      final connecting = service.connect();
      service.dispose();

      final connection = FakeTimerServiceConnection();
      created.complete(connection);
      await connecting;

      expect(connection.commands, ['quit']);
    },
  );
}
