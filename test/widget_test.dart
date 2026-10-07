// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

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
  final List<String> commands = [];
  final List<int?> commandSeconds = [];

  @override
  TimerSnapshot get snapshot => _snapshot;

  @override
  bool get isConnected => true;

  @override
  String? get errorMessage => null;

  @override
  Future<void> connect() async {}

  @override
  Future<void> sendCommand(String type, {int? seconds}) async {
    commands.add(type);
    commandSeconds.add(seconds);
    if (type == 'skip' && skipResponseDelay > Duration.zero) {
      await Future<void>.delayed(skipResponseDelay);
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
    }
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
}
