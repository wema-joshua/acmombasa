import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/data/auth_repository.dart';
import '../../../../core/providers.dart';
import '../../../../core/sync/sync_controller.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/pill.dart';
import '../../../auth/presentation/add_staff_dialog.dart';
import 'cloud_status_dialog.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.onSignOut, this.compact = false});

  static const double height = 68;

  final bool compact;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _Brand(compact: compact),
          const SizedBox(width: AppSpacing.lg),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _StatusCluster(),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _UserMenu(onSignOut: onSignOut),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.desktop_windows_outlined,
            color: AppColors.white,
            size: 22,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'American Corner Mombasa',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong
                      .copyWith(fontSize: 13.5, height: 1.2),
                ),
                const SizedBox(height: 2),
                Text(
                  'Part of American Spaces Global Network',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusCluster extends StatelessWidget {
  const _StatusCluster();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pill(label: 'VISITOR MANAGEMENT'),
        SizedBox(width: 12),
        _DateTimeCapsule(),
        SizedBox(width: 12),
        _CloudStatusPill(),
      ],
    );
  }
}

/// Local database is always the source of truth; this shows the cloud state
/// and opens the sync dialog when tapped.
class _CloudStatusPill extends ConsumerWidget {
  const _CloudStatusPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);

    final (label, background, foreground, dot) = switch (sync.phase) {
      // Same look as the reference design. Changes are still queued locally.
      SyncPhase.notConfigured => (
          'Local Database Connected (Offline Sync Active)',
          AppColors.successSoft,
          AppColors.success,
          AppColors.successDot,
        ),
      SyncPhase.signedOut => (
          'Local Database Connected • Cloud not signed in',
          AppColors.warningSoft,
          AppColors.warning,
          AppColors.warning,
        ),
      SyncPhase.syncing => (
          'Syncing with cloud…',
          AppColors.infoSoft,
          AppColors.info,
          AppColors.brightBlue,
        ),
      SyncPhase.error => (
          'Local Database Connected • Sync failed, will retry',
          AppColors.warningSoft,
          AppColors.warning,
          AppColors.warning,
        ),
      SyncPhase.idle => (
          'Local Database Connected (Offline Sync Active)',
          AppColors.successSoft,
          AppColors.success,
          AppColors.successDot,
        ),
    };

    return Tooltip(
      message: 'Cloud sync status',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: () => showCloudStatusDialog(context),
        child: Pill(
          label: label,
          background: background,
          foreground: foreground,
          dotColor: dot,
        ),
      ),
    );
  }
}

class _DateTimeCapsule extends StatefulWidget {
  const _DateTimeCapsule();

  @override
  State<_DateTimeCapsule> createState() => _DateTimeCapsuleState();
}

class _DateTimeCapsuleState extends State<_DateTimeCapsule> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.neutralSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(DateFormatter.fullDate(_now), style: style),
          Container(
            width: 1,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppColors.borderStrong,
          ),
          const Icon(Icons.schedule, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text('${DateFormatter.time12(_now)} EAT', style: style),
        ],
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink();

    final isAdmin = user.role == AuthRepository.roleAdmin;
    final roleLabel = isAdmin ? 'Administrator' : 'Receptionist';

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 48),
      onSelected: (value) {
        switch (value) {
          case 'add_staff':
            showAddStaffDialog(context);
          case 'sign_out':
            onSignOut();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(user.email, style: AppTextStyles.caption),
        ),
        const PopupMenuDivider(),
        if (isAdmin)
          const PopupMenuItem<String>(
            value: 'add_staff',
            child: Row(
              children: [
                Icon(Icons.person_add_alt_outlined, size: 18),
                SizedBox(width: 10),
                Text('Add staff account'),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'sign_out',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 10),
              Text('Sign out'),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(user.displayName, style: AppTextStyles.bodyStrong),
              Text(roleLabel,
                  style: AppTextStyles.caption.copyWith(fontSize: 11)),
            ],
          ),
          const SizedBox(width: 10),
          InitialsAvatar(
            initials: initialsOf(user.displayName),
            size: 38,
            background: AppColors.brightBlue,
          ),
          const Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
