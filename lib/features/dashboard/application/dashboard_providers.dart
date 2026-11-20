import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/live_query.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers.dart';

/// All of these re-run whenever the local database changes, so every card on
/// the dashboard updates on its own after a check-in, check-out or sync.
final dashboardStatsProvider = StreamProvider<DashboardStats>((ref) {
  final db = ref.watch(databaseProvider);
  final visits = ref.watch(visitRepositoryProvider);
  return watchQuery(db, visits.loadStats, every: const Duration(minutes: 1));
});

final todayLogProvider = StreamProvider<List<VisitLogEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  final visits = ref.watch(visitRepositoryProvider);
  return watchQuery(db, visits.todayLog);
});

/// Re-evaluated every minute so "happening now" follows the clock.
final todaysActivitiesProvider = StreamProvider<List<ActivityView>>((ref) {
  final db = ref.watch(databaseProvider);
  final programs = ref.watch(programRepositoryProvider);
  return watchQuery(
    db,
    programs.todaysActivities,
    every: const Duration(minutes: 1),
  );
});

final purposeOptionsProvider = StreamProvider<List<PurposeOption>>((ref) {
  final db = ref.watch(databaseProvider);
  final programs = ref.watch(programRepositoryProvider);
  return watchQuery(db, programs.purposeOptions);
});

final visitorSummaryProvider =
    StreamProvider.autoDispose.family<VisitorSummary?, String>((ref, visitorId) {
  final db = ref.watch(databaseProvider);
  final visitors = ref.watch(visitorRepositoryProvider);
  return watchQuery(db, () => visitors.summary(visitorId));
});
