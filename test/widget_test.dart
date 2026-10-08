// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'package:pomodoro_gui/main.dart';
import 'package:pomodoro_gui/pomodoro_service.dart';
import 'package:pomodoro_gui/service_protocol.dart';

class FakeTimerController extends TimerController {
  FakeTimerController({
    TimerSnapshot? initialSnapshot,
    this.skipResponseDelay = Duration.zero,
    this.waitAfterAdditionalPomodoro = false,
    this.connected = true,
    this.initialErrorMessage,
    this.skipDoesNotAdvance = false,
    this.skipError,
  }) : _snapshot =
           initialSnapshot ??
           const TimerSnapshot(
             status: TimerStatus.idle,
             phase: null,
             elapsedSeconds: 0,
             durationSeconds: 0,
             completedPomodoros: 0,
           );

  TimerSnapshot _snapshot;
  final Duration skipResponseDelay;
  final bool waitAfterAdditionalPomodoro;
  final bool connected;
  final String? initialErrorMessage;
  final bool skipDoesNotAdvance;
  final Object? skipError;
  final List<String> commands = [];
  final List<int?> commandSeconds = [];

  @override
  TimerSnapshot get snapshot => _snapshot;

  @override
  bool get isConnected => connected;

  @override
  String? get errorMessage => initialErrorMessage;

  @override
  Future<void> connect() async {}

  @override
  Future<void> sendCommand(String type, {int? seconds}) async {
    commands.add(type);
    commandSeconds.add(seconds);
    if (type == 'skip' && skipResponseDelay > Duration.zero) {
      await Future<void>.delayed(skipResponseDelay);
    }
    if (type == 'skip') {
      if (skipError case final error?) throw error;
    }
    if (type == 'start') {
      _snapshot = const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 0,
        durationSeconds: 1500,
        completedPomodoros: 0,
      );
      notifyListeners();
    } else if (type == 'skip') {
      if (skipDoesNotAdvance) return;
      _snapshot = switch (_snapshot.phase) {
        TimerPhase.pomodoro => const TimerSnapshot(
          status: TimerStatus.running,
          phase: TimerPhase.additionalPomodoro,
          elapsedSeconds: 0,
          durationSeconds: 300,
          completedPomodoros: 1,
        ),
        TimerPhase.additionalPomodoro => TimerSnapshot(
          status: waitAfterAdditionalPomodoro
              ? TimerStatus.waiting
              : TimerStatus.running,
          phase: TimerPhase.shortBreak,
          elapsedSeconds: 0,
          durationSeconds: 300,
          completedPomodoros: 1,
        ),
        _ => _snapshot,
      };
      notifyListeners();
    } else if (type == 'pause') {
      _snapshot = TimerSnapshot(
        status: TimerStatus.paused,
        phase: _snapshot.phase,
        elapsedSeconds: _snapshot.elapsedSeconds,
        durationSeconds: _snapshot.durationSeconds,
        completedPomodoros: _snapshot.completedPomodoros,
      );
      notifyListeners();
    } else if (type == 'resume') {
      _snapshot = TimerSnapshot(
        status: TimerStatus.running,
        phase: _snapshot.phase,
        elapsedSeconds: _snapshot.elapsedSeconds,
        durationSeconds: _snapshot.durationSeconds,
        completedPomodoros: _snapshot.completedPomodoros,
      );
      notifyListeners();
    } else if (type == 'cancel') {
      _snapshot = const TimerSnapshot(
        status: TimerStatus.idle,
        phase: null,
        elapsedSeconds: 0,
        durationSeconds: 0,
        completedPomodoros: 0,
      );
      notifyListeners();
    }
  }

  void update(TimerSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }
}

void main() {
  testWidgets('starts a Pomodoro through the timer controller', (tester) async {
    final controller = FakeTimerController();
    await tester.pumpWidget(PomodoroApp(controller: controller));

    expect(find.text('POMODORO'), findsOneWidget);
    expect(find.text('--:--'), findsOneWidget);
    await tester.tap(find.text('START SESSION'));
    await tester.pump();

    expect(controller.commands, ['start']);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.byTooltip('Pause timer'), findsOneWidget);
  });

  testWidgets('skips to the next phase and displays the upcoming session', (
    tester,
  ) async {
    final controller = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 300,
        durationSeconds: 1500,
        completedPomodoros: 0,
      ),
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));

    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Additional focus'), findsOneWidget);
    await tester.tap(find.byTooltip('Skip to next session'));
    await tester.pump();

    expect(controller.commands, ['skip']);
    expect(controller.commandSeconds, [1200]);
    expect(find.text('Additional focus'), findsOneWidget);
    expect(find.text('Break'), findsOneWidget);

    await tester.tap(find.byTooltip('Skip to next session'));
    await tester.pump();

    expect(controller.commands, ['skip', 'skip']);
    expect(controller.commandSeconds, [1200, 300]);
    expect(find.text('Short break'), findsOneWidget);
    expect(find.text('Pomodoro'), findsOneWidget);
  });

  testWidgets('rapid next-session skips use the latest running phase', (
    tester,
  ) async {
    final controller = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 300,
        durationSeconds: 1500,
        completedPomodoros: 0,
      ),
      skipResponseDelay: const Duration(seconds: 1),
      waitAfterAdditionalPomodoro: true,
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));

    final skipButton = find.byTooltip('Skip to next session');
    await tester.tap(skipButton);
    await tester.tap(skipButton);
    await tester.tap(skipButton);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(controller.commands, ['skip', 'skip']);
    expect(controller.commandSeconds, [1200, 300]);
    expect(controller.snapshot.phase, TimerPhase.shortBreak);
    expect(controller.snapshot.status, TimerStatus.waiting);
  });

  testWidgets('opens the in-app Talker log screen from the top bar', (
    tester,
  ) async {
    final controller = FakeTimerController();
    await tester.pumpWidget(PomodoroApp(controller: controller));

    await tester.tap(find.byTooltip('View logs'));
    await tester.pumpAndSettle();

    expect(find.byType(TalkerScreen), findsOneWidget);
  });

  testWidgets('pauses and resumes a running session', (tester) async {
    final controller = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 61,
        durationSeconds: 1500,
        completedPomodoros: 0,
      ),
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));

    expect(find.text('23:59'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause timer'));
    await tester.pump();
    expect(controller.snapshot.status, TimerStatus.paused);
    expect(find.byTooltip('Resume timer'), findsOneWidget);

    await tester.tap(find.byTooltip('Resume timer'));
    await tester.pump();
    expect(controller.snapshot.status, TimerStatus.running);
    await tester.tap(find.byTooltip('Skip ahead one minute'));
    await tester.pump();
    expect(controller.commands, ['pause', 'resume', 'skip']);
    expect(controller.commandSeconds, [null, null, 60]);
  });

  testWidgets('shows a connection error and disables controls while offline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FakeTimerController(
      connected: false,
      initialErrorMessage: 'Connection unavailable',
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));

    expect(find.text('Connection unavailable'), findsOneWidget);
    expect(find.text('CONNECTING TO RUST'), findsOneWidget);
    final startButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'START SESSION'),
    );
    expect(startButton.onPressed, isNull);
    await tester.tap(find.byTooltip('View logs'));
    await tester.pumpAndSettle();
    expect(find.byType(TalkerScreen), findsOneWidget);
    expect(controller.commands, isEmpty);
  });

  testWidgets('starts a waiting break and can cancel an inactive phase', (
    tester,
  ) async {
    final controller = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.waiting,
        phase: TimerPhase.shortBreak,
        elapsedSeconds: 0,
        durationSeconds: 300,
        completedPomodoros: 1,
      ),
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));

    expect(find.text('START BREAK'), findsOneWidget);
    await tester.tap(find.text('START BREAK'));
    await tester.pump();
    expect(controller.commands, ['start']);

    controller.update(
      const TimerSnapshot(
        status: TimerStatus.waiting,
        phase: TimerPhase.shortBreak,
        elapsedSeconds: 0,
        durationSeconds: 300,
        completedPomodoros: 1,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel session'));
    await tester.pump();
    expect(controller.commands, ['start', 'cancel']);
    expect(controller.snapshot.phase, isNull);
  });

  testWidgets('uses the compact layout and clamps a finished timer to zero', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.paused,
        phase: TimerPhase.longBreak,
        elapsedSeconds: 4000,
        durationSeconds: 1500,
        completedPomodoros: 4,
      ),
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('Long break'), findsOneWidget);
    expect(find.text('4 completed sessions'), findsOneWidget);
    expect(find.text('Pomodoro 5'), findsOneWidget);
  });

  testWidgets('shows feedback when skip fails or never advances', (
    tester,
  ) async {
    final controller = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 10,
        durationSeconds: 1500,
        completedPomodoros: 0,
      ),
      skipError: StateError('skip failed'),
    );
    await tester.pumpWidget(PomodoroApp(controller: controller));
    await tester.tap(find.byTooltip('Skip to next session'));
    await tester.pump();
    expect(
      find.text('The timer did not advance after skipping.'),
      findsOneWidget,
    );

    final silentController = FakeTimerController(
      initialSnapshot: const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 10,
        durationSeconds: 1500,
        completedPomodoros: 0,
      ),
      skipDoesNotAdvance: true,
    );
    await tester.pumpWidget(PomodoroApp(controller: silentController));
    await tester.tap(find.byTooltip('Skip to next session'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(
      find.text('The timer did not advance after skipping.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'recognizes duration, completion-count, and elapsed-time changes',
    (tester) async {
      final nextSnapshots = [
        const TimerSnapshot(
          status: TimerStatus.running,
          phase: TimerPhase.pomodoro,
          elapsedSeconds: 300,
          durationSeconds: 1400,
          completedPomodoros: 0,
        ),
        const TimerSnapshot(
          status: TimerStatus.running,
          phase: TimerPhase.pomodoro,
          elapsedSeconds: 300,
          durationSeconds: 1500,
          completedPomodoros: 1,
        ),
        const TimerSnapshot(
          status: TimerStatus.running,
          phase: TimerPhase.pomodoro,
          elapsedSeconds: 299,
          durationSeconds: 1500,
          completedPomodoros: 0,
        ),
      ];

      const initialSnapshot = TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 300,
        durationSeconds: 1500,
        completedPomodoros: 0,
      );
      final controller = FakeTimerController(
        initialSnapshot: initialSnapshot,
        skipResponseDelay: const Duration(milliseconds: 1),
        skipDoesNotAdvance: true,
      );
      await tester.pumpWidget(PomodoroApp(controller: controller));

      for (var index = 0; index < nextSnapshots.length; index++) {
        if (index > 0) {
          controller.update(initialSnapshot);
          await tester.pump();
        }
        await tester.tap(find.byTooltip('Skip to next session'));
        await tester.pump();
        controller.update(nextSnapshots[index]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(controller.commands, List.filled(index + 1, 'skip'));
      }
    },
  );
}
