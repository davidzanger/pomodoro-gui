import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:talker_flutter/talker_flutter.dart';

import 'app_settings.dart';
import 'app_logging.dart';
import 'pomodoro_service.dart';
import 'service_protocol.dart';
import 'settings_screen.dart';

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appTalker.handle(
      details.exception,
      details.stack,
      'Flutter framework error',
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    appTalker.handle(error, stackTrace, 'Uncaught asynchronous error');
    return true;
  };
  appTalker.info('Pomodoro application started.');
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({super.key, this.controller, this.settingsStore});

  final TimerController? controller;
  final AppSettingsStore? settingsStore;

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp> {
  late final TimerController _controller;
  late final AppSettingsStore _settingsStore;
  AppSettings _settings = const AppSettings();
  String? _settingsError;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PomodoroService();
    _settingsStore =
        widget.settingsStore ?? SharedPreferencesAppSettingsStore();
    unawaited(_loadSettingsAndConnect());
  }

  Future<void> _loadSettingsAndConnect() async {
    try {
      final appSettings = await _settingsStore.load();
      final timerOptions = await _controller.loadSettings();
      final settings = AppSettings(
        timerOptions: timerOptions,
        theme: appSettings.theme,
      );
      if (mounted) setState(() => _settings = settings);
    } on Object catch (error, stackTrace) {
      appTalker.handle(error, stackTrace, 'Could not load app settings.');
      if (mounted) setState(() => _settingsError = error.toString());
    }
    await _controller.connect();
  }

  Future<void> _saveSettings(AppSettings settings) async {
    await _settingsStore.save(settings);
    if (mounted) {
      setState(() {
        _settings = settings;
        _settingsError = null;
      });
    }
    await _controller.updateSettings(settings.timerOptions);
  }

  Future<void> _resetSettings(AppSettings settings) async {
    await _settingsStore.reset(settings);
    if (mounted) {
      setState(() {
        _settings = settings;
        _settingsError = null;
      });
    }
    await _controller.updateSettings(settings.timerOptions);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = switch (_settings.theme) {
      AppThemePreference.system => ThemeMode.system,
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
    };
    return MaterialApp(
      title: 'Pomodoro',
      debugShowCheckedModeBanner: false,
      theme: _themeData(Brightness.light),
      darkTheme: _themeData(Brightness.dark),
      themeMode: themeMode,
      home: PomodoroHome(
        controller: _controller,
        settings: _settings,
        settingsError: _settingsError,
        onSettingsChanged: _saveSettings,
        onSettingsReset: _resetSettings,
      ),
    );
  }
}

ThemeData _themeData(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF245B50),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF9CC8B9) : const Color(0xFF245B50),
        secondary: const Color(0xFFC2E66B),
        error: const Color(0xFFB7503E),
      );
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF17211F)
        : const Color(0xFFF1F4EF),
    colorScheme: colorScheme,
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 76,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 30,
        color: colorScheme.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
    ),
  );
}

class PomodoroHome extends StatelessWidget {
  const PomodoroHome({
    super.key,
    required this.controller,
    required this.settings,
    required this.settingsError,
    required this.onSettingsChanged,
    required this.onSettingsReset,
  });

  final TimerController controller;
  final AppSettings settings;
  final String? settingsError;
  final AppSettingsChanged onSettingsChanged;
  final AppSettingsChanged onSettingsReset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 24 : 64,
                    vertical: compact ? 24 : 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(
                        connected: controller.isConnected,
                        onShowSettings: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SettingsScreen(
                                settings: settings,
                                loadError: settingsError,
                                onSettingsChanged: onSettingsChanged,
                                onReset: onSettingsReset,
                              ),
                            ),
                          );
                        },
                        onShowLogs: () {
                          appTalker.info('Opened the app log viewer.');
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TalkerScreen(talker: appTalker),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      if (settingsError != null)
                        _ConnectionError(
                          message: 'Could not load settings: $settingsError',
                        ),
                      if (controller.errorMessage != null)
                        _ConnectionError(message: controller.errorMessage!),
                      Expanded(
                        child: compact
                            ? _CompactLayout(
                                snapshot: snapshot,
                                controller: controller,
                              )
                            : _WideLayout(
                                snapshot: snapshot,
                                controller: controller,
                              ),
                      ),
                      const _Footer(),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.connected,
    required this.onShowSettings,
    required this.onShowLogs,
  });

  final bool connected;
  final VoidCallback onShowSettings;
  final VoidCallback onShowLogs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.hourglass_bottom,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'POMODORO',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.circle,
          size: 9,
          color: connected
              ? const Color(0xFF4F8B52)
              : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Text(
          connected ? 'ENGINE CONNECTED' : 'CONNECTING TO RUST',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Settings',
          onPressed: onShowSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(
          tooltip: 'View logs',
          onPressed: onShowLogs,
          icon: const Icon(Icons.receipt_long),
        ),
      ],
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.snapshot, required this.controller});

  final TimerSnapshot snapshot;
  final TimerController controller;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Row(
          children: [
            Expanded(child: _TimerDial(snapshot: snapshot, diameter: 340)),
            const SizedBox(width: 64),
            Expanded(
              child: _SessionPanel(snapshot: snapshot, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({required this.snapshot, required this.controller});

  final TimerSnapshot snapshot;
  final TimerController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          _TimerDial(snapshot: snapshot, diameter: 260),
          const SizedBox(height: 28),
          _SessionPanel(snapshot: snapshot, controller: controller),
        ],
      ),
    );
  }
}

class _TimerDial extends StatelessWidget {
  const _TimerDial({required this.snapshot, required this.diameter});

  final TimerSnapshot snapshot;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = snapshot.phase == null
        ? '--:--'
        : _formatDuration(snapshot.remaining);
    return Center(
      child: SizedBox.square(
        dimension: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: diameter,
              child: CircularProgressIndicator(
                value: snapshot.progress,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                backgroundColor: colors.surfaceContainerHighest,
                color: colors.primary,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.phase == null ? 'READY WHEN YOU ARE' : 'TIME LEFT',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time,
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: diameter * 0.24,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  snapshot.status.label.toUpperCase(),
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionPanel extends StatelessWidget {
  const _SessionPanel({required this.snapshot, required this.controller});

  final TimerSnapshot snapshot;
  final TimerController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = snapshot.phase?.label ?? 'A little focus goes a long way.';
    final sessionLabel = snapshot.completedPomodoros == 1
        ? 'session'
        : 'sessions';
    final subtitle = snapshot.phase == null
        ? 'Start a session when you are ready.'
        : '${snapshot.completedPomodoros} completed $sessionLabel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FOCUS SESSION',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 32),
        _Controls(snapshot: snapshot, controller: controller),
        const SizedBox(height: 18),
        _NextSession(label: snapshot.nextSessionLabel),
        const SizedBox(height: 18),
        Text(
          'Pomodoro ${snapshot.completedPomodoros + 1}',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _NextSession extends StatelessWidget {
  const _NextSession({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(Icons.skip_next, color: colors.primary, size: 18),
          const SizedBox(width: 9),
          Text(
            'UP NEXT',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatefulWidget {
  const _Controls({required this.snapshot, required this.controller});

  final TimerSnapshot snapshot;
  final TimerController controller;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  static const _phaseChangeTimeout = Duration(seconds: 5);

  int _queuedNextSessionSkips = 0;
  bool _processingNextSessionSkips = false;
  Completer<void>? _phaseChangeCompleter;

  @override
  void didUpdateWidget(covariant _Controls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_phaseChangeCompleter != null &&
        _hasPhaseAdvanced(oldWidget.snapshot, widget.snapshot)) {
      _phaseChangeCompleter!.complete();
    }
  }

  bool _hasPhaseAdvanced(TimerSnapshot previous, TimerSnapshot next) {
    return previous.phase != next.phase ||
        previous.status != next.status ||
        previous.durationSeconds != next.durationSeconds ||
        previous.completedPomodoros != next.completedPomodoros ||
        next.elapsedSeconds < previous.elapsedSeconds;
  }

  bool _isActive(TimerSnapshot snapshot) =>
      snapshot.phase != null &&
      (snapshot.status == TimerStatus.running ||
          snapshot.status == TimerStatus.paused);

  void _queueSkipToNextSession() {
    if (!_isActive(widget.snapshot)) return;
    setState(() => _queuedNextSessionSkips++);
    unawaited(_processQueuedNextSessionSkips());
  }

  Future<void> _processQueuedNextSessionSkips() async {
    if (_processingNextSessionSkips) return;
    _processingNextSessionSkips = true;

    try {
      while (mounted && _queuedNextSessionSkips > 0) {
        final snapshot = widget.snapshot;
        if (!_isActive(snapshot)) {
          final discarded = _queuedNextSessionSkips;
          _queuedNextSessionSkips = 0;
          appTalker.warning(
            'Ignored $discarded queued skip-to-next click(s): '
            'the timer is no longer running.',
          );
          break;
        }

        _queuedNextSessionSkips--;
        final phaseChange = Completer<void>();
        _phaseChangeCompleter = phaseChange;
        try {
          appTalker.info(
            'Skipping ${snapshot.phase!.name} with '
            '${snapshot.remaining.inSeconds} seconds remaining.',
          );
          await widget.controller.sendCommand(
            'skip',
            seconds: snapshot.remaining.inSeconds,
          );
          await phaseChange.future.timeout(_phaseChangeTimeout);
        } on TimeoutException catch (error, stackTrace) {
          _queuedNextSessionSkips = 0;
          appTalker.handle(
            error,
            stackTrace,
            'The timer did not report a phase change after a skip.',
          );
          _showSkipError();
          break;
        } on Object catch (error, stackTrace) {
          _queuedNextSessionSkips = 0;
          appTalker.handle(
            error,
            stackTrace,
            'Could not skip the timer phase.',
          );
          _showSkipError();
          break;
        } finally {
          if (identical(_phaseChangeCompleter, phaseChange)) {
            _phaseChangeCompleter = null;
          }
        }
      }
    } finally {
      _processingNextSessionSkips = false;
      if (mounted) setState(() {});
    }
  }

  void _showSkipError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The timer did not advance after skipping.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final controller = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final connected = controller.isConnected;
    final waiting = snapshot.status == TimerStatus.waiting;
    final paused = snapshot.status == TimerStatus.paused;
    final running = snapshot.status == TimerStatus.running;
    final startingBreak = waiting && snapshot.phase != TimerPhase.pomodoro;
    final canStart =
        connected && (snapshot.status == TimerStatus.idle || waiting);
    final canControl = connected && (running || paused);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: canStart ? () => controller.sendCommand('start') : null,
          icon: Icon(startingBreak ? Icons.play_arrow : Icons.timer_outlined),
          label: Text(startingBreak ? 'START BREAK' : 'START SESSION'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            minimumSize: const Size(184, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        if (canControl)
          IconButton.filledTonal(
            tooltip: paused ? 'Resume timer' : 'Pause timer',
            onPressed: () =>
                controller.sendCommand(paused ? 'resume' : 'pause'),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            style: IconButton.styleFrom(
              foregroundColor: colors.onSecondary,
              backgroundColor: colors.secondary,
              fixedSize: const Size(52, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        if (canControl)
          IconButton.outlined(
            tooltip: 'Skip ahead one minute',
            onPressed: () => controller.sendCommand('skip', seconds: 60),
            icon: const Icon(Icons.skip_next),
            style: IconButton.styleFrom(
              fixedSize: const Size(52, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        if (snapshot.phase != null)
          IconButton.outlined(
            tooltip: canControl ? 'Skip to next session' : 'Cancel session',
            onPressed: connected
                ? canControl
                      ? _queueSkipToNextSession
                      : () => controller.sendCommand('cancel')
                : null,
            icon: Icon(canControl ? Icons.skip_next : Icons.stop),
            style: IconButton.styleFrom(
              foregroundColor: colors.error,
              fixedSize: const Size(52, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          'LOCKING POMODORO TIMER',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        Text(
          'DESKTOP',
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 999999);
  final minutesPart = (seconds ~/ 60).toString().padLeft(2, '0');
  final secondsPart = (seconds % 60).toString().padLeft(2, '0');
  return '$minutesPart:$secondsPart';
}
