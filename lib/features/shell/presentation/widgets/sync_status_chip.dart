import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/sync/sync_controller.dart';
import 'cloud_status_dialog.dart';

enum SyncChipStyle {
  /// "Live Sync" / "Syncing…" / "Offline" (Visitors Directory header).
  live,

  /// "Synchronized with SQLite/Cloud Archive" (Visit History header).
  archive,
}

/// Small status chip fed by the real sync state. Tap opens the cloud dialog.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key, this.style = SyncChipStyle.live});

  final SyncChipStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingSyncCountProvider).asData?.value ?? 0;

    final online =
        sync.phase == SyncPhase.idle || sync.phase == SyncPhase.syncing;

    final (String label, Color dot, Color bg, Color fg) = switch (style) {
      SyncChipStyle.live => switch (sync.phase) {
          SyncPhase.syncing => (
              'Syncing…',
              AppColors.brightBlue,
              AppColors.infoSoft,
              AppColors.info,
            ),
          SyncPhase.idle => (
              'Live Sync',
              AppColors.successDot,
              AppColors.successSoft,
              AppColors.success,
            ),
          _ => (
              'Offline',
              AppColors.textFaint,
              AppColors.neutralSoft,
              AppColors.textSecondary,
            ),
        },
      SyncChipStyle.archive => pending > 0
          ? (
              '$pending record${pending == 1 ? '' : 's'} pending sync',
              AppColors.warning,
              AppColors.warningSoft,
              AppColors.warning,
            )
          : online
              ? (
                  'Synchronized with SQLite/Cloud Archive',
                  AppColors.successDot,
                  AppColors.successSoft,
                  AppColors.success,
                )
              : (
                  'Local SQLite Archive (cloud offline)',
                  AppColors.textFaint,
                  AppColors.neutralSoft,
                  AppColors.textSecondary,
                ),
    };

    return Tooltip(
      message: 'Cloud sync status',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: () => showCloudStatusDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
