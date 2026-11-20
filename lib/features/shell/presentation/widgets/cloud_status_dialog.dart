import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/domain/app_exception.dart';
import '../../../../core/sync/sync_controller.dart';
import '../../../../core/utils/date_format.dart';

Future<void> showCloudStatusDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CloudStatusDialog(),
  );
}

class _CloudStatusDialog extends ConsumerStatefulWidget {
  const _CloudStatusDialog();

  @override
  ConsumerState<_CloudStatusDialog> createState() => _CloudStatusDialogState();
}

class _CloudStatusDialogState extends ConsumerState<_CloudStatusDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await ref
          .read(syncControllerProvider.notifier)
          .signInToCloud(_email.text, _password.text);
      _password.clear();
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final message = await ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) {
      setState(() {
        _busy = false;
        _info = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingSyncCountProvider).asData?.value ?? 0;

    return AlertDialog(
      title: const Text('Cloud sync'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_describe(sync, pending), style: AppTextStyles.body),
            const SizedBox(height: AppSpacing.md),
            if (sync.phase == SyncPhase.notConfigured)
              const Text(
                'This build has no Supabase URL / anon key. Start the app with '
                '--dart-define-from-file=env.json (see SETUP.md). The app keeps '
                'working fully offline in the meantime.',
                style: AppTextStyles.caption,
              )
            else if (sync.phase == SyncPhase.signedOut) ...[
              const Text(
                'Sign in with the Supabase account used for syncing.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Cloud email'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Cloud password'),
                onSubmitted: (_) => _signIn(),
              ),
            ] else
              Text(
                'Signed in as ${sync.cloudEmail ?? 'cloud account'}.',
                style: AppTextStyles.bodyStrong,
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.americanRed, fontSize: 12.5)),
            ],
            if (_info != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_info!,
                  style:
                      const TextStyle(color: AppColors.success, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        if (sync.phase == SyncPhase.idle || sync.phase == SyncPhase.error)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await ref
                        .read(syncControllerProvider.notifier)
                        .signOutOfCloud();
                  },
            child: const Text('Disconnect'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (sync.phase == SyncPhase.signedOut)
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: const Text('Connect'),
          )
        else if (sync.phase != SyncPhase.notConfigured)
          FilledButton(
            onPressed: _busy || sync.phase == SyncPhase.syncing ? null : _syncNow,
            child: const Text('Sync now'),
          ),
      ],
    );
  }

  String _describe(SyncState s, int pending) {
    final queue = '$pending change${pending == 1 ? '' : 's'} waiting to upload.';
    switch (s.phase) {
      case SyncPhase.notConfigured:
        return 'Cloud sync is off. All data is stored on this computer.';
      case SyncPhase.signedOut:
        return 'Cloud sync is ready but not connected. $queue';
      case SyncPhase.syncing:
        return 'Syncing now…';
      case SyncPhase.error:
        return '${s.message ?? 'The last sync failed.'} $queue';
      case SyncPhase.idle:
        final at = s.lastSyncedAt;
        final last = at == null
            ? 'Not synced yet this session.'
            : 'Last synced ${DateFormatter.time12(at)}.';
        return '$last $queue';
    }
  }
}
