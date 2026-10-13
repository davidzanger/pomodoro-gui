import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/pomodoro_service.dart';
import 'package:pomodoro_gui/rust_bridge_initializer.dart';
import 'package:pomodoro_gui/service_protocol.dart';
import 'package:pomodoro_gui/src/rust/api/simple.dart' as rust_api;
import 'package:pomodoro_gui/src/rust/frb_generated.dart';

void main() {
  test('streams timer events from the in-process Rust service', () async {
    await rustBridgeInitializer.ensureInitialized();
    final settings =
        jsonDecode(await rust_api.loadTimerSettings()) as Map<String, dynamic>;
    expect(settings.containsKey('durationPomodoro'), isTrue);
    expect(settings.containsKey('themeMode'), isFalse);
    final service = await rust_api.createTimerService();
    final events = StreamIterator(service.events());
    var quitSent = false;

    try {
      expect(await events.moveNext(), isTrue);
      expect(ServiceEvent.decode(events.current).type, 'ready');
      expect(await events.moveNext(), isTrue);
      expect(ServiceEvent.decode(events.current).type, 'state');

      await service.updateSettings(
        durationPomodoro: 1,
        additionalDuration: 0,
        durationShortBreak: 0,
        durationLongBreak: 0,
        intervalLongBreak: 4,
        autoStartBreak: true,
        autoStartPomodoro: true,
      );
      await service.sendCommand(command: rust_api.TimerCommand.start);
      expect(await events.moveNext(), isTrue);
      final started = ServiceEvent.decode(events.current);
      expect(started.state?.durationSeconds, 60);

      quitSent = true;
      await service.sendCommand(command: rust_api.TimerCommand.quit);
      expect(await events.moveNext(), isTrue);
      expect(ServiceEvent.decode(events.current).type, 'stopped');
    } finally {
      if (!quitSent) {
        await service.sendCommand(command: rust_api.TimerCommand.quit);
      }
      await events.cancel();
    }
  }, skip: !Platform.isWindows);

  test('loads settings, connects, and saves through one Rust bridge', () async {
    final service = PomodoroService();
    final ready = Completer<void>();
    service.addListener(() {
      if (service.isConnected && !ready.isCompleted) ready.complete();
    });

    try {
      final settings = await service.loadSettings();
      expect(settings.durationPomodoro, greaterThan(0));

      await service.connect();
      await ready.future.timeout(const Duration(seconds: 10));
      expect(service.errorMessage, isNull);

      await service.updateSettings(settings);
      expect(service.errorMessage, isNull);
      expect(RustLib.instance.initialized, isTrue);
    } finally {
      service.dispose();
    }
  }, skip: !Platform.isWindows);
}
