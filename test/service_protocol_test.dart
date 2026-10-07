import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/service_protocol.dart';

void main() {
  test('decodes timer state events from the Rust service', () {
    final event = ServiceEvent.decode(
      '{"protocolVersion":1,"event":{"type":"state",'
      '"status":"running","phase":"pomodoro",'
      '"elapsedSeconds":12,"durationSeconds":1500,'
      '"completedPomodoros":2}}',
    );

    expect(event.type, 'state');
    expect(event.state?.status, TimerStatus.running);
    expect(event.state?.phase, TimerPhase.pomodoro);
    expect(event.state?.elapsedSeconds, 12);
    expect(event.state?.durationSeconds, 1500);
    expect(event.state?.completedPomodoros, 2);
  });

  test('rejects an unsupported protocol version', () {
    expect(
      () =>
          ServiceEvent.decode('{"protocolVersion":2,"event":{"type":"ready"}}'),
      throwsFormatException,
    );
  });
}
