import 'package:flutter/foundation.dart';

import '../../../core/services/app_initializer.dart';

enum SplashStatus { loading, ready, failed }

/// Drives the splash screen. Holds no UI code.
class SplashController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  SplashController({required AppInitializer initializer})
      : _initializer = initializer;

  final AppInitializer _initializer;

  SplashStatus _status = SplashStatus.loading;
  StartupDestination? _destination;
  Object? _error;
  bool _disposed = false;

  SplashStatus get status => _status;
  StartupDestination? get destination => _destination;
  Object? get error => _error;

  /// Runs initialisation. Safe to call again after a failure to retry.
  Future<void> start() async {
    _status = SplashStatus.loading;
    _error = null;
    _notify();

    try {
      _destination = await _initializer.initialize();
      _status = SplashStatus.ready;
    } catch (error, stackTrace) {
      debugPrint('Splash initialisation failed: $error\n$stackTrace');
      _error = error;
      _status = SplashStatus.failed;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
