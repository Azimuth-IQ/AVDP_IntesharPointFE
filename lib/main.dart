import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/app.dart';
import 'package:inteshar/core/logging/client_log_reporter.dart';
import 'package:inteshar/core/logging/device_context.dart';

void main() {
  // Run inside a guarded zone so uncaught async errors are captured and shipped
  // to the operation log (alongside framework + platform errors).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await DeviceContext.init();

    // Framework (build/layout/render) errors.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      ClientLogReporter.report(
        message: details.exceptionAsString(),
        errorType: details.exception.runtimeType.toString(),
        stack: details.stack?.toString(),
        action: 'FlutterError',
      );
    };

    // Errors that escape the framework (e.g. in platform callbacks).
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      ClientLogReporter.report(
        message: error.toString(),
        errorType: error.runtimeType.toString(),
        stack: stack.toString(),
        action: 'PlatformDispatcher',
      );
      return true;
    };

    runApp(const ProviderScope(child: IntesharApp()));
  }, (Object error, StackTrace stack) {
    ClientLogReporter.report(
      message: error.toString(),
      errorType: error.runtimeType.toString(),
      stack: stack.toString(),
      action: 'uncaughtZone',
    );
  });
}
