import 'dart:convert';

const serviceProtocolVersion = 1;

enum TimerStatus { idle, running, paused, waiting, awaitingBreakDecision }

enum TimerPhase { pomodoro, additionalPomodoro, shortBreak, longBreak }

extension TimerStatusLabel on TimerStatus {
  String get label => switch (this) {
    TimerStatus.idle => 'Ready',
    TimerStatus.running => 'In progress',
    TimerStatus.paused => 'Paused',
    TimerStatus.waiting => 'Waiting to start',
    TimerStatus.awaitingBreakDecision => 'Choose a break',
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
  });

  final TimerStatus status;
  final TimerPhase? phase;
  final int elapsedSeconds;
  final int durationSeconds;
  final int completedPomodoros;

  String get nextSessionLabel => status == TimerStatus.awaitingBreakDecision
      ? 'Your choice'
      : switch (phase) {
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
  });

  final String type;
  final TimerSnapshot? state;
  final TimerPhase? phase;
  final int? completedPomodoros;
  final String? message;

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
        );
      case 'error':
        return ServiceEvent(type: type, message: event['message'] as String);
      default:
        throw FormatException('Unknown service event: $type');
    }
  }
}
