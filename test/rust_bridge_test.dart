import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/service_protocol.dart';
import 'package:pomodoro_gui/src/rust/api/simple.dart' as rust_api;
import 'package:pomodoro_gui/src/rust/frb_generated.dart';

void main() {
  test('streams timer events from the in-process Rust service', () async {
    await RustLib.init();
    final service = await rust_api.createTimerService();
    final events = StreamIterator(service.events());
    var quitSent = false;

    try {
      expect(await events.moveNext(), isTrue);
      expect(ServiceEvent.decode(events.current).type, 'ready');
      expect(await events.moveNext(), isTrue);
      expect(ServiceEvent.decode(events.current).type, 'state');

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
}
