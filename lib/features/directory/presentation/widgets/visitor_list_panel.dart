import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/domain/directory_models.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/pill.dart';
import '../../application/directory_providers.dart';

class VisitorListPanel extends ConsumerStatefulWidget {
  const VisitorListPanel({super.key});

  @override
  ConsumerState<VisitorListPanel> createState() => _VisitorListPanelState();
}

class _VisitorListPanelState extends ConsumerState<VisitorListPanel> {
  bool _dense = false;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(directoryRowsProvider);
    final selected = ref.watch(selectedVisitorIdProvider);
    final pageSize = _dense ? 12 : 7;

    // Back to page 1 whenever the filters change.
    ref.listen(directoryQueryProvider, (_, _) => setState(() => _page = 0));

    return AppCard(
      padding: EdgeInsets.zero,
      child: rowsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load visitors.\n$e')),
        data: (rows) {
          final pages = (rows.length / pageSize).ceil().clamp(1, 100000);
          final page = _page.clamp(0, pages - 1);
          final slice = rows.skip(page * pageSize).take(pageSize).toList();
          final now = DateTime.now();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    const Text('VISITORS', style: AppTextStyles.label),
                    const SizedBox(width: 8),
                    Text('${groupThousands(rows.length)} found',
                        style: AppTextStyles.caption),
                    const Spacer(),
                    const Text('Dense View', style: AppTextStyles.caption),
                    Switch(
                      value: _dense,
                      onChanged: (v) => setState(() {
                        _dense = v;
                        _page = 0;
                      }),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: slice.isEmpty
                    ? const Center(
                        child: Text('No visitors match these filters.',
                            style: AppTextStyles.body))
                    : ListView.separated(
                        itemCount: slice.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _row(slice[i], selected, now),
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed:
                          page > 0 ? () => setState(() => _page = page - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Page ${page + 1} of $pages', style: AppTextStyles.caption),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: page < pages - 1
                          ? () => setState(() => _page = page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(DirectoryRow r, String? selected, DateTime now) {
    final isSelected = r.visitor.id == selected;
    final (label, bg, fg) = switch (r.status) {
      RowStatus.insideNow => ('Inside Now', AppColors.successSoft, AppColors.success),
      RowStatus.checkedOut => ('Checked Out', AppColors.infoSoft, AppColors.info),
      RowStatus.active => ('Active', AppColors.neutralSoft, AppColors.textSecondary),
      RowStatus.inactive => ('Inactive', AppColors.warningSoft, AppColors.warning),
    };
    return InkWell(
      onTap: () => ref.read(selectedVisitorIdProvider.notifier).set(r.visitor.id),
      child: Container(
        color: isSelected ? AppColors.surfaceTinted : null,
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: _dense ? 6 : 12),
        child: Row(
          children: [
            InitialsAvatar(
              initials: initialsOf(r.visitor.fullName),
              size: _dense ? 28 : 38,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.visitor.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyStrong),
                  Text('${r.visitor.memberId} • ${r.visitor.category}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                r.lastVisitAt == null
                    ? 'No visits yet'
                    : 'Last: ${dayLabel(r.lastVisitAt!, now)}',
                style: AppTextStyles.caption,
              ),
            ),
            SizedBox(
              width: 70,
              child: Text('${r.totalVisits} visits', style: AppTextStyles.caption),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: Align(
                alignment: Alignment.centerRight,
                child: Pill(label: label, background: bg, foreground: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Kept for the detail panel's "Member since" line.
String memberSince(DateTime d) => DateFormatter.shortDate(d);
