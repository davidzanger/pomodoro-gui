import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'theme preference is persisted independently from timer options',
    () async {
      final store = SharedPreferencesAppSettingsStore();

      await store.save(
        const AppSettings(
          theme: AppThemePreference.dark,
          timerOptions: TimerOptions(durationPomodoro: 40),
        ),
      );
      final preferences = await SharedPreferences.getInstance();
      final loaded = await store.load();

      expect(preferences.getKeys(), {'appThemeMode'});
      expect(preferences.getString('appThemeMode'), 'dark');
      expect(loaded.theme, AppThemePreference.dark);
      expect(loaded.timerOptions.durationPomodoro, 25);
    },
  );

  test('reset removes the saved app theme preference', () async {
    final store = SharedPreferencesAppSettingsStore();
    await store.save(const AppSettings(theme: AppThemePreference.light));

    await store.reset(const AppSettings());

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('appThemeMode'), isFalse);
    expect((await store.load()).theme, AppThemePreference.system);
  });

  test('timer options encode and decode the Rust bridge shape', () {
    const options = TimerOptions(
      durationPomodoro: 30,
      additionalDuration: 0,
      durationShortBreak: 4,
      durationLongBreak: 12,
      intervalLongBreak: 0,
      autoStartBreak: false,
      autoStartPomodoro: true,
    );

    final decoded = TimerOptions.decode(options.encode());

    expect(decoded.durationPomodoro, 30);
    expect(decoded.additionalDuration, 0);
    expect(decoded.repeatAdditionalEnabled, isFalse);
    expect(decoded.breakDecisionEnabled, isFalse);
    expect(decoded.durationShortBreak, 4);
    expect(decoded.durationLongBreak, 12);
    expect(decoded.intervalLongBreak, 0);
    expect(decoded.autoStartBreak, isFalse);
    expect(decoded.autoStartPomodoro, isTrue);
    final json = jsonDecode(options.encode()) as Map<String, dynamic>;
    expect(json.containsKey('themeMode'), isFalse);
  });

  test('older settings enable repetition and the decision by default', () {
    final options = TimerOptions.decode(
      '{"durationPomodoro":25,"additionalDuration":5,'
      '"durationShortBreak":5,"durationLongBreak":15,'
      '"intervalLongBreak":4,"autoStartBreak":true,'
      '"autoStartPomodoro":true}',
    );
    expect(options.repeatAdditionalEnabled, isTrue);
    expect(options.breakDecisionEnabled, isTrue);
    final withoutQuestion = options.copyWith(askBeforeBreak: false);
    expect(withoutQuestion.repeatAdditionalEnabled, isTrue);
    expect(withoutQuestion.breakDecisionEnabled, isFalse);
  });

  test('actions and reminders round-trip in the Rust options format', () {
    const options = TimerOptions(
      endEventPomodoro: TimerEndEvent.sound('C:\\audio\\pomodoro.wav'),
      endEventAdditionalPomodoro: TimerEndEvent.sound(),
      intervalReminderAfterBreak: 12,
      eventReminderAfterBreak: TimerEndEvent.lockScreen(),
    );
    final decoded = TimerOptions.decode(options.encode());
    final json = jsonDecode(options.encode()) as Map<String, dynamic>;

    expect(decoded.endEventPomodoro.soundPath, 'C:\\audio\\pomodoro.wav');
    expect(decoded.endEventAdditionalPomodoro.kind, TimerEventKind.sound);
    expect(decoded.intervalReminderAfterBreak, 12);
    expect(decoded.eventReminderAfterBreak.kind, TimerEventKind.lockScreen);
    expect(json['endEventPomodoro'], {
      'sound': {'filepathSound': 'C:\\audio\\pomodoro.wav'},
    });
    expect(json['eventReminderAfterBreak'], 'lockScreen');
    expect(
      () => const TimerOptions(intervalReminderAfterBreak: -1).validate(),
      throwsFormatException,
    );
    expect(
      () => TimerEndEvent.decode({'sound': 'bad'}, 'event'),
      throwsFormatException,
    );
  });

  test('rejects invalid timer settings and malformed bridge responses', () {
    expect(
      () => const TimerOptions(intervalLongBreak: 0).validate(),
      returnsNormally,
    );
    expect(
      () => const TimerOptions(intervalLongBreak: -1).validate(),
      throwsFormatException,
    );
    expect(
      () => TimerOptions.decode(
        '{"durationPomodoro":0,"additionalDuration":0,'
        '"durationShortBreak":5,"durationLongBreak":15,'
        '"intervalLongBreak":4,"autoStartBreak":true,'
        '"autoStartPomodoro":true}',
      ),
      throwsFormatException,
    );
    expect(() => TimerOptions.decode('[]'), throwsFormatException);
  });
}
