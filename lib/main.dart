import 'dart:async';

import 'package:flutter/material.dart';

import 'pomodoro_service.dart';
import 'service_protocol.dart';

void main() {
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatefulWidget {
  const PomodoroApp({super.key, this.controller});

  final TimerController? controller;

  @override
  State<PomodoroApp> createState() => _PomodoroAppState();
}

class _PomodoroAppState extends State<PomodoroApp> {
  late final TimerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PomodoroService();
    unawaited(_controller.connect());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomodoro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F4EF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF245B50),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF245B50),
          secondary: const Color(0xFFC2E66B),
          error: const Color(0xFFB7503E),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 76,
            fontWeight: FontWeight.w400,
            color: Color(0xFF18342F),
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 30,
            color: Color(0xFF18342F),
          ),
          bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF596863)),
        ),
      ),
      home: PomodoroHome(controller: _controller),
    );
  }
}

class PomodoroHome extends StatelessWidget {
  const PomodoroHome({super.key, required this.controller});

  final TimerController controller;

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
                      _TopBar(connected: controller.isConnected),
                      const SizedBox(height: 28),
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
  const _TopBar({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFC2E66B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.hourglass_bottom, color: Color(0xFF18342F)),
        ),
        const SizedBox(width: 12),
        const Text(
          'POMODORO',
          style: TextStyle(
            color: Color(0xFF18342F),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Icon(
          Icons.circle,
          size: 9,
          color: connected ? const Color(0xFF4F8B52) : const Color(0xFFB7503E),
        ),
        const SizedBox(width: 8),
        Text(
          connected ? 'ENGINE CONNECTED' : 'CONNECTING TO RUST',
          style: const TextStyle(
            color: Color(0xFF596863),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
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
    final time = snapshot.phase == null ? '--:--' : _formatDuration(snapshot.remaining);
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
                backgroundColor: const Color(0xFFDDE4DC),
                color: const Color(0xFF245B50),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.phase == null ? 'READY WHEN YOU ARE' : 'TIME LEFT',
                  style: const TextStyle(
                    color: Color(0xFF74817A),
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
                  style: const TextStyle(
                    color: Color(0xFF596863),
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
    final title = snapshot.phase?.label ?? 'A little focus goes a long way.';
    final sessionLabel = snapshot.completedPomodoros == 1 ? 'session' : 'sessions';
    final subtitle = snapshot.phase == null
        ? 'Start a session when you are ready.'
        : '${snapshot.completedPomodoros} completed $sessionLabel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'FOCUS SESSION',
          style: TextStyle(
            color: Color(0xFF77827C),
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
          style: const TextStyle(
            color: Color(0xFF596863),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBE1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          const Icon(Icons.skip_next, color: Color(0xFF245B50), size: 18),
          const SizedBox(width: 9),
          const Text(
            'UP NEXT',
            style: TextStyle(
              color: Color(0xFF74817A),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF18342F),
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

class _Controls extends StatelessWidget {
  const _Controls({required this.snapshot, required this.controller});

  final TimerSnapshot snapshot;
  final TimerController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isConnected;
    final waiting = snapshot.status == TimerStatus.waiting;
    final paused = snapshot.status == TimerStatus.paused;
    final running = snapshot.status == TimerStatus.running;
    final startingBreak = waiting && snapshot.phase != TimerPhase.pomodoro;
    final canStart = connected && (snapshot.status == TimerStatus.idle || waiting);
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
            backgroundColor: const Color(0xFF245B50),
            foregroundColor: Colors.white,
            minimumSize: const Size(184, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
        if (canControl)
          IconButton.filledTonal(
            tooltip: paused ? 'Resume timer' : 'Pause timer',
            onPressed: () => controller.sendCommand(paused ? 'resume' : 'pause'),
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF18342F),
              backgroundColor: const Color(0xFFC2E66B),
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
                ? () => canControl
                      ? controller.sendCommand(
                          'skip',
                          seconds: snapshot.remaining.inSeconds,
                        )
                      : controller.sendCommand('cancel')
                : null,
            icon: Icon(canControl ? Icons.skip_next : Icons.stop),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFFB7503E),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8E7E1),
        border: Border.all(color: const Color(0xFFE5B8AA)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFF9D4638), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF77382E), fontSize: 13),
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
    return const Row(
      children: [
        Text(
          'LOCKING POMODORO TIMER',
          style: TextStyle(
            color: Color(0xFF87918B),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        Spacer(),
        Text(
          'DESKTOP',
          style: TextStyle(
            color: Color(0xFF87918B),
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
