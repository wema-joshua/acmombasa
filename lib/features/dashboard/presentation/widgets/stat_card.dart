import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/dashboard_models.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.data});

  final StatCardData data;

  @override
  Widget build(BuildContext context) {
    final positive = data.tone == FooterTone.positive;
    final footerColor = positive ? AppColors.success : AppColors.textMuted;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        data.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label,
                      ),
                    ),
                    if (data.live) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.successDot,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.infoSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(data.icon, size: 18, color: AppColors.brightBlue),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(data.value, style: AppTextStyles.statValue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  data.unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body,
                ),
              ),
            ],
          ),
          if (data.progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: LinearProgressIndicator(
                value: data.progress,
                minHeight: 6,
                backgroundColor: AppColors.border,
                color: AppColors.successDot,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (positive) ...[
                const Icon(Icons.trending_up,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  data.footer,
                  style: AppTextStyles.caption.copyWith(
                    color: footerColor,
                    fontWeight: positive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
