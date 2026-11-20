import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/data/visit_repository.dart';
import '../../../../core/domain/models.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/pill.dart';
import '../../application/dashboard_providers.dart';

class TodaysActivitiesCard extends ConsumerWidget {
  const TodaysActivitiesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(todaysActivitiesProvider).asData?.value ?? const [];
    final stats = ref.watch(dashboardStatsProvider).asData?.value;
    final anyLive = activities.any((a) => a.isLive);
    final total = activities.fold<int>(0, (sum, a) => sum + a.attendees);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_outlined,
                  size: 22, color: AppColors.brightBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Today's Activities",
                    style: AppTextStyles.cardTitle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: anyLive
                    ? const Pill(
                        label: 'HAPPENING NOW',
                        background: AppColors.successSoft,
                        foreground: AppColors.success,
                        dotColor: AppColors.successDot,
                      )
                    : const Pill(label: 'NONE LIVE'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Scheduled program roster for Mombasa Hub spaces and lab '
            'facilities.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSpacing.md),
          if (activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text('No programs scheduled.', style: AppTextStyles.body),
              ),
            )
          else
            for (final item in activities) _ActivityTile(item),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.neutralSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Total Scheduled Engagement',
                      style: AppTextStyles.bodyStrong),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Pill(
                    label: '$total ${total == 1 ? 'participant' : 'participants'}',
                    background: AppColors.navy,
                    foreground: AppColors.white,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _CapacityBanner(stats: stats),
        ],
      ),
    );
  }
}

IconData _iconFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('conversation')) return Icons.forum_outlined;
  if (n.contains('research') || n.contains('study')) return Icons.menu_book_outlined;
  if (n.contains('culture')) return Icons.palette_outlined;
  if (n.contains('english') || n.contains('toefl')) return Icons.translate;
  if (n.contains('game') || n.contains('maker')) return Icons.sports_esports_outlined;
  return Icons.event_note_outlined;
}

String _scheduleOf(ActivityView v) {
  final p = v.program;
  if (p.startMinute == null || p.endMinute == null) {
    return 'All Day • ${p.location}';
  }
  return '${DateFormatter.minutesToTime12(p.startMinute!)} - '
      '${DateFormatter.minutesToTime12(p.endMinute!)} • ${p.location}';
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile(this.item);

  final ActivityView item;

  @override
  Widget build(BuildContext context) {
    final note = item.isLive ? 'Session currently active' : item.program.note;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: item.isLive ? AppColors.surfaceTinted : AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
        border: Border.all(
          color: item.isLive
              ? AppColors.brightBlue.withValues(alpha: 0.45)
              : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(_iconFor(item.program.name),
                size: 18, color: AppColors.brightBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(item.program.name,
                          style: AppTextStyles.bodyStrong),
                    ),
                    const SizedBox(width: 8),
                    Pill(
                      label: '${item.attendees} '
                          '${item.attendees == 1 ? 'Attendee' : 'Attendees'}',
                      background: AppColors.infoSoft,
                      foreground: AppColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_scheduleOf(item), style: AppTextStyles.caption),
                if (note != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: item.isLive
                              ? AppColors.successDot
                              : AppColors.textFaint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          note,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11,
                            color: item.isLive
                                ? AppColors.success
                                : AppColors.textMuted,
                            fontWeight:
                                item.isLive ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live occupancy summary. (The reference design shows a photo here; this is a
/// branded banner until a real image asset is supplied.)
class _CapacityBanner extends StatelessWidget {
  const _CapacityBanner({required this.stats});

  final DashboardStats? stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final text = s == null
        ? 'Loading occupancy…'
        : '${s.inside} of ${s.capacity} seats in use • '
            '${s.workstationsInUse} of ${VisitRepository.workstationCount} '
            'workstations occupied';

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
      child: Container(
        height: 96,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.navy, Color(0xFF1B4F9C)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                Icons.meeting_room_outlined,
                size: 110,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
