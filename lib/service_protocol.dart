import 'dart:convert';

const serviceProtocolVersion = 1;

enum TimerStatus { idle, running, paused, waiting }

enum TimerPhase { pomodoro, additionalPomodoro, shortBreak, longBreak }

enum NextStep { pomodoro, additionalPomodoro, shortBreak, longBreak }

extension NextStepLabel on NextStep {
  String get label => switch (this) {
    NextStep.pomodoro => 'Pomodoro',
    NextStep.additionalPomodoro => 'Additional Pomodoro',
    NextStep.shortBreak => 'Short break',
    NextStep.longBreak => 'Long break',
  };
}

extension TimerStatusLabel on TimerStatus {
  String get label => switch (this) {
    TimerStatus.idle => 'Ready',
    TimerStatus.running => 'In progress',
    TimerStatus.paused => 'Paused',
    TimerStatus.waiting => 'Waiting to start',
  };
}

extension TimerPhaseLabel on TimerPhase {
  String get label => switch (this) {
    TimerPhase.pomodoro => 'Pomodoro',
    TimerPhase.additionalPomodoro => 'Additional Pomodoro',
    TimerPhase.shortBreak => 'Short break',
    TimerPhase.longBreak => 'Long break',
  };
}

class TimerSnapshot {
  const TimerSnapshot({
    required this.status,
    required this.phase,
    required this.elapsedSeconds,
    required this.durationSeconds,
    required this.completedPomodoros,
    this.nextStep,
    this.phaseId = 0,
    this.breakDecisionId = 0,
    this.breakDecisionPending = false,
  });

  final TimerStatus status;
  final TimerPhase? phase;
  final int elapsedSeconds;
  final int durationSeconds;
  final int completedPomodoros;
  final NextStep? nextStep;
  final int phaseId;
  final int breakDecisionId;
  final bool breakDecisionPending;

  String get nextSessionLabel =>
      nextStep?.label ??
      switch (phase) {
        null => 'Pomodoro',
        TimerPhase.pomodoro => 'Additional Pomodoro',
        TimerPhase.additionalPomodoro => 'Break',
        TimerPhase.shortBreak || TimerPhase.longBreak => 'Pomodoro',
      };

  Duration get remaining => Duration(
    seconds: (durationSeconds - elapsedSeconds).clamp(0, durationSeconds),
  );

  double get progress => durationSeconds == 0
      ? 0
      : (elapsedSeconds / durationSeconds).clamp(0.0, 1.0);

  factory TimerSnapshot.fromJson(Map<String, dynamic> json) {
    return TimerSnapshot(
      status: TimerStatus.values.byName(json['status'] as String),
      phase: json['phase'] == null
          ? null
          : TimerPhase.values.byName(json['phase'] as String),
      elapsedSeconds: (json['elapsedSeconds'] as num).toInt(),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      completedPomodoros: (json['completedPomodoros'] as num).toInt(),
      nextStep: json['nextStep'] == null
          ? null
          : NextStep.values.byName(json['nextStep'] as String),
      phaseId: (json['phaseId'] as num?)?.toInt() ?? 0,
      breakDecisionId: (json['breakDecisionId'] as num?)?.toInt() ?? 0,
      breakDecisionPending: json['breakDecisionPending'] as bool? ?? false,
    );
  }
}

class ServiceEvent {
  const ServiceEvent({
    required this.type,
    this.state,
    this.phase,
    this.completedPomodoros,
    this.message,
    this.phaseId,
    this.skipped,
  });

  final String type;
  final TimerSnapshot? state;
  final TimerPhase? phase;
  final int? completedPomodoros;
  final String? message;
  final int? phaseId;
  final bool? skipped;

  factory ServiceEvent.decode(String line) {
    final response = jsonDecode(line) as Map<String, dynamic>;
    final version = response['protocolVersion'];
    if (version != serviceProtocolVersion) {
      throw FormatException('Unsupported protocol version: $version');
    }

    final event = response['event'] as Map<String, dynamic>;
    final type = event['type'] as String;
    switch (type) {
      case 'ready':
      case 'stopped':
        return ServiceEvent(type: type);
      case 'state':
        return ServiceEvent(type: type, state: TimerSnapshot.fromJson(event));
      case 'awaitingStart':
      case 'phaseCompleted':
        return ServiceEvent(
          type: type,
          phase: TimerPhase.values.byName(event['phase'] as String),
          completedPomodoros: (event['completedPomodoros'] as num).toInt(),
          phaseId: (event['phaseId'] as num?)?.toInt(),
          skipped: event['skipped'] as bool?,
        );
      case 'error':
        return ServiceEvent(type: type, message: event['message'] as String);
      default:
        throw FormatException('Unknown service event: $type');
    }
  }
}
