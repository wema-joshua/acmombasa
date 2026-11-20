import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/domain/history_models.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/pill.dart';
import '../../application/history_providers.dart';

/// Open visits longer than this are flagged.
const overLimitMinutes = 120;

class TerminalLogTable extends ConsumerStatefulWidget {
  const TerminalLogTable({super.key, required this.entries});

  final List<HistoryEntry> entries;

  @override
  ConsumerState<TerminalLogTable> createState() => _TerminalLogTableState();
}

class _TerminalLogTableState extends ConsumerState<TerminalLogTable> {
  int _pageSize = 10;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(historyFiltersProvider);
    final selected = ref.watch(selectedHistoryEntryIdProvider);
    final entries = widget.entries;
    final pages = (entries.length / _pageSize).ceil().clamp(1, 100000);
    final page = _page.clamp(0, pages - 1);
    final slice = entries.skip(page * _pageSize).take(_pageSize).toList();
    final now = DateTime.now();

    ref.listen(historyFiltersProvider, (_, _) => setState(() => _page = 0));

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                const Text('TERMINAL LOG', style: AppTextStyles.cardTitle),
                const SizedBox(width: 10),
                if (filters.includesToday)
                  const Pill(
                    label: 'Live Feed',
                    background: AppColors.successSoft,
                    foreground: AppColors.success,
                    dotColor: AppColors.successDot,
                  ),
                const Spacer(),
                IconButton(
                  tooltip: filters.newestFirst
                      ? 'Newest first (tap for oldest first)'
                      : 'Oldest first (tap for newest first)',
                  onPressed: ref.read(historyFiltersProvider.notifier).toggleSort,
                  icon: Icon(filters.newestFirst
                      ? Icons.arrow_downward
                      : Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(historyReportProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            color: AppColors.surfaceTinted,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('TIME WINDOW', style: AppTextStyles.label)),
                Expanded(flex: 3, child: Text('PATRON', style: AppTextStyles.label)),
                Expanded(flex: 3, child: Text('PURPOSE', style: AppTextStyles.label)),
                Expanded(flex: 2, child: Text('RESOURCE / ROOM', style: AppTextStyles.label)),
                Expanded(flex: 2, child: Text('OPERATOR', style: AppTextStyles.label)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: slice.isEmpty
                ? const Center(
                    child: Text('No visits match these filters.',
                        style: AppTextStyles.body))
                : ListView.separated(
                    itemCount: slice.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _row(slice[i], selected, now),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text('Rows per page', style: AppTextStyles.caption),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 10, child: Text('10')),
                      DropdownMenuItem(value: 25, child: Text('25')),
                      DropdownMenuItem(value: 50, child: Text('50')),
                    ],
                    onChanged: (v) => setState(() {
                      _pageSize = v ?? 10;
                      _page = 0;
                    }),
                  ),
                ),
                const Spacer(),
                Text('${groupThousands(entries.length)} entries • Page ${page + 1} of $pages',
                    style: AppTextStyles.caption),
                IconButton(
                  onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  onPressed:
                      page < pages - 1 ? () => setState(() => _page = page + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(HistoryEntry e, String? selected, DateTime now) {
    final isSelected = e.visit.id == selected;
    final inMinutes = e.isOpen
        ? now.difference(e.visit.checkInAt).inMinutes
        : e.duration!.inMinutes;
    final over = e.isOpen && inMinutes > overLimitMinutes;

    return InkWell(
      onTap: () =>
          ref.read(selectedHistoryEntryIdProvider.notifier).set(e.visit.id),
      child: Container(
        color: isSelected ? AppColors.surfaceTinted : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.isOpen
                        ? '${DateFormatter.time12(e.visit.checkInAt)} – now'
                        : '${DateFormatter.time12(e.visit.checkInAt)} – '
                            '${DateFormatter.time12(e.visit.checkOutAt!)}',
                    style: AppTextStyles.bodyStrong,
                  ),
                  Row(children: [
                    Text(
                        '${dayLabel(e.visit.checkInAt, now)} • ${formatMinutes(inMinutes)}',
                        style: AppTextStyles.caption),
                    if (over) ...[
                      const SizedBox(width: 6),
                      const Pill(
                        label: 'Over 2h',
                        background: AppColors.dangerSoft,
                        foreground: AppColors.americanRed,
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  InitialsAvatar(initials: initialsOf(e.visitor.fullName), size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.visitor.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyStrong),
                        Text(e.visitor.memberId, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(e.visit.purpose,
                  overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
            ),
            Expanded(
              flex: 2,
              child: Text(e.space,
                  overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
            ),
            Expanded(
              flex: 2,
              child: Text(e.staffName,
                  overflow: TextOverflow.ellipsis, style: AppTextStyles.caption),
            ),
          ],
        ),
      ),
    );
  }
}
