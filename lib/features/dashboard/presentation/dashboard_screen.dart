import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/sync/sync_controller.dart';
import '../../../core/widgets/pill.dart';
import '../../kiosk/presentation/kiosk_screen.dart';
import '../../shell/presentation/widgets/cloud_status_dialog.dart';
import '../application/dashboard_providers.dart';
import '../application/stat_cards.dart';
import 'widgets/find_visitor_card.dart';
import 'widgets/recent_checkins_card.dart';
import 'widgets/stat_card.dart';
import 'widgets/todays_activities_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const double _gap = 20;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 700 ? 16.0 : 24.0;
        final inner = constraints.maxWidth - padding * 2;
        final twoColumns = inner >= 980;

        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WelcomeHeader(stacked: inner < 760),
              const SizedBox(height: _gap),
              _StatsGrid(width: inner),
              const SizedBox(height: _gap),
              if (twoColumns)
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: FindVisitorCard()),
                    SizedBox(width: _gap),
                    Expanded(flex: 4, child: TodaysActivitiesCard()),
                  ],
                )
              else ...const [
                FindVisitorCard(),
                SizedBox(height: _gap),
                TodaysActivitiesCard(),
              ],
              const SizedBox(height: _gap),
              const RecentCheckInsCard(),
            ],
          ),
        );
      },
    );
  }
}

class _WelcomeHeader extends ConsumerWidget {
  const _WelcomeHeader({required this.stacked});

  final bool stacked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingSyncCountProvider).asData?.value ?? 0;
    final syncing = ref.watch(syncControllerProvider).phase == SyncPhase.syncing;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Welcome back, Receptionist',
                style: AppTextStyles.pageTitle),
            const Pill(
              label: 'ACTIVE SESSION',
              background: AppColors.infoSoft,
              foreground: AppColors.info,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Front Desk Terminal • Entrance Station 1 • American Corner '
          'Mombasa (KNLS Buruhani)',
          style: AppTextStyles.caption.copyWith(fontSize: 12.5),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: syncing ? null : () => _syncQueue(context, ref),
          icon: syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 18),
          label: Text('Sync Queue ($pending)'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const KioskScreen()),
          ),
          icon: const Icon(Icons.tv_outlined, size: 18),
          label: const Text('Batch Kiosk Mode'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
        ),
      ],
    );

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: AppSpacing.md), actions],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: title),
        const SizedBox(width: AppSpacing.md),
        actions,
      ],
    );
  }

  Future<void> _syncQueue(BuildContext context, WidgetRef ref) async {
    final phase = ref.read(syncControllerProvider).phase;
    // Not configured or not signed in: the dialog explains and offers sign-in.
    if (phase == SyncPhase.notConfigured || phase == SyncPhase.signedOut) {
      await showCloudStatusDialog(context);
      return;
    }
    final message = await ref.read(syncControllerProvider.notifier).syncNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid({required this.width});

  final double width;

  static const double _gap = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final stats = statsAsync.asData?.value;
    if (stats == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final cards = buildStatCards(stats);
    final columns = width >= 900 ? 4 : (width >= 520 ? 2 : 1);

    if (columns == 4) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(child: StatCard(data: cards[i])),
            ],
          ],
        ),
      );
    }

    final itemWidth = (width - _gap * (columns - 1)) / columns;
    return Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: [
        for (final card in cards)
          SizedBox(width: itemWidth, child: StatCard(data: card)),
      ],
    );
  }
}
