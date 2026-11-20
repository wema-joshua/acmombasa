import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A tiny provider that just holds one value (selected id, chosen day...).
///
/// Works the same on Riverpod 2 and 3, so the app does not depend on the
/// old `StateProvider`, which Riverpod 3 moved to a legacy library.
class StateHolder<T> extends Notifier<T> {
  StateHolder(this._initial);

  final T Function() _initial;

  @override
  T build() => _initial();

  void set(T value) => state = value;
}

NotifierProvider<StateHolder<T>, T> stateHolderProvider<T>(T Function() initial) {
  return NotifierProvider<StateHolder<T>, T>(() => StateHolder<T>(initial));
}
