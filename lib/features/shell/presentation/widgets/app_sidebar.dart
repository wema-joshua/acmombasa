import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../domain/nav_destination.dart';
import 'sidebar_nav_item.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  static const double expandedWidth = 232;
  static const double compactWidth = 72;

  final NavDestination selected;
  final ValueChanged<NavDestination> onSelected;

  /// Icon-only rail for narrow windows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? compactWidth : expandedWidth,
      color: AppColors.sidebar,
      child: Column(
        children: [
          if (compact)
            const SizedBox(height: AppSpacing.md)
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('RECEPTION CONSOLE', style: AppTextStyles.sidebarLabel),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final destination in NavDestination.values)
                  SidebarNavItem(
                    destination: destination,
                    selected: destination == selected,
                    compact: compact,
                    onTap: () => onSelected(destination),
                  ),
              ],
            ),
          ),
          _SidebarFooter(compact: compact),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(
      Icons.location_on_outlined,
      size: 16,
      color: AppColors.sidebarText,
    );

    return Container(
      width: double.infinity,
      color: AppColors.sidebarFooter,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: compact
          ? const Center(child: icon)
          : const Row(
              children: [
                icon,
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AMERICAN CORNER MOMBASA:MEWA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sidebarLabel,
                  ),
                ),
              ],
            ),
    );
  }
}
