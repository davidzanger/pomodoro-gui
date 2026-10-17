import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/service_protocol.dart';

void main() {
  test('maps timer statuses and phases to their user-facing labels', () {
    expect(TimerStatus.idle.label, 'Ready');
    expect(TimerStatus.running.label, 'In progress');
    expect(TimerStatus.paused.label, 'Paused');
    expect(TimerStatus.waiting.label, 'Waiting to start');
    expect(TimerPhase.pomodoro.label, 'Pomodoro');
    expect(TimerPhase.additionalPomodoro.label, 'Additional Pomodoro');
    expect(TimerPhase.shortBreak.label, 'Short break');
    expect(TimerPhase.longBreak.label, 'Long break');
  });

  test('calculates next session, remaining time, and clamped progress', () {
    TimerSnapshot snapshot(TimerPhase? phase) => TimerSnapshot(
      status: TimerStatus.running,
      phase: phase,
      elapsedSeconds: 30,
      durationSeconds: 120,
      completedPomodoros: 0,
    );

    expect(snapshot(null).nextSessionLabel, 'Pomodoro');
    expect(
      snapshot(TimerPhase.pomodoro).nextSessionLabel,
      'Additional Pomodoro',
    );
    expect(snapshot(TimerPhase.additionalPomodoro).nextSessionLabel, 'Break');
    expect(snapshot(TimerPhase.shortBreak).nextSessionLabel, 'Pomodoro');
    expect(snapshot(TimerPhase.longBreak).nextSessionLabel, 'Pomodoro');
    expect(
      snapshot(TimerPhase.pomodoro).remaining,
      const Duration(seconds: 90),
    );
    expect(snapshot(TimerPhase.pomodoro).progress, 0.25);
    expect(
      const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 200,
        durationSeconds: 120,
        completedPomodoros: 0,
      ).remaining,
      Duration.zero,
    );
    expect(
      const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: -10,
        durationSeconds: 120,
        completedPomodoros: 0,
      ).progress,
      0.0,
    );
    expect(
      const TimerSnapshot(
        status: TimerStatus.idle,
        phase: null,
        elapsedSeconds: 0,
        durationSeconds: 0,
        completedPomodoros: 0,
      ).progress,
      0.0,
    );
  });

  test('parses snapshots and rejects unknown enum values', () {
    expect(
      TimerSnapshot.fromJson({
        'status': 'paused',
        'phase': null,
        'elapsedSeconds': 5.9,
        'durationSeconds': 25,
        'completedPomodoros': 1,
      }).elapsedSeconds,
      5,
    );
    expect(
      () => TimerSnapshot.fromJson({
        'status': 'invalid',
        'phase': null,
        'elapsedSeconds': 0,
        'durationSeconds': 0,
        'completedPomodoros': 0,
      }),
      throwsArgumentError,
    );
    expect(
      () => TimerSnapshot.fromJson({
        'status': 'idle',
        'phase': 'invalid',
        'elapsedSeconds': 0,
        'durationSeconds': 0,
        'completedPomodoros': 0,
      }),
      throwsArgumentError,
    );
  });

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

  test('decodes notification and connection events', () {
    for (final type in ['ready', 'stopped']) {
      expect(
        ServiceEvent.decode(
          '{"protocolVersion":1,"event":{"type":"$type"}}',
        ).type,
        type,
      );
    }

    final awaitingStart = ServiceEvent.decode(
      '{"protocolVersion":1,"event":{"type":"awaitingStart",'
      '"phase":"longBreak","completedPomodoros":4}}',
    );
    expect(awaitingStart.type, 'awaitingStart');
    expect(awaitingStart.phase, TimerPhase.longBreak);
    expect(awaitingStart.completedPomodoros, 4);

    final completed = ServiceEvent.decode(
      '{"protocolVersion":1,"event":{"type":"phaseCompleted",'
      '"phase":"shortBreak","completedPomodoros":3}}',
    );
    expect(completed.type, 'phaseCompleted');
    expect(completed.phase, TimerPhase.shortBreak);
    expect(completed.completedPomodoros, 3);

    final error = ServiceEvent.decode(
      '{"protocolVersion":1,"event":{"type":"error","message":"failed"}}',
    );
    expect(error.type, 'error');
    expect(error.message, 'failed');
  });

  test('rejects malformed and unknown event payloads', () {
    expect(() => ServiceEvent.decode('{'), throwsFormatException);
    expect(
      () => ServiceEvent.decode(
        '{"protocolVersion":1,"event":{"type":"futureEvent"}}',
      ),
      throwsFormatException,
    );
    expect(
      () => ServiceEvent.decode(
        '{"protocolVersion":1,"event":{"type":"awaitingStart","phase":"other",'
        '"completedPomodoros":0}}',
      ),
      throwsArgumentError,
    );
  });
}
