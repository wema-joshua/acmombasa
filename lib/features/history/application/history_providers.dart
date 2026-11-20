import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/history_repository.dart';
import '../../../core/database/live_query.dart';
import '../../../core/domain/history_models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/state_holder.dart';

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(databaseProvider)),
);

class HistoryFiltersNotifier extends Notifier<HistoryFilters> {
  @override
  HistoryFilters build() => _forPeriod(HistoryPeriod.thisMonth);

  static HistoryFilters _forPeriod(
    HistoryPeriod period, {
    HistoryFilters? keep,
  }) {
    final today = startOfDay(DateTime.now());
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final start = switch (period) {
      HistoryPeriod.today => today,
      HistoryPeriod.thisWeek =>
        DateTime(today.year, today.month, today.day - (today.weekday - 1)),
      HistoryPeriod.thisMonth => DateTime(today.year, today.month, 1),
      HistoryPeriod.custom => today,
    };
    return HistoryFilters(
      period: period,
      start: start,
      end: tomorrow,
      search: keep?.search ?? '',
      purposeKey: keep?.purposeKey,
      roomKey: keep?.roomKey,
      newestFirst: keep?.newestFirst ?? true,
    );
  }

  void setPeriod(HistoryPeriod period) {
    if (period == HistoryPeriod.custom) return;
    state = _forPeriod(period, keep: state);
  }

  /// [first] and [last] are the first and last day picked (inclusive).
  void setCustomRange(DateTime first, DateTime last) {
    final s = startOfDay(first);
    final e = startOfDay(last);
    state = state.copyWith(
      period: HistoryPeriod.custom,
      start: s,
      end: DateTime(e.year, e.month, e.day + 1),
    );
  }

  void setSearch(String value) => state = state.copyWith(search: value);

  void setPurpose(String? key) => state = key == null
      ? state.copyWith(clearPurpose: true)
      : state.copyWith(purposeKey: key);

  void setRoom(String? key) => state = key == null
      ? state.copyWith(clearRoom: true)
      : state.copyWith(roomKey: key);

  void toggleSort() => state = state.copyWith(newestFirst: !state.newestFirst);

  void clearExtras() =>
      state = state.copyWith(search: '', clearPurpose: true, clearRoom: true);
}

final historyFiltersProvider =
    NotifierProvider<HistoryFiltersNotifier, HistoryFilters>(
  HistoryFiltersNotifier.new,
);

final historyReportProvider = StreamProvider<HistoryReport>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(historyRepositoryProvider);
  final filters = ref.watch(historyFiltersProvider);
  return watchQuery(
    db,
    () => repo.load(filters),
    every: const Duration(minutes: 1),
  );
});

final historyRoomsProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(historyRepositoryProvider);
  return watchQuery(db, repo.rooms);
});

/// Visit id selected in the table (drives the session inspector).
final selectedHistoryEntryIdProvider = stateHolderProvider<String?>(() => null);
