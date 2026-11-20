import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers.dart';
import '../../../../core/utils/date_format.dart';

Future<void> showVisitorHistoryDialog(BuildContext context, Visitor visitor) {
  return showDialog<void>(
    context: context,
    builder: (_) => _HistoryDialog(visitor: visitor),
  );
}

class _HistoryDialog extends ConsumerWidget {
  const _HistoryDialog({required this.visitor});

  final Visitor visitor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('Privacy Activity: ${visitor.fullName}'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: FutureBuilder<List<Visit>>(
          future: ref.read(visitorRepositoryProvider).history(visitor.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final visits = snapshot.data ?? const <Visit>[];
            if (visits.isEmpty) {
              return const Center(
                child: Text('No visits recorded yet.',
                    style: AppTextStyles.body),
              );
            }
            return ListView.separated(
              itemCount: visits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final v = visits[i];
                final out = v.checkOutAt;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.purpose, style: AppTextStyles.bodyStrong),
                  subtitle: Text(
                    '${DateFormatter.shortDate(v.checkInAt)}  •  '
                    '${DateFormatter.time12(v.checkInAt)} → '
                    '${out == null ? 'still inside' : DateFormatter.time12(out)}',
                    style: AppTextStyles.caption,
                  ),
                  trailing: v.workstation == null
                      ? null
                      : Text(v.workstation!,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
