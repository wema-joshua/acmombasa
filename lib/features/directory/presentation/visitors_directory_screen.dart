import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/domain/directory_models.dart';
import '../../../core/services/report_exporters.dart';
import '../../../core/services/visit_exporter.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/pill.dart';
import '../../dashboard/presentation/dialogs/register_visitor_dialog.dart';
import '../../shell/presentation/widgets/sync_status_chip.dart';
import '../application/directory_providers.dart';
import 'widgets/visitor_detail_panel.dart';
import 'widgets/visitor_list_panel.dart';

class VisitorsDirectoryScreen extends ConsumerStatefulWidget {
  const VisitorsDirectoryScreen({super.key});

  @override
  ConsumerState<VisitorsDirectoryScreen> createState() =>
      _VisitorsDirectoryScreenState();
}

class _VisitorsDirectoryScreenState
    extends ConsumerState<VisitorsDirectoryScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      ref.read(directoryQueryProvider.notifier).setSearch(value);
    });
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await ref
          .read(directoryRepositoryProvider)
          .loadRows(ref.read(directoryQueryProvider));
      final file = await ReportExporters.exportDirectory(rows);
      messenger.showSnackBar(SnackBar(
        content: Text('Exported ${rows.length} visitors to ${file.path}'),
        action: SnackBarAction(
            label: 'Show', onPressed: () => VisitExporter.reveal(file)),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _register() async {
    final visitor =
        await showRegisterVisitorDialog(context, initialQuery: _search.text);
    if (visitor != null) {
      ref.read(selectedVisitorIdProvider.notifier).set(visitor.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(directorySummaryProvider).asData?.value;
    final query = ref.watch(directoryQueryProvider);
    final categories = ref.watch(directoryCategoriesProvider).asData?.value ?? const [];
    final notifier = ref.read(directoryQueryProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _searchFocus.requestFocus,
      },
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
                const Text('Visitors Directory', style: AppTextStyles.pageTitle),
                Pill(
                  label:
                      '${groupThousands(summary?.totalVisitors ?? 0)} Active Members',
                  background: AppColors.infoSoft,
                  foreground: AppColors.info,
                ),
                Pill(
                  label: '${summary?.insideNow ?? 0} Inside Terminal',
                  background: AppColors.successSoft,
                  foreground: AppColors.success,
                  dotColor: AppColors.successDot,
                ),
                const SyncStatusChip(),
                OutlinedButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Export Directory'),
                ),
                FilledButton.icon(
                  onPressed: _register,
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.americanRed),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Register New Visitor'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 380,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: _onSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search name, member ID, phone or email (Ctrl+K)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _dropdown<String?>(
                  value: query.category,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Categories')),
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: notifier.setCategory,
                ),
                _dropdown<DirectoryStatus>(
                  value: query.status,
                  items: const [
                    DropdownMenuItem(
                        value: DirectoryStatus.all, child: Text('All Statuses')),
                    DropdownMenuItem(
                        value: DirectoryStatus.insideNow, child: Text('Inside Now')),
                    DropdownMenuItem(
                        value: DirectoryStatus.active, child: Text('Active')),
                    DropdownMenuItem(
                        value: DirectoryStatus.inactive, child: Text('Inactive')),
                  ],
                  onChanged: (v) => notifier.setStatus(v ?? DirectoryStatus.all),
                ),
                _dropdown<DirectorySort>(
                  value: query.sort,
                  items: const [
                    DropdownMenuItem(
                        value: DirectorySort.recentVisit,
                        child: Text('Sort: Recent Visit')),
                    DropdownMenuItem(
                        value: DirectorySort.nameAsc, child: Text('Sort: Name A–Z')),
                    DropdownMenuItem(
                        value: DirectorySort.mostVisits,
                        child: Text('Sort: Most Visits')),
                    DropdownMenuItem(
                        value: DirectorySort.newestMember,
                        child: Text('Sort: Newest Member')),
                  ],
                  onChanged: (v) => notifier.setSort(v ?? DirectorySort.recentVisit),
                ),
                TextButton(
                  onPressed: () {
                    _search.clear();
                    notifier.reset();
                  },
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 11, child: VisitorListPanel()),
                  SizedBox(width: AppSpacing.md),
                  Expanded(flex: 9, child: VisitorDetailPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
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
