import 'package:talker_flutter/talker_flutter.dart';

final appTalker = TalkerFlutter.init(
  settings: TalkerSettings(useHistory: true, maxHistoryItems: 1000),
);
