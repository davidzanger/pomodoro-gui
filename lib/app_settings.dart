import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

enum TimerEventKind { sound, lockScreen }

class TimerEndEvent {
  const TimerEndEvent.sound([this.soundPath = ''])
    : kind = TimerEventKind.sound;
  const TimerEndEvent.lockScreen()
    : kind = TimerEventKind.lockScreen,
      soundPath = '';

  final TimerEventKind kind;
  final String soundPath;

  TimerEndEvent copyWith({TimerEventKind? kind, String? soundPath}) {
    final nextKind = kind ?? this.kind;
    return nextKind == TimerEventKind.lockScreen
        ? const TimerEndEvent.lockScreen()
        : TimerEndEvent.sound(soundPath ?? this.soundPath);
  }

  Object toJson() => kind == TimerEventKind.lockScreen
      ? 'lockScreen'
      : {
          'sound': {'filepathSound': soundPath},
        };

  factory TimerEndEvent.decode(Object? value, String key) {
    if (value == 'lockScreen') return const TimerEndEvent.lockScreen();
    if (value case {'sound': {'filepathSound': String path}}) {
      return TimerEndEvent.sound(path);
    }
    throw FormatException('The "$key" event must be a sound or screen lock.');
  }
}

class TimerOptions {
  const TimerOptions({
    this.durationPomodoro = 25,
    this.additionalDuration = 5,
    this.durationShortBreak = 5,
    this.durationLongBreak = 15,
    this.intervalLongBreak = 4,
    this.autoStartBreak = true,
    this.autoStartPomodoro = true,
    this.endEventPomodoro = const TimerEndEvent.sound(),
    this.endEventAdditionalPomodoro = const TimerEndEvent.lockScreen(),
    this.intervalReminderAfterBreak = 5,
    this.eventReminderAfterBreak = const TimerEndEvent.sound(),
  });

  final int durationPomodoro;
  final int additionalDuration;
  final int durationShortBreak;
  final int durationLongBreak;
  final int intervalLongBreak;
  final bool autoStartBreak;
  final bool autoStartPomodoro;
  final TimerEndEvent endEventPomodoro;
  final TimerEndEvent endEventAdditionalPomodoro;
  final int intervalReminderAfterBreak;
  final TimerEndEvent eventReminderAfterBreak;

  TimerOptions copyWith({
    int? durationPomodoro,
    int? additionalDuration,
    int? durationShortBreak,
    int? durationLongBreak,
    int? intervalLongBreak,
    bool? autoStartBreak,
    bool? autoStartPomodoro,
    TimerEndEvent? endEventPomodoro,
    TimerEndEvent? endEventAdditionalPomodoro,
    int? intervalReminderAfterBreak,
    TimerEndEvent? eventReminderAfterBreak,
  }) => TimerOptions(
    durationPomodoro: durationPomodoro ?? this.durationPomodoro,
    additionalDuration: additionalDuration ?? this.additionalDuration,
    durationShortBreak: durationShortBreak ?? this.durationShortBreak,
    durationLongBreak: durationLongBreak ?? this.durationLongBreak,
    intervalLongBreak: intervalLongBreak ?? this.intervalLongBreak,
    autoStartBreak: autoStartBreak ?? this.autoStartBreak,
    autoStartPomodoro: autoStartPomodoro ?? this.autoStartPomodoro,
    endEventPomodoro: endEventPomodoro ?? this.endEventPomodoro,
    endEventAdditionalPomodoro:
        endEventAdditionalPomodoro ?? this.endEventAdditionalPomodoro,
    intervalReminderAfterBreak:
        intervalReminderAfterBreak ?? this.intervalReminderAfterBreak,
    eventReminderAfterBreak:
        eventReminderAfterBreak ?? this.eventReminderAfterBreak,
  );

  void validate() {
    const maxMinutes = 2147483647;
    if (durationPomodoro < 1 || durationPomodoro > maxMinutes) {
      throw const FormatException(
        'Pomodoro duration must be between 1 and 2147483647 minutes.',
      );
    }
    if (additionalDuration < 0 || additionalDuration > maxMinutes) {
      throw const FormatException(
        'Additional Pomodoro duration must be between 0 and 2147483647 minutes.',
      );
    }
    if (durationShortBreak < 0 || durationShortBreak > maxMinutes) {
      throw const FormatException(
        'Short break duration must be between 0 and 2147483647 minutes.',
      );
    }
    if (durationLongBreak < 0 || durationLongBreak > maxMinutes) {
      throw const FormatException(
        'Long break duration must be between 0 and 2147483647 minutes.',
      );
    }
    if (intervalLongBreak < 0 || intervalLongBreak > maxMinutes) {
      throw const FormatException(
        'Long break interval is outside the supported range.',
      );
    }
    if (intervalReminderAfterBreak < 0 ||
        intervalReminderAfterBreak > maxMinutes) {
      throw const FormatException(
        'Reminder interval must be between 0 and 2147483647 minutes.',
      );
    }
  }

  Map<String, Object> toJson() => {
    'durationPomodoro': durationPomodoro,
    'additionalDuration': additionalDuration,
    'durationShortBreak': durationShortBreak,
    'durationLongBreak': durationLongBreak,
    'intervalLongBreak': intervalLongBreak,
    'autoStartBreak': autoStartBreak,
    'autoStartPomodoro': autoStartPomodoro,
    'endEventPomodoro': endEventPomodoro.toJson(),
    'endEventAdditionalPomodoro': endEventAdditionalPomodoro.toJson(),
    'intervalReminderAfterBreak': intervalReminderAfterBreak,
    'eventReminderAfterBreak': eventReminderAfterBreak.toJson(),
  };

  String encode() => jsonEncode(toJson());

  factory TimerOptions.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Rust timer settings must be a JSON object.');
    }
    final options = TimerOptions(
      durationPomodoro: _readInt(decoded, 'durationPomodoro'),
      additionalDuration: _readInt(decoded, 'additionalDuration'),
      durationShortBreak: _readInt(decoded, 'durationShortBreak'),
      durationLongBreak: _readInt(decoded, 'durationLongBreak'),
      intervalLongBreak: _readInt(decoded, 'intervalLongBreak'),
      autoStartBreak: _readBool(decoded, 'autoStartBreak'),
      autoStartPomodoro: _readBool(decoded, 'autoStartPomodoro'),
      endEventPomodoro: decoded.containsKey('endEventPomodoro')
          ? TimerEndEvent.decode(
              decoded['endEventPomodoro'],
              'endEventPomodoro',
            )
          : const TimerEndEvent.sound(),
      endEventAdditionalPomodoro:
          decoded.containsKey('endEventAdditionalPomodoro')
          ? TimerEndEvent.decode(
              decoded['endEventAdditionalPomodoro'],
              'endEventAdditionalPomodoro',
            )
          : const TimerEndEvent.lockScreen(),
      intervalReminderAfterBreak:
          decoded.containsKey('intervalReminderAfterBreak')
          ? _readInt(decoded, 'intervalReminderAfterBreak')
          : 5,
      eventReminderAfterBreak: decoded.containsKey('eventReminderAfterBreak')
          ? TimerEndEvent.decode(
              decoded['eventReminderAfterBreak'],
              'eventReminderAfterBreak',
            )
          : const TimerEndEvent.sound(),
    );
    options.validate();
    return options;
  }
}

class AppSettings {
  const AppSettings({
    this.timerOptions = const TimerOptions(),
    this.theme = AppThemePreference.system,
  });

  final TimerOptions timerOptions;
  final AppThemePreference theme;

  AppSettings copyWith({
    TimerOptions? timerOptions,
    AppThemePreference? theme,
  }) => AppSettings(
    timerOptions: timerOptions ?? this.timerOptions,
    theme: theme ?? this.theme,
  );
}

abstract interface class AppSettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Future<void> reset(AppSettings settings);
}

class MemoryAppSettingsStore implements AppSettingsStore {
  MemoryAppSettingsStore([this._settings = const AppSettings()]);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> reset(AppSettings settings) async {
    _settings = settings;
  }
}

class SharedPreferencesAppSettingsStore implements AppSettingsStore {
  static const _themeKey = 'appThemeMode';

  @override
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_themeKey);
    final theme = switch (value) {
      null || 'system' => AppThemePreference.system,
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => throw FormatException('Unsupported saved app theme: $value'),
    };
    return AppSettings(theme: theme);
  }

  @override
  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_themeKey, settings.theme.name);
    if (!saved) throw StateError('Could not save the app theme preference.');
  }

  @override
  Future<void> reset(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    final removed = await preferences.remove(_themeKey);
    if (!removed && preferences.containsKey(_themeKey)) {
      throw StateError('Could not reset the app theme preference.');
    }
  }
}

int _readInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('The "$key" timer option must be an integer.');
}

bool _readBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('The "$key" timer option must be true or false.');
}
