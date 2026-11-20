import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/domain/program_models.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../application/programs_providers.dart';

class SchedulePanel extends ConsumerWidget {
  const SchedulePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(scheduleDayProvider);
    final venue = ref.watch(venueFilterProvider);
    final query = ref.watch(sessionSearchProvider).trim().toLowerCase();
    final selected = ref.watch(selectedSessionIdProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final isToday = DateUtils.isSameDay(day, DateTime.now());

    void shift(int days) => ref.read(scheduleDayProvider.notifier).set(DateTime(day.year, day.month, day.day + days));

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isToday ? "Today's Schedule" : 'Schedule',
                        style: AppTextStyles.cardTitle),
                    Text(DateFormatter.fullDate(day), style: AppTextStyles.caption),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              TextButton(
                onPressed: () => ref.read(scheduleDayProvider.notifier).set(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)),
                child: const Text('Today'),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: () => shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ),
          sessionsAsync.when(
            loading: () => const SizedBox(height: 40),
            error: (_, _) => const SizedBox.shrink(),
            data: (sessions) {
              final venues = sessions.map((s) => s.program.location).toSet().toList()..sort();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    _chip(ref, 'All Venues (${venues.length})', null, venue),
                    for (final v in venues) _chip(ref, v, v, venue),
                  ]),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              onChanged: (v) => ref.read(sessionSearchProvider.notifier).set(v),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search session or facilitator…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: sessionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load sessions.\n$e')),
              data: (all) {
                final sessions = all.where((s) {
                  if (venue != null && s.program.location != venue) return false;
                  if (query.isEmpty) return true;
                  return s.program.name.toLowerCase().contains(query) ||
                      (s.program.facilitator ?? '').toLowerCase().contains(query);
                }).toList();
                if (sessions.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No sessions for this day. Use "Create New Program / Session" to add one.',
                          textAlign: TextAlign.center, style: AppTextStyles.body),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _SessionCard(
                    session: sessions[i],
                    selected: sessions[i].program.id == selected,
                    onTap: () => ref.read(selectedSessionIdProvider.notifier).set(sessions[i].program.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(WidgetRef ref, String label, String? value, String? current) {
    final on = value == current;
    return InkWell(
      onTap: () => ref.read(venueFilterProvider.notifier).set(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.surface,
          border: Border.all(color: on ? AppColors.navy : AppColors.borderStrong),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? Colors.white : AppColors.textSecondary,
            )),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.selected, required this.onTap});

  final SessionView session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = session.program;
    final (label, color) = switch (session.phase) {
      SessionPhase.inSession => (
          'IN SESSION • ${formatMinutes(session.minutesElapsed ?? 0)} elapsed',
          AppColors.success
        ),
      SessionPhase.startingSoon => (
          'STARTING IN ${session.minutesToStart} MIN',
          AppColors.warning
        ),
      SessionPhase.completed => ('COMPLETED', AppColors.textMuted),
      SessionPhase.allDay => ('ALL DAY', AppColors.info),
      SessionPhase.scheduled => ('SCHEDULED', AppColors.info),
    };
    final time = (p.startMinute == null || p.endMinute == null)
        ? 'All day'
        : '${DateFormatter.minutesToTime12(p.startMinute!)} - ${DateFormatter.minutesToTime12(p.endMinute!)}';
    final cap = p.capacity;
    final fill = cap == null || cap == 0 ? null : (session.seatsTaken / cap).clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceTinted : AppColors.surface,
          border: Border.all(
              color: selected ? AppColors.brightBlue : AppColors.border,
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('$label   $time',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16, color: selected ? AppColors.brightBlue : AppColors.textFaint),
            ]),
            const SizedBox(height: 4),
            Text(p.name, style: AppTextStyles.bodyStrong.copyWith(fontSize: 14)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, children: [
              Text(p.location, style: AppTextStyles.caption),
              if (p.facilitator != null) Text(p.facilitator!, style: AppTextStyles.caption),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Text(
                cap == null
                    ? '${session.seatsTaken} registered'
                    : '${session.seatsTaken} / $cap Capacity',
                style: AppTextStyles.caption,
              ),
              if (fill != null) ...[
                const SizedBox(width: 6),
                Text('(${(fill * 100).round()}%)',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
              ],
              const Spacer(),
              Text(Pillars.hashtag(p.pillar),
                  style: const TextStyle(fontSize: 10, color: AppColors.brightBlue)),
            ]),
          ],
        ),
      ),
    );
  }
}
