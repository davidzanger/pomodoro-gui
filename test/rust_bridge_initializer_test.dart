import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro_gui/rust_bridge_initializer.dart';

void main() {
  test('shares concurrent initialization and skips later calls', () async {
    final started = Completer<void>();
    var calls = 0;
    var initialized = false;
    final initializer = RustBridgeInitializer(() async {
      calls++;
      await started.future;
      initialized = true;
    }, () => initialized);

    final first = initializer.ensureInitialized();
    final second = initializer.ensureInitialized();
    expect(calls, 1);

    started.complete();
    await Future.wait([first, second]);
    await initializer.ensureInitialized();
    expect(calls, 1);
  });

  test('retries after an initialization failure', () async {
    var calls = 0;
    var initialized = false;
    final initializer = RustBridgeInitializer(() async {
      calls++;
      if (calls == 1) throw StateError('DLL unavailable');
      initialized = true;
    }, () => initialized);

    await expectLater(initializer.ensureInitialized(), throwsStateError);
    await initializer.ensureInitialized();
    expect(calls, 2);
    await initializer.ensureInitialized();
    expect(calls, 2);
  });

  test('waits until Rust initializers finish after the bridge is marked ready', () async {
    final initializersFinished = Completer<void>();
    var initialized = false;
    final initializer = RustBridgeInitializer(() async {
      initialized = true;
      await initializersFinished.future;
    }, () => initialized);

    final first = initializer.ensureInitialized();
    var secondCompleted = false;
    final second = initializer.ensureInitialized().then((_) {
      secondCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(secondCompleted, isFalse);

    initializersFinished.complete();
    await Future.wait([first, second]);
    expect(secondCompleted, isTrue);
  });

  test('starts again after the bridge has been disposed', () async {
    var calls = 0;
    var initialized = false;
    final initializer = RustBridgeInitializer(() async {
      calls++;
      initialized = true;
    }, () => initialized);

    await initializer.ensureInitialized();
    initialized = false;
    await initializer.ensureInitialized();
    expect(calls, 2);
  });
}
