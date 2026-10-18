import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pomodoro_gui/app_settings.dart';
import 'package:pomodoro_gui/main.dart';
import 'package:pomodoro_gui/pomodoro_service.dart';
import 'package:pomodoro_gui/service_protocol.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop controls advance a real Rust timer', (tester) async {
    final controller = PomodoroService();
    await tester.pumpWidget(
      PomodoroApp(
        controller: controller,
        settingsStore: MemoryAppSettingsStore(),
      ),
    );

    Future<void> waitFor(bool Function() condition) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        if (condition()) return;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('Timed out waiting for the Rust timer. ${controller.errorMessage}');
    }

    try {
      await waitFor(() => controller.isConnected);
      expect(find.byTooltip('Start session'), findsOneWidget);
      await tester.tap(find.byTooltip('Start session'));
      await waitFor(() => controller.snapshot.status == TimerStatus.running);
      expect(find.byTooltip('Pause timer'), findsOneWidget);
      final firstPhaseId = controller.snapshot.phaseId;
      expect(firstPhaseId, greaterThan(0));

      await tester.tap(find.byTooltip('Skip to next session'));
      await waitFor(() => controller.snapshot.phaseId > firstPhaseId);
      expect(controller.snapshot.completedPomodoros, 1);
      expect(controller.errorMessage, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !Platform.isWindows);
}
