import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/domain/history_models.dart';
import '../../../core/services/log_sheet_printer.dart';
import '../../../core/services/report_exporters.dart';
import '../../../core/services/visit_exporter.dart';
import '../../../core/utils/date_format.dart';
import '../../shell/presentation/widgets/sync_status_chip.dart';
import '../application/history_providers.dart';
import 'widgets/history_filters_bar.dart';
import 'widgets/history_kpi_cards.dart';
import 'widgets/session_inspector.dart';
import 'widgets/terminal_log_table.dart';

class VisitHistoryScreen extends ConsumerWidget {
  const VisitHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(historyReportProvider);
    final filters = ref.watch(historyFiltersProvider);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> export(HistoryReport r) async {
      try {
        final file = await ReportExporters.exportHistory(r.entries, filters);
        messenger.showSnackBar(SnackBar(
          content: Text('Exported ${r.entries.length} entries to ${file.path}'),
          action: SnackBarAction(
              label: 'Show', onPressed: () => VisitExporter.reveal(file)),
        ));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    Future<void> printSheet(HistoryReport r) async {
      try {
        final last = filters.end.subtract(const Duration(days: 1));
        await LogSheetPrinter.print(
          entries: r.entries,
          rangeLabel:
              '${DateFormatter.shortDate(filters.start)} – ${DateFormatter.shortDate(last)}',
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    final data = report.asData?.value;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reports  /  Visit History', style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Visit History & Terminal Logs',
                  style: AppTextStyles.pageTitle),
              const SyncStatusChip(style: SyncChipStyle.archive),
              OutlinedButton.icon(
                onPressed: data == null ? null : () => export(data),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Export CSV / Excel'),
              ),
              FilledButton.icon(
                onPressed: data == null ? null : () => printSheet(data),
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print Daily Log Sheet'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Every check-in and check-out recorded at the terminal, newest activity first.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.md),
          if (data != null) HistoryKpiCards(kpis: data.kpis),
          const SizedBox(height: AppSpacing.md),
          const HistoryFiltersBar(),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: report.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load history.\n$e')),
              data: (r) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 13, child: TerminalLogTable(entries: r.entries)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(flex: 7, child: SessionInspector(report: r)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
