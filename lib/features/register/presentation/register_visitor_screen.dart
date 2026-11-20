import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/services/badge_printer.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../dashboard/presentation/dialogs/register_visitor_dialog.dart';
import '../../dashboard/presentation/dialogs/visitor_history_dialog.dart';
import '../application/register_providers.dart';

class RegisterVisitorScreen extends ConsumerWidget {
  const RegisterVisitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentRegistrationsProvider).asData?.value ?? const [];
    final now = DateTime.now();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Register Visitor', style: AppTextStyles.pageTitle),
          const Text(
            'Create a new member record. The visitor is checked in straight after registering.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.infoSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(Icons.person_add_alt, color: AppColors.brightBlue),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New visitor registration', style: AppTextStyles.cardTitle),
                    Text('Name, phone, purpose and consent are required. Everything else is optional.',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => showRegisterVisitorDialog(context),
                style: FilledButton.styleFrom(backgroundColor: AppColors.americanRed),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Register New Visitor'),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Recently Registered', style: AppTextStyles.cardTitle),
                ),
                const Divider(height: 1),
                if (recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Nobody has been registered yet.', style: AppTextStyles.body),
                  )
                else
                  for (final v in recent) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Row(children: [
                        InitialsAvatar(initials: initialsOf(v.fullName), size: 36),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.fullName, style: AppTextStyles.bodyStrong),
                              Text('${v.memberId} • ${PhoneUtils.format(v.phone)}',
                                  style: AppTextStyles.caption),
                            ],
                          ),
                        ),
                        Text(dayLabel(v.registeredAt, now), style: AppTextStyles.caption),
                        const SizedBox(width: AppSpacing.md),
                        TextButton(
                          onPressed: () => showVisitorHistoryDialog(context, v),
                          child: const Text('History'),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await BadgePrinter.print(visitor: v);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(friendlyError(e))));
                              }
                            }
                          },
                          child: const Text('Print Badge'),
                        ),
                      ]),
                    ),
                    const Divider(height: 1),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
