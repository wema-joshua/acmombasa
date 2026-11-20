import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/domain/report_models.dart';
import '../../../core/services/report_exporters.dart';
import '../../../core/services/report_pdf.dart';
import '../../../core/services/visit_exporter.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/pill.dart';
import '../application/reports_providers.dart';
import 'widgets/demographics_cards.dart';
import 'widgets/footfall_chart.dart';
import 'widgets/pillar_donut.dart';
import 'widgets/report_kpi_cards.dart';
import 'widgets/report_templates_section.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);
    final months = ref.watch(reportMonthsProvider).asData?.value ?? [month];
    final reportAsync = ref.watch(monthlyReportProvider);
    final report = reportAsync.asData?.value;
    final repo = ref.read(reportRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final label = DateFormatter.monthYear(month).replaceAll(' ', '-');

    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    void saved(File file, String what) {
      messenger.showSnackBar(SnackBar(
        content: Text('$what saved to ${file.path}'),
        action: SnackBarAction(label: 'Show', onPressed: () => VisitExporter.reveal(file)),
      ));
    }

    Future<void> csvReport(String name, Future<List<List<String>>> Function() rows) =>
        guard(() async {
          final file = await ReportExporters.writeCsv('$name-$label.csv', await rows());
          saved(file, 'Report');
        });

    Future<void> excel() => guard(() async {
          final r = report;
          if (r == null) return;
          final rows = <List<String>>[
            ['Measure', 'Value'],
            ['Month', DateFormatter.monthYear(r.month)],
            ['Total visits', '${r.footfall}'],
            ['Monthly target', '${r.target}'],
            ['Previous month', '${r.previousFootfall}'],
            ['Average visits per day', r.dailyAverage.toStringAsFixed(1)],
            ['Unique visitors', '${r.uniqueVisitors}'],
            ['New members', '${r.newMembers}'],
            ['Female %', '${(r.femaleShare * 100).round()}'],
            ['Male %', '${(r.maleShare * 100).round()}'],
            ['Youth 18-35 %', '${(r.youthShare * 100).round()}'],
            [],
            ['Pillar', 'Visits', 'Sessions', 'Unique attendees'],
            for (final l in r.ledger) [l.pillar, '${l.visits}', '${l.sessions}', '${l.uniqueAttendees}'],
            [],
            ['Residence', 'Visitors', 'Share %'],
            for (final s in r.residence) [s.label, '${s.count}', '${(s.fraction * 100).round()}'],
            [],
            ['Age cohort', 'Visitors', 'Share %'],
            for (final s in r.cohorts) [s.label, '${s.count}', '${(s.fraction * 100).round()}'],
          ];
          saved(await ReportExporters.writeCsv('analytics-$label.csv', rows), 'Spreadsheet');
        });

    Future<void> pdfPreview() => guard(() async {
          final r = report;
          if (r == null) return;
          final bytes = await ReportPdf.ecaReport(r);
          await Printing.layoutPdf(name: 'Report $label', onLayout: (_) => bytes);
        });

    Future<void> eca() => guard(() async {
          final r = report;
          if (r == null) return;
          final bytes = await ReportPdf.ecaReport(r);
          saved(await ReportExporters.writeBytes('ECA-report-$label.pdf', bytes), 'ECA report');
        });

    final templates = [
      ReportTemplate(
        badge: 'ECA FORM',
        frequency: 'Monthly',
        title: 'Monthly ECA Statistical Summary',
        description: 'Official statistics: footfall, demographics and pillars, as a PDF.',
        run: eca,
      ),
      ReportTemplate(
        badge: 'FACILITIES',
        frequency: 'Weekly',
        title: 'Venue & Facilitator Utilization Report',
        description: 'Room usage, sessions held and seat fill per program.',
        run: () => csvReport('utilization', () => repo.utilizationRows(month)),
      ),
      ReportTemplate(
        badge: 'PATRON INSIGHTS',
        frequency: 'Monthly',
        title: 'Patron Retention & Return Metrics',
        description: 'New versus returning members and visit counts.',
        run: () => csvReport('retention', () => repo.retentionRows(month)),
      ),
      ReportTemplate(
        badge: 'PARTNER',
        frequency: 'On demand',
        title: 'Partner Joint Attendance Sheet',
        description: 'Attendance per program per day for partner organizations.',
        run: () => csvReport('partner-attendance', () => repo.partnerRows(month)),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Pill(
                label: 'COMPLIANCE BUREAU • U.S. Embassy Nairobi Partner Hub',
                background: AppColors.infoSoft,
                foreground: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reports & Statistical Analytics', style: AppTextStyles.pageTitle),
                    Text(
                      'Generate compliance dashboards and statistical outputs formatted for Bureau of Educational and Cultural Affairs (ECA) quarterly standards and host-partner requirements.',
                      style: AppTextStyles.body,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.borderStrong),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<DateTime>(
                      value: months.contains(month) ? month : months.first,
                      items: [
                        for (final m in months)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              '${m == months.first ? 'Current Month' : 'Month'}: ${DateFormatter.monthYear(m)}',
                              style: AppTextStyles.bodyStrong,
                            ),
                          ),
                      ],
                      onChanged: (m) {
                        if (m != null) ref.read(reportMonthProvider.notifier).set(m);
                      },
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: report == null ? null : excel,
                  icon: const Icon(Icons.table_chart_outlined, size: 16),
                  label: const Text('Excel (CSV)'),
                ),
                OutlinedButton.icon(
                  onPressed: report == null ? null : pdfPreview,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('PDF Export'),
                ),
                FilledButton.icon(
                  onPressed: report == null ? null : eca,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Generate Official ECA Report'),
                ),
              ]),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (report == null)
            SizedBox(
              height: 300,
              child: Center(
                child: reportAsync.hasError
                    ? Text('Could not build the report.\n${reportAsync.error}')
                    : const CircularProgressIndicator(),
              ),
            )
          else
            _Body(report: report, templates: templates),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.report, required this.templates});

  final MonthlyReport report;
  final List<ReportTemplate> templates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportKpiCards(report: report),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 13, child: FootfallChart(report: report)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 8,
              child: PillarDonut(
                report: report,
                onLedger: () => showPillarLedger(context, report),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ResidenceCard(report: report)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: AgeCohortCard(report: report)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReportTemplatesSection(templates: templates),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Privacy: exported ECA reports contain aggregated statistics only. '
                '${groupThousands(report.footfall)} visit records are included for '
                '${DateFormatter.monthYear(report.month)}.',
                style: AppTextStyles.body,
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
