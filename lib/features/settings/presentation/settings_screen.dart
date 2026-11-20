import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/data/auth_repository.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/pill.dart';
import '../../auth/presentation/add_staff_dialog.dart';
import '../../shell/presentation/widgets/cloud_status_dialog.dart';
import '../application/settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _capacity = TextEditingController();
  final _target = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _capacity.dispose();
    _target.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _saveNumbers() async {
    final capacity = int.tryParse(_capacity.text.trim());
    final target = int.tryParse(_target.text.trim());
    if (capacity == null || capacity < 1 || capacity > 1000) {
      _toast('Enter a hall capacity between 1 and 1000.');
      return;
    }
    if (target == null || target < 1 || target > 1000000) {
      _toast('Enter a monthly footfall target of at least 1.');
      return;
    }
    setState(() => _busy = true);
    try {
      final settings = ref.read(settingsRepositoryProvider);
      await settings.setCapacity(capacity);
      await settings.setMonthlyTarget(target);
      _toast('Settings saved.');
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStaff(String id, bool active) async {
    final me = ref.read(sessionProvider);
    if (me == null) return;
    try {
      await ref.read(authRepositoryProvider).setStaffActive(
            requester: me,
            staffId: id,
            active: active,
          );
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionProvider);
    final isAdmin = me?.role == AuthRepository.roleAdmin;
    final values = ref.watch(settingsValuesProvider).asData?.value;
    final staff = ref.watch(staffListProvider).asData?.value ?? const [];
    final sync = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingSyncCountProvider).asData?.value ?? 0;

    if (values != null && !_loaded) {
      _loaded = true;
      _capacity.text = '${values.capacity}';
      _target.text = '${values.monthlyTarget}';
    }

    final syncText = switch (sync.phase) {
      SyncPhase.notConfigured => 'Not configured (running offline)',
      SyncPhase.signedOut => 'Configured, not signed in to the cloud account',
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.error => 'Last sync failed, will retry',
      SyncPhase.idle => sync.lastSyncedAt == null
          ? 'Connected'
          : 'Connected, last synced ${DateFormatter.time12(sync.lastSyncedAt!)}',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Settings', style: AppTextStyles.pageTitle),
              const Text('Terminal limits, cloud sync and staff accounts.',
                  style: AppTextStyles.body),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Center Limits & Targets', style: AppTextStyles.cardTitle),
                    const SizedBox(height: 4),
                    const Text(
                      'Hall capacity drives the "Inside now" gauge on the dashboard. '
                      'The monthly target drives the Reports page.',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _capacity,
                          enabled: isAdmin && !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Hall capacity (people)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _target,
                          enabled: isAdmin && !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Monthly footfall target',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: (isAdmin && !_busy) ? _saveNumbers : null,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                        child: const Text('Save'),
                      ),
                    ]),
                    if (!isAdmin)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Only administrators can change these.',
                            style: AppTextStyles.caption),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cloud Sync', style: AppTextStyles.cardTitle),
                        const SizedBox(height: 4),
                        Text(syncText, style: AppTextStyles.body),
                        Text(
                          '$pending record${pending == 1 ? '' : 's'} waiting to upload',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => showCloudStatusDialog(context),
                    child: const Text('Manage Cloud Sync'),
                  ),
                ]),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Staff Accounts', style: AppTextStyles.cardTitle)),
                      FilledButton.icon(
                        onPressed: isAdmin ? () => showAddStaffDialog(context) : null,
                        style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                        icon: const Icon(Icons.person_add_alt, size: 16),
                        label: const Text('Add Staff'),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text(
                      'Staff accounts stay on this terminal and are never uploaded to the cloud.',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final s in staff)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Row(children: [
                          Flexible(child: Text(s.displayName, style: AppTextStyles.bodyStrong)),
                          const SizedBox(width: 8),
                          Pill(
                            label: s.role == AuthRepository.roleAdmin
                                ? 'ADMIN'
                                : 'RECEPTIONIST',
                            background: s.role == AuthRepository.roleAdmin
                                ? AppColors.infoSoft
                                : AppColors.neutralSoft,
                            foreground: s.role == AuthRepository.roleAdmin
                                ? AppColors.info
                                : AppColors.textSecondary,
                          ),
                          if (s.id == me?.id) ...[
                            const SizedBox(width: 6),
                            const Text('(you)', style: AppTextStyles.caption),
                          ],
                        ]),
                        subtitle: Text(s.email, style: AppTextStyles.caption),
                        trailing: Switch(
                          value: s.isActive,
                          onChanged: (isAdmin && s.id != me?.id)
                              ? (v) => _toggleStaff(s.id, v)
                              : null,
                        ),
                      ),
                    if (!isAdmin)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Only administrators can add or switch off accounts.',
                            style: AppTextStyles.caption),
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
