import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/domain/program_models.dart';
import '../../../core/services/report_pdf.dart';
import '../../../core/sync/sync_controller.dart';
import '../../shell/presentation/widgets/sync_status_chip.dart';
import '../application/programs_providers.dart';
import 'dialogs/create_program_dialog.dart';
import 'dialogs/drafts_dialog.dart';
import 'widgets/day_summary_cards.dart';
import 'widgets/roster_panel.dart';
import 'widgets/schedule_panel.dart';

class ProgramsScreen extends ConsumerWidget {
  const ProgramsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(scheduleDayProvider);
    final summary = ref.watch(daySummaryProvider).asData?.value;
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const <SessionView>[];
    final selectedId = ref.watch(selectedSessionIdProvider);
    final draftCount = ref.watch(draftSessionsProvider).asData?.value.length ?? 0;

    // Keep a valid selection: fall back to the live (or first) session.
    SessionView? selected = sessions.where((s) => s.program.id == selectedId).firstOrNull;
    selected ??= sessions.where((s) => s.phase == SessionPhase.inSession).firstOrNull ??
        sessions.firstOrNull;

    final messenger = ScaffoldMessenger.of(context);

    Future<void> create() async {
      final created = await showCreateProgramDialog(context, day: day);
      if (created != null) {
        if (created.status == 'published') {
          ref.read(selectedSessionIdProvider.notifier).set(created.id);
          if (created.sessionDate != null) {
            ref.read(scheduleDayProvider.notifier).set(created.sessionDate!);
          }
        }
        messenger.showSnackBar(SnackBar(
          content: Text(created.status == 'published'
              ? '"${created.name}" published.'
              : '"${created.name}" saved as a draft.'),
        ));
      }
    }

    Future<void> printSheet() async {
      final s = selected;
      if (s == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Select a session first.')));
        return;
      }
      try {
        final entries = await ref.read(sessionRepositoryProvider).roster(s.program.id, s.day);
        final bytes = await ReportPdf.attendanceSheet(session: s, entries: entries);
        await Printing.layoutPdf(
          name: 'Attendance ${s.program.name}',
          onLayout: (_) => bytes,
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    Future<void> syncNow() async {
      final msg = await ref.read(syncControllerProvider.notifier).syncNow();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f4): create},
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Programs & Activities Roster', style: AppTextStyles.pageTitle),
                  const SyncStatusChip(),
                  OutlinedButton.icon(
                    onPressed: syncNow,
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Sessions & Rosters'),
                  ),
                  if (draftCount > 0)
                    OutlinedButton.icon(
                      onPressed: () => showDraftsDialog(context),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: Text('Drafts ($draftCount)'),
                    ),
                  OutlinedButton.icon(
                    onPressed: printSheet,
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Print Daily Attendance Sheet'),
                  ),
                  FilledButton.icon(
                    onPressed: create,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create New Program / Session  F4'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Schedule, coordinate, and track real-time attendee check-ins across American Spaces cultural, educational, and tech programs.',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppSpacing.md),
              if (summary != null)
                DaySummaryCards(
                  summary: summary,
                  isToday: DateUtils.isSameDay(day, DateTime.now()),
                ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(flex: 8, child: SchedulePanel()),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 13,
                      child: selected == null
                          ? const Card(
                              child: Center(
                                child: Text('Select a session to see its roster.',
                                    style: AppTextStyles.body),
                              ),
                            )
                          : RosterPanel(key: ValueKey(selected.program.id), session: selected),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
