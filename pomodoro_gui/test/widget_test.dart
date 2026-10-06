// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:pomodoro_gui/main.dart';
import 'package:pomodoro_gui/pomodoro_service.dart';
import 'package:pomodoro_gui/service_protocol.dart';

class FakeTimerController extends TimerController {
  TimerSnapshot _snapshot = const TimerSnapshot(
    status: TimerStatus.idle,
    phase: null,
    elapsedSeconds: 0,
    durationSeconds: 0,
    completedPomodoros: 0,
  );
  final List<String> commands = [];

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
    if (type == 'start') {
      _snapshot = const TimerSnapshot(
        status: TimerStatus.running,
        phase: TimerPhase.pomodoro,
        elapsedSeconds: 0,
        durationSeconds: 1500,
        completedPomodoros: 0,
      );
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
}
