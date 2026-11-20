import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/report_repository.dart';
import '../../../core/database/live_query.dart';
import '../../../core/domain/report_models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/state_holder.dart';

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

/// First day of the month being reported.
final reportMonthProvider = stateHolderProvider<DateTime>(() => ReportRepository.monthStart(DateTime.now()));

final reportMonthsProvider = StreamProvider<List<DateTime>>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(reportRepositoryProvider);
  return watchQuery(db, repo.availableMonths);
});

final monthlyReportProvider = StreamProvider<MonthlyReport>((ref) {
  final db = ref.watch(databaseProvider);
  final repo = ref.watch(reportRepositoryProvider);
  final month = ref.watch(reportMonthProvider);
  return watchQuery(db, () => repo.load(month), every: const Duration(minutes: 1));
});
