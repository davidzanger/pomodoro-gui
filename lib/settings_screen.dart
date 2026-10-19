import 'package:flutter/material.dart';

import 'app_logging.dart';
import 'app_settings.dart';

typedef AppSettingsChanged = Future<void> Function(AppSettings settings);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.settings,
    required this.onSettingsChanged,
    required this.onReset,
    this.loadError,
    super.key,
  });

  final AppSettings settings;
  final AppSettingsChanged onSettingsChanged;
  final AppSettingsChanged onReset;
  final String? loadError;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _maxMinutes = 2147483647;

  late AppSettings _settings;
  late AppSettings _confirmedSettings;
  late final Map<String, TextEditingController> _controllers;
  Future<void> _saveQueue = Future<void>.value();
  String? _saveError;
  bool _dismissLoadError = false;
  int _saveRevision = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _confirmedSettings = widget.settings;
    final options = _settings.timerOptions;
    _controllers = {
      'pomodoro': TextEditingController(
        text: options.durationPomodoro.toString(),
      ),
      'additional': TextEditingController(
        text: options.additionalDuration.toString(),
      ),
      'shortBreak': TextEditingController(
        text: options.durationShortBreak.toString(),
      ),
      'longBreak': TextEditingController(
        text: options.durationLongBreak.toString(),
      ),
      'interval': TextEditingController(
        text: options.intervalLongBreak.toString(),
      ),
      'reminderInterval': TextEditingController(
        text: options.intervalReminderAfterBreak.toString(),
      ),
      'pomodoroSound': TextEditingController(
        text: options.endEventPomodoro.soundPath,
      ),
      'additionalSound': TextEditingController(
        text: options.endEventAdditionalPomodoro.soundPath,
      ),
      'reminderSound': TextEditingController(
        text: options.eventReminderAfterBreak.soundPath,
      ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateInteger(
    String text,
    int minimum,
    TimerOptions Function(TimerOptions options, int value) update,
  ) {
    final value = int.tryParse(text);
    if (value == null || value < minimum || value > _maxMinutes) return;
    final settings = _settings.copyWith(
      timerOptions: update(_settings.timerOptions, value),
    );
    setState(() => _settings = settings);
    _queueSave(settings);
  }

  void _updateOptions(TimerOptions Function(TimerOptions) update) {
    final settings = _settings.copyWith(
      timerOptions: update(_settings.timerOptions),
    );
    setState(() => _settings = settings);
    _queueSave(settings);
  }

  void _updateTheme(AppThemePreference? theme) {
    if (theme == null) return;
    final settings = _settings.copyWith(theme: theme);
    setState(() => _settings = settings);
    _queueSave(settings);
  }

  void _updateAutoStartOnLaunch(bool enabled) {
    final settings = _settings.copyWith(autoStartOnLaunch: enabled);
    setState(() => _settings = settings);
    _queueSave(settings);
  }

  void _queueSave(AppSettings settings) {
    final revision = ++_saveRevision;
    _saveQueue = _saveQueue.then((_) async {
      try {
        await widget.onSettingsChanged(settings);
        _confirmedSettings = settings;
        if (mounted && revision == _saveRevision) {
          setState(() => _saveError = null);
        }
      } on Object catch (error, stackTrace) {
        appTalker.handle(error, stackTrace, 'Could not save app settings.');
        if (mounted && revision == _saveRevision) {
          setState(() {
            _settings = _confirmedSettings;
            _syncControllers(_confirmedSettings.timerOptions);
            _saveError = error.toString();
          });
        }
      }
    });
  }

  void _syncControllers(TimerOptions options) {
    _controllers['pomodoro']!.text = options.durationPomodoro.toString();
    _controllers['additional']!.text = options.additionalDuration.toString();
    _controllers['shortBreak']!.text = options.durationShortBreak.toString();
    _controllers['longBreak']!.text = options.durationLongBreak.toString();
    _controllers['interval']!.text = options.intervalLongBreak.toString();
    _controllers['reminderInterval']!.text = options.intervalReminderAfterBreak
        .toString();
    _controllers['pomodoroSound']!.text = options.endEventPomodoro.soundPath;
    _controllers['additionalSound']!.text =
        options.endEventAdditionalPomodoro.soundPath;
    _controllers['reminderSound']!.text =
        options.eventReminderAfterBreak.soundPath;
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset settings?'),
        content: Text(
          widget.loadError == null
              ? 'Timer, actions, reminders and appearance will return to their defaults.'
              : 'The options file could not be read. Resetting replaces it, '
                    'so custom Rust timer options may be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _saveQueue;
    const defaults = AppSettings();
    setState(() {
      _settings = defaults;
      _saveError = null;
      _dismissLoadError = true;
      _syncControllers(defaults.timerOptions);
    });
    try {
      await widget.onReset(defaults);
      _confirmedSettings = defaults;
    } on Object catch (error, stackTrace) {
      appTalker.handle(error, stackTrace, 'Could not reset app settings.');
      if (mounted) {
        setState(() {
          _settings = _confirmedSettings;
          _syncControllers(_confirmedSettings.timerOptions);
          _saveError = error.toString();
        });
      }
    }
  }

  String? _validateInteger(String? text, int minimum) {
    final value = int.tryParse(text ?? '');
    if (value == null || value < minimum || value > _maxMinutes) {
      return 'Enter a whole number from $minimum to $_maxMinutes.';
    }
    return null;
  }

  Widget _numberField({
    required String keyName,
    required String label,
    required String suffix,
    required String explanation,
    required int minimum,
    required TimerOptions Function(TimerOptions, int) update,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _settingLabel(label, explanation),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey(keyName),
          controller: _controllers[keyName],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: suffix),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (text) => _validateInteger(text, minimum),
          onChanged: (text) => _updateInteger(text, minimum, update),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ],
    );
  }

  Widget _settingLabel(String label, String explanation) => Row(
    children: [
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
      _infoButton(label, explanation),
    ],
  );

  Widget _infoButton(String label, String explanation) => IconButton(
    tooltip: explanation,
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    icon: const Icon(Icons.info_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  Widget _eventField({
    required String keyName,
    required String label,
    required String explanation,
    required TimerEndEvent event,
    required TimerOptions Function(TimerOptions, TimerEndEvent) update,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _settingLabel(label, explanation),
      const SizedBox(height: 6),
      DropdownButtonFormField<TimerEventKind>(
        key: ValueKey('$keyName-kind-${event.kind.name}'),
        initialValue: event.kind,
        decoration: const InputDecoration(labelText: 'Action'),
        items: const [
          DropdownMenuItem(
            value: TimerEventKind.sound,
            child: Text('Play sound'),
          ),
          DropdownMenuItem(
            value: TimerEventKind.lockScreen,
            child: Text('Lock screen'),
          ),
        ],
        onChanged: (kind) {
          if (kind == null) return;
          if (kind == TimerEventKind.lockScreen) {
            _controllers['${keyName}Sound']!.clear();
          }
          _updateOptions(
            (options) => update(options, event.copyWith(kind: kind)),
          );
        },
      ),
      if (event.kind == TimerEventKind.sound) ...[
        const SizedBox(height: 10),
        _settingLabel(
          'Sound file path',
          'Enter the full path to an existing audio file. Leave it empty to play the built-in sound.',
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('$keyName-sound'),
          controller: _controllers['${keyName}Sound'],
          decoration: const InputDecoration(hintText: 'Default sound'),
          onChanged: (path) => _updateOptions(
            (options) =>
                update(options, event.copyWith(soundPath: path.trim())),
          ),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final options = _settings.timerOptions;
    final colors = Theme.of(context).colorScheme;
    final error = _saveError == null
        ? (_dismissLoadError ? null : widget.loadError)
        : 'Could not apply changes. Check saved and active timer settings. $_saveError';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
            children: [
              Text(
                'Make the rhythm yours.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Set your Pomodoro duration, breaks, and what happens when each phase ends.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Timer', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Changes save immediately and apply to the next timer phase.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: _settingLabel(
                          'Start timer when app opens',
                          'Start the first Pomodoro automatically each time you open the app.',
                        ),
                        value: _settings.autoStartOnLaunch,
                        onChanged: _updateAutoStartOnLaunch,
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        keyName: 'pomodoro',
                        label: 'Pomodoro duration',
                        explanation:
                            'Length of each regular Pomodoro in minutes.',
                        suffix: 'minutes',
                        minimum: 1,
                        update: (value, minutes) =>
                            value.copyWith(durationPomodoro: minutes),
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        keyName: 'additional',
                        label: 'Additional Pomodoro duration',
                        explanation:
                            'Length of the additional Pomodoro after a regular Pomodoro. Set to 0 to skip this phase.',
                        suffix: 'minutes (0 = off)',
                        minimum: 0,
                        update: (value, minutes) =>
                            value.copyWith(additionalDuration: minutes),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: _settingLabel(
                          'Repeat Additional Pomodoros',
                          'Keep starting another Additional Pomodoro until you choose the due break. Requires a duration above 0.',
                        ),
                        value: options.repeatAdditionalEnabled,
                        onChanged: options.additionalDuration > 0
                            ? (enabled) => _updateOptions(
                                (value) => value.copyWith(
                                  repeatAdditionalPomodoro: enabled,
                                ),
                              )
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: _settingLabel(
                          'Ask before each break',
                          'After each completed Additional Pomodoro, choose another work round or the due break.',
                        ),
                        value: options.breakDecisionEnabled,
                        onChanged: options.repeatAdditionalEnabled
                            ? (enabled) => _updateOptions(
                                (value) =>
                                    value.copyWith(askBeforeBreak: enabled),
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        keyName: 'shortBreak',
                        label: 'Short break',
                        explanation:
                            'Length of a short break in minutes. Set to 0 to skip short breaks.',
                        suffix: 'minutes (0 = off)',
                        minimum: 0,
                        update: (value, minutes) =>
                            value.copyWith(durationShortBreak: minutes),
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        keyName: 'longBreak',
                        label: 'Long break',
                        explanation:
                            'Length of a long break in minutes. Set to 0 to skip long breaks.',
                        suffix: 'minutes (0 = off)',
                        minimum: 0,
                        update: (value, minutes) =>
                            value.copyWith(durationLongBreak: minutes),
                      ),
                      const SizedBox(height: 12),
                      _numberField(
                        keyName: 'interval',
                        label: 'Long break every',
                        explanation:
                            'Number of completed Pomodoros between long breaks. Set to 0 to use short breaks only.',
                        suffix: 'Pomodoros (0 = short breaks only)',
                        minimum: 0,
                        update: (value, count) =>
                            value.copyWith(intervalLongBreak: count),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: _settingLabel(
                          'Start breaks automatically',
                          'Begin the next break as soon as the Pomodoro ends. When off, the timer waits for you to start it.',
                        ),
                        value: options.autoStartBreak,
                        onChanged: (enabled) => _updateOptions(
                          (value) => value.copyWith(autoStartBreak: enabled),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: _settingLabel(
                          'Start Pomodoro automatically after a break',
                          'Begin the next Pomodoro when a break ends. Turn this off to start manually and enable a reminder.',
                        ),
                        value: options.autoStartPomodoro,
                        onChanged: (enabled) => _updateOptions(
                          (value) => value.copyWith(autoStartPomodoro: enabled),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Actions & reminders',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Actions apply to upcoming phases. Reminders repeat while the next Pomodoro waits to start.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _eventField(
                        keyName: 'pomodoro',
                        label: 'When a Pomodoro or a break ends',
                        explanation:
                            'Choose a sound or lock the screen when a regular Pomodoro or a break ends. An empty sound path uses the built-in sound.',
                        event: options.endEventPomodoro,
                        update: (value, event) =>
                            value.copyWith(endEventPomodoro: event),
                      ),
                      const SizedBox(height: 18),
                      _eventField(
                        keyName: 'additional',
                        label: 'When an additional Pomodoro ends',
                        explanation:
                            'Choose what happens after the additional Pomodoro. This phase is skipped when its duration is 0.',
                        event: options.endEventAdditionalPomodoro,
                        update: (value, event) =>
                            value.copyWith(endEventAdditionalPomodoro: event),
                      ),
                      const SizedBox(height: 18),
                      _numberField(
                        keyName: 'reminderInterval',
                        label: 'Reminder after a break',
                        explanation:
                            'Minutes after a break ends before the reminder action runs. Used only when automatic Pomodoro start is off. Set to 0 to disable it.',
                        suffix: 'minutes (0 = off)',
                        minimum: 0,
                        update: (value, minutes) =>
                            value.copyWith(intervalReminderAfterBreak: minutes),
                      ),
                      const SizedBox(height: 18),
                      _eventField(
                        keyName: 'reminder',
                        label: 'Reminder action',
                        explanation:
                            'Choose a sound or screen lock for the reminder after a break. An empty sound path uses the built-in sound.',
                        event: options.eventReminderAfterBreak,
                        update: (value, event) =>
                            value.copyWith(eventReminderAfterBreak: event),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _settingLabel(
                        'App theme',
                        'Choose a light or dark appearance, or follow your system setting.',
                      ),
                      const SizedBox(height: 6),
                      KeyedSubtree(
                        key: ValueKey('theme-value-${_settings.theme.name}'),
                        child: DropdownButtonFormField<AppThemePreference>(
                          key: const ValueKey('theme'),
                          initialValue: _settings.theme,
                          decoration: const InputDecoration(),
                          items: const [
                            DropdownMenuItem(
                              value: AppThemePreference.system,
                              child: Text('System default'),
                            ),
                            DropdownMenuItem(
                              value: AppThemePreference.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: AppThemePreference.dark,
                              child: Text('Dark'),
                            ),
                          ],
                          onChanged: _updateTheme,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
