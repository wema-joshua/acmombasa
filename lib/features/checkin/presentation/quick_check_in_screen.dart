import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../dashboard/presentation/widgets/find_visitor_card.dart';
import '../../dashboard/presentation/widgets/recent_checkins_card.dart';

/// Front-desk page for fast check-in and check-out: find a visitor, then see
/// today's log right below.
class QuickCheckInScreen extends StatelessWidget {
  const QuickCheckInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Check-In', style: AppTextStyles.pageTitle),
          Text(
            'Scan a badge or search by name, member ID or phone to check a visitor in or out.',
            style: AppTextStyles.body,
          ),
          SizedBox(height: AppSpacing.lg),
          FindVisitorCard(),
          SizedBox(height: AppSpacing.lg),
          RecentCheckInsCard(),
        ],
      ),
    );
  }
}
