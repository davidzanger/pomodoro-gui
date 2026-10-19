import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pomodoro_gui/app_settings.dart';
import 'package:pomodoro_gui/main.dart';
import 'package:pomodoro_gui/pomodoro_service.dart';
import 'package:pomodoro_gui/service_protocol.dart';

class _DecisionController extends TimerController {
  TimerSnapshot _snapshot = const TimerSnapshot(
    status: TimerStatus.idle,
    phase: null,
    elapsedSeconds: 0,
    durationSeconds: 0,
    completedPomodoros: 0,
  );

  @override
  TimerSnapshot get snapshot => _snapshot;
  @override
  bool get isConnected => true;
  @override
  String? get errorMessage => null;
  @override
  Future<TimerOptions> loadSettings() async => const TimerOptions();
  @override
  Future<void> connect() async {}
  @override
  Future<void> sendCommand(String type, {int? seconds}) async {}
  @override
  Future<bool> advanceToNextPhase() async => false;
  @override
  Future<void> updateSettings(TimerOptions options) async {}

  void showDecision() {
    _snapshot = const TimerSnapshot(
      status: TimerStatus.running,
      phase: TimerPhase.additionalPomodoro,
      elapsedSeconds: 10,
      durationSeconds: 300,
      completedPomodoros: 1,
      breakDecisionId: 1,
      breakDecisionPending: true,
    );
    notifyListeners();
  }
}

class _WindowsForeground {
  _WindowsForeground() {
    final user32 = DynamicLibrary.open('user32.dll');
    findWindow = user32
        .lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('FindWindowW');
    showWindow = user32
        .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
          'ShowWindow',
        );
    isIconic = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsIconic',
    );
    getForegroundWindow = user32
        .lookupFunction<IntPtr Function(), int Function()>(
          'GetForegroundWindow',
        );
    postMessage = user32
        .lookupFunction<
          Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)
        >('PostMessageW');
    getWindowLong = user32
        .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
          'GetWindowLongW',
        );
  }

  late final int Function(Pointer<Utf16>, Pointer<Utf16>) findWindow;
  late final int Function(int, int) showWindow;
  late final int Function(int) isIconic;
  late final int Function() getForegroundWindow;
  late final int Function(int, int, int, int) postMessage;
  late final int Function(int, int) getWindowLong;

  int appWindow() {
    final name = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final title = 'pomodoro_gui'.toNativeUtf16();
    try {
      return findWindow(name, title);
    } finally {
      calloc.free(name);
      calloc.free(title);
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('break decision restores and foregrounds the app after unlock', (
    tester,
  ) async {
    final windows = _WindowsForeground();
    final controller = _DecisionController();
    await tester.pumpWidget(
      PomodoroApp(
        controller: controller,
        settingsStore: MemoryAppSettingsStore(
          const AppSettings(autoStartOnLaunch: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hwnd = windows.appWindow();
    expect(hwnd, isNonZero);

    try {
      controller.showDecision();
      await tester.pumpAndSettle();
      expect(find.text('Take a break?'), findsOneWidget);
      expect(windows.getWindowLong(hwnd, -20) & 0x8, 0x8); // WS_EX_TOPMOST
      windows.showWindow(hwnd, 6);
      expect(windows.isIconic(hwnd), isNonZero);
      expect(windows.postMessage(hwnd, 0x02B1, 0x8, 0), isNonZero);
      await tester.pump(const Duration(milliseconds: 200));
      expect(windows.isIconic(hwnd), 0);
      expect(windows.getForegroundWindow(), hwnd);

      await tester.tap(find.text('Keep working'));
      await tester.pumpAndSettle();
      expect(windows.getWindowLong(hwnd, -20) & 0x8, 0);
    } finally {
      windows.showWindow(hwnd, 9); // SW_RESTORE
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !Platform.isWindows);
}
