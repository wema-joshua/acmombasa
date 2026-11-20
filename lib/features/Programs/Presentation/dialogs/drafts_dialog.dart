import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/domain/app_exception.dart';
import '../../../../core/utils/date_format.dart';
import '../../application/programs_providers.dart';

/// Lists saved drafts so they can be published or deleted.
Future<void> showDraftsDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _DraftsDialog());
}

class _DraftsDialog extends ConsumerStatefulWidget {
  const _DraftsDialog();

  @override
  ConsumerState<_DraftsDialog> createState() => _DraftsDialogState();
}

class _DraftsDialogState extends ConsumerState<_DraftsDialog> {
  String? _message;
  bool _busy = false;

  Future<void> _publish(Program p) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(sessionRepositoryProvider).publishDraft(p.id);
      if (p.sessionDate != null) {
        ref.read(scheduleDayProvider.notifier).set(p.sessionDate!);
      }
      ref.read(selectedSessionIdProvider.notifier).set(p.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = friendlyError(e);
        });
      }
    }
  }

  Future<void> _delete(Program p) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionRepositoryProvider).cancelSession(p.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(draftSessionsProvider).asData?.value ?? const <Program>[];
    return AlertDialog(
      title: const Text('Draft Sessions'),
      content: SizedBox(
        width: 520,
        child: drafts.isEmpty
            ? const Text('No drafts.', style: AppTextStyles.body)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in drafts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name, style: AppTextStyles.bodyStrong),
                      subtitle: Text(
                        '${p.location} • ${p.sessionDate == null ? 'No date' : DateFormatter.shortDate(p.sessionDate!)}'
                        '${p.startMinute == null ? '' : ' • ${DateFormatter.minutesToTime12(p.startMinute!)}'}',
                        style: AppTextStyles.caption,
                      ),
                      trailing: Wrap(spacing: 4, children: [
                        TextButton(
                          onPressed: _busy ? null : () => _delete(p),
                          child: const Text('Delete'),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _publish(p),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                          child: const Text('Publish'),
                        ),
                      ]),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_message!,
                          style: const TextStyle(color: AppColors.americanRed, fontSize: 13)),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
