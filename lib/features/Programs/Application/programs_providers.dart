import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/session_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/live_query.dart';
import '../../../core/domain/program_models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/state_holder.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    ref.watch(databaseProvider),
    ref.watch(visitRepositoryProvider),
  ),
);

/// Day shown in the schedule (midnight).
final scheduleDayProvider = stateHolderProvider<DateTime>(() => startOfDay(DateTime.now()));

/// Venue chip filter; null = all venues.
final venueFilterProvider = stateHolderProvider<String?>(() => null);

final sessionSearchProvider = stateHolderProvider<String>(() => '');

final selectedSessionIdProvider = stateHolderProvider<String?>(() => null);

final sessionsProvider = StreamProvider<List<SessionView>>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  final day = ref.watch(scheduleDayProvider);
  return watchQuery(db, () => repo.sessionsOn(day), every: const Duration(seconds: 30));
});

final daySummaryProvider = StreamProvider<DaySummary>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  final day = ref.watch(scheduleDayProvider);
  return watchQuery(db, () => repo.summaryFor(day), every: const Duration(seconds: 30));
});

final rosterProvider =
    StreamProvider.autoDispose.family<List<RosterEntry>, String>((ref, programId) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  final day = ref.watch(scheduleDayProvider);
  return watchQuery(db, () => repo.roster(programId, day));
});

final draftSessionsProvider = StreamProvider<List<Program>>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(sessionRepositoryProvider);
  return watchQuery(db, repo.draftSessions);
});

final roomNamesProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(sessionRepositoryProvider).roomNames(),
);
