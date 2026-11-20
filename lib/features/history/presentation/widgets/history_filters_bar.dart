import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/data/history_repository.dart';
import '../../../../core/domain/history_models.dart';
import '../../../../core/providers.dart';
import '../../../../core/utils/date_format.dart';
import '../../application/history_providers.dart';

class HistoryFiltersBar extends ConsumerStatefulWidget {
  const HistoryFiltersBar({super.key});

  @override
  ConsumerState<HistoryFiltersBar> createState() => _HistoryFiltersBarState();
}

class _HistoryFiltersBarState extends ConsumerState<HistoryFiltersBar> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final f = ref.read(historyFiltersProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: f.start,
        end: f.end.subtract(const Duration(days: 1)).isAfter(now)
            ? now
            : f.end.subtract(const Duration(days: 1)),
      ),
    );
    if (picked != null) {
      ref.read(historyFiltersProvider.notifier).setCustomRange(picked.start, picked.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(historyFiltersProvider);
    final notifier = ref.read(historyFiltersProvider.notifier);
    final rooms = ref.watch(historyRoomsProvider).asData?.value ?? const [];
    final programs = ref.watch(_programsProvider).asData?.value ?? const [];
    final last = f.end.subtract(const Duration(days: 1));

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<HistoryPeriod>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: HistoryPeriod.today, label: Text('Today')),
            ButtonSegment(value: HistoryPeriod.thisWeek, label: Text('This Week')),
            ButtonSegment(value: HistoryPeriod.thisMonth, label: Text('This Month')),
            ButtonSegment(value: HistoryPeriod.custom, label: Text('Custom Range')),
          ],
          selected: {f.period},
          onSelectionChanged: (s) {
            final p = s.first;
            if (p == HistoryPeriod.custom) {
              _pickRange();
            } else {
              notifier.setPeriod(p);
            }
          },
        ),
        InkWell(
          onTap: _pickRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              '${DateFormatter.shortDate(f.start)} – ${DateFormatter.shortDate(last)}'
              '  |  ${f.daysFiltered} Day${f.daysFiltered == 1 ? '' : 's'} Filtered',
              style: AppTextStyles.bodyStrong,
            ),
          ),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 200),
                  () => notifier.setSearch(v));
            },
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search patron, ID, purpose',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        _dropdown<String?>(
          value: f.purposeKey,
          items: [
            const DropdownMenuItem(value: null, child: Text('All Purposes')),
            const DropdownMenuItem(
                value: HistoryRepository.generalKey, child: Text('General Visit')),
            for (final p in programs)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: notifier.setPurpose,
        ),
        _dropdown<String?>(
          value: f.roomKey,
          items: [
            const DropdownMenuItem(value: null, child: Text('All Rooms & Workstations')),
            const DropdownMenuItem(
                value: RoomKeys.workstation, child: Text('Workstations (any)')),
            const DropdownMenuItem(
                value: RoomKeys.noWorkstation, child: Text('No workstation')),
            for (final r in rooms) DropdownMenuItem(value: r, child: Text(r)),
          ],
          onChanged: notifier.setRoom,
        ),
        if (f.hasExtraFilters)
          IconButton(
            tooltip: 'Clear filters',
            onPressed: () {
              _search.clear();
              notifier.clearExtras();
            },
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          style: AppTextStyles.bodyStrong,
        ),
      ),
    );
  }
}

final _programsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(programRepositoryProvider).allPrograms(),
);
