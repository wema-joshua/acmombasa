import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/directory_repository.dart';
import '../../../core/database/live_query.dart';
import '../../../core/domain/directory_models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/state_holder.dart';

final directoryRepositoryProvider = Provider<DirectoryRepository>(
  (ref) => DirectoryRepository(ref.watch(databaseProvider)),
);

class DirectoryQueryNotifier extends Notifier<DirectoryQuery> {
  @override
  DirectoryQuery build() => const DirectoryQuery();

  void setSearch(String value) => state = state.copyWith(search: value);

  void setCategory(String? value) => state = value == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(category: value);

  void setStatus(DirectoryStatus value) =>
      state = state.copyWith(status: value);

  void setSort(DirectorySort value) => state = state.copyWith(sort: value);

  void reset() => state = const DirectoryQuery();
}

final directoryQueryProvider =
    NotifierProvider<DirectoryQueryNotifier, DirectoryQuery>(
  DirectoryQueryNotifier.new,
);

/// Rows for the list; re-runs on any database change.
final directoryRowsProvider = StreamProvider<List<DirectoryRow>>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(directoryRepositoryProvider);
  final query = ref.watch(directoryQueryProvider);
  return watchQuery(db, () => repo.loadRows(query));
});

final directorySummaryProvider = StreamProvider<DirectorySummary>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(directoryRepositoryProvider);
  return watchQuery(db, repo.summary, every: const Duration(minutes: 1));
});

final directoryCategoriesProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(directoryRepositoryProvider);
  return watchQuery(db, repo.categories);
});

/// Visitor id shown in the right-hand panel.
final selectedVisitorIdProvider = stateHolderProvider<String?>(() => null);

final visitorProfileProvider =
    StreamProvider.autoDispose.family<VisitorProfileData?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(directoryRepositoryProvider);
  return watchQuery(db, () => repo.profile(id));
});
