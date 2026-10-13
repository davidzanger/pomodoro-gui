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
  late final Map<String, TextEditingController> _controllers;
  Future<void> _saveQueue = Future<void>.value();
  String? _saveError;
  bool _dismissLoadError = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
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

  void _queueSave(AppSettings settings) {
    _saveQueue = _saveQueue.then((_) async {
      try {
        await widget.onSettingsChanged(settings);
        if (mounted) setState(() => _saveError = null);
      } on Object catch (error, stackTrace) {
        appTalker.handle(error, stackTrace, 'Could not save app settings.');
        if (mounted) setState(() => _saveError = error.toString());
      }
    });
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset settings?'),
        content: Text(
          widget.loadError == null
              ? 'Timer and appearance settings will return to their defaults. '
                    'Other Rust timer options will be preserved.'
              : 'The options file could not be read. Resetting replaces it, '
                    'so any other custom Rust timer options may be lost.',
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
      _controllers['pomodoro']!.text = '25';
      _controllers['additional']!.text = '5';
      _controllers['shortBreak']!.text = '5';
      _controllers['longBreak']!.text = '15';
      _controllers['interval']!.text = '4';
    });
    try {
      await widget.onReset(defaults);
    } on Object catch (error, stackTrace) {
      appTalker.handle(error, stackTrace, 'Could not reset app settings.');
      if (mounted) setState(() => _saveError = error.toString());
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
    required int minimum,
    required TimerOptions Function(TimerOptions, int) update,
  }) {
    return TextFormField(
      key: ValueKey(keyName),
      controller: _controllers[keyName],
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (text) => _validateInteger(text, minimum),
      onChanged: (text) => _updateInteger(text, minimum, update),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _settings.timerOptions;
    final colors = Theme.of(context).colorScheme;
    final error = _saveError ?? (_dismissLoadError ? null : widget.loadError);

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
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
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _numberField(
                    keyName: 'pomodoro',
                    label: 'Focus duration',
                    suffix: 'minutes',
                    minimum: 1,
                    update: (value, minutes) =>
                        value.copyWith(durationPomodoro: minutes),
                  ),
                  const SizedBox(height: 12),
                  _numberField(
                    keyName: 'additional',
                    label: 'Additional focus phase',
                    suffix: 'minutes (0 = off)',
                    minimum: 0,
                    update: (value, minutes) =>
                        value.copyWith(additionalDuration: minutes),
                  ),
                  const SizedBox(height: 12),
                  _numberField(
                    keyName: 'shortBreak',
                    label: 'Short break',
                    suffix: 'minutes (0 = off)',
                    minimum: 0,
                    update: (value, minutes) =>
                        value.copyWith(durationShortBreak: minutes),
                  ),
                  const SizedBox(height: 12),
                  _numberField(
                    keyName: 'longBreak',
                    label: 'Long break',
                    suffix: 'minutes (0 = off)',
                    minimum: 0,
                    update: (value, minutes) =>
                        value.copyWith(durationLongBreak: minutes),
                  ),
                  const SizedBox(height: 12),
                  _numberField(
                    keyName: 'interval',
                    label: 'Long break every',
                    suffix: 'Pomodoros (0 = short breaks only)',
                    minimum: 0,
                    update: (value, count) =>
                        value.copyWith(intervalLongBreak: count),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start breaks automatically'),
                    value: options.autoStartBreak,
                    onChanged: (enabled) => _updateOptions(
                      (value) => value.copyWith(autoStartBreak: enabled),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Start focus automatically after a break',
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
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DropdownButtonFormField<AppThemePreference>(
                key: const ValueKey('theme'),
                initialValue: _settings.theme,
                decoration: const InputDecoration(labelText: 'App theme'),
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
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Could not save changes. Check the values and timer connection.',
              style: TextStyle(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
