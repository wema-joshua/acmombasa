import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/domain/app_exception.dart';
import '../../../../core/domain/models.dart';
import '../../../../core/providers.dart';
import '../../../../core/services/badge_printer.dart';
import '../../../../core/services/visit_exporter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/pill.dart';
import '../../application/dashboard_providers.dart';

enum _LogFilter { all, insideNow, checkedOut }

class RecentCheckInsCard extends ConsumerStatefulWidget {
  const RecentCheckInsCard({super.key});

  @override
  ConsumerState<RecentCheckInsCard> createState() => _RecentCheckInsCardState();
}

class _RecentCheckInsCardState extends ConsumerState<RecentCheckInsCard> {
  static const double _minTableWidth = 900;
  // Column flex values: name, card, time, purpose, status, actions.
  static const List<int> _flex = [28, 18, 14, 22, 20, 18];
  static const List<String> _headers = [
    'VISITOR NAME',
    'ID / CARD NUMBER',
    'CHECK-IN TIME',
    'VISIT PURPOSE',
    'STATUS',
    'ACTIONS',
  ];
  static const int _pageSize = 25;

  _LogFilter _filter = _LogFilter.all;
  int _visibleCount = _pageSize;
  bool _exporting = false;

  void _toast(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: action,
        duration: const Duration(seconds: 4),
      ));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<void> _export(List<VisitLogEntry> all) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await VisitExporter.exportDay(DateTime.now(), all);
      if (!mounted) return;
      _toast(
        'Saved ${all.length} ${all.length == 1 ? 'row' : 'rows'} to ${file.path}',
        action: SnackBarAction(
          label: 'Show',
          onPressed: () => VisitExporter.reveal(file),
        ),
      );
    } catch (_) {
      if (mounted) _toast('Could not save the daily sheet.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(todayLogProvider).asData?.value ?? const <VisitLogEntry>[];
    final inside = all.where((e) => e.isInside).toList();
    final out = all.where((e) => !e.isInside).toList();

    final filtered = switch (_filter) {
      _LogFilter.all => all,
      _LogFilter.insideNow => inside,
      _LogFilter.checkedOut => out,
    };
    final shown = filtered.take(_visibleCount).toList();

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _buildHeader(all, inside.length, out.length),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(constraints.maxWidth, _minTableWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      _buildHeaderRow(),
                      if (shown.isEmpty) _buildEmptyRow(),
                      for (final entry in shown) _buildDataRow(entry),
                    ],
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${shown.length} of ${filtered.length} '
                    'check-ins today',
                    style: AppTextStyles.caption,
                  ),
                ),
                if (shown.length < filtered.length)
                  TextButton(
                    onPressed: () =>
                        setState(() => _visibleCount += _pageSize),
                    child: const Text('Show more'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Text(
          'No check-ins to show yet today.',
          style: AppTextStyles.body,
        ),
      ),
    );
  }

  Widget _buildHeader(List<VisitLogEntry> all, int inside, int out) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 22, color: AppColors.brightBlue),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Recent Check-Ins & Real-Time Log',
                      style: AppTextStyles.cardTitle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                'Continuous chronological terminal transaction log for '
                'American Corner Mombasa.',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterTabs(
              selected: _filter,
              counts: {
                _LogFilter.all: all.length,
                _LogFilter.insideNow: inside,
                _LogFilter.checkedOut: out,
              },
              onChanged: (f) => setState(() {
                _filter = f;
                _visibleCount = _pageSize;
              }),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _export(all),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Export Daily Sheet'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border.symmetric(
          horizontal: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _headers.length; i++)
            Expanded(
              flex: _flex[i],
              child: Text(_headers[i], style: AppTextStyles.label),
            ),
        ],
      ),
    );
  }

  Widget _buildDataRow(VisitLogEntry e) {
    final inside = e.isInside;
    final actionColor = inside ? AppColors.americanRed : AppColors.brightBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _flex[0],
            child: Row(
              children: [
                InitialsAvatar(initials: initialsOf(e.visitor.fullName), size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.visitor.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyStrong),
                      Text(e.visitor.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: _flex[1],
            child: Align(
              alignment: Alignment.centerLeft,
              child: Pill(label: e.visitor.memberId, fontSize: 11),
            ),
          ),
          Expanded(
            flex: _flex[2],
            child: Text(DateFormatter.time12(e.visit.checkInAt),
                style: AppTextStyles.bodyStrong),
          ),
          Expanded(
            flex: _flex[3],
            child: Align(
              alignment: Alignment.centerLeft,
              child: Pill(
                label: e.visit.purpose,
                background: AppColors.infoSoft,
                foreground: AppColors.info,
              ),
            ),
          ),
          Expanded(
            flex: _flex[4],
            child: Align(
              alignment: Alignment.centerLeft,
              child: inside
                  ? const Pill(
                      label: 'Checked In',
                      background: AppColors.successSoft,
                      foreground: AppColors.success,
                      dotColor: AppColors.successDot,
                    )
                  : Pill(
                      label: 'Checked Out '
                          '(${DateFormatter.time12(e.visit.checkOutAt!)})',
                    ),
            ),
          ),
          Expanded(
            flex: _flex[5],
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => _guard(() async {
                    final repo = ref.read(visitRepositoryProvider);
                    if (inside) {
                      await repo.checkOut(e.visit.id);
                    } else {
                      final staff = ref.read(sessionProvider);
                      if (staff == null) return;
                      await repo.readmit(previous: e.visit, staffId: staff.id);
                    }
                  }),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: actionColor,
                    side: BorderSide(color: actionColor.withValues(alpha: 0.45)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  child: Text(inside ? 'Check Out' : 'Re-Admit'),
                ),
                IconButton(
                  tooltip: 'Print badge',
                  onPressed: () => _guard(
                    () => BadgePrinter.print(
                      visitor: e.visitor,
                      visit: e.visit,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.badge_outlined,
                      size: 18, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final _LogFilter selected;
  final Map<_LogFilter, int> counts;
  final ValueChanged<_LogFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = <(_LogFilter, String)>[
      (_LogFilter.all, 'All (${counts[_LogFilter.all] ?? 0})'),
      (_LogFilter.insideNow, 'Inside Now (${counts[_LogFilter.insideNow] ?? 0})'),
      (
        _LogFilter.checkedOut,
        'Checked Out (${counts[_LogFilter.checkedOut] ?? 0})'
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.neutralSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd + 2),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (filter, label) in tabs)
            _Tab(
              label: label,
              selected: filter == selected,
              onTap: () => onChanged(filter),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.navy : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.white : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
