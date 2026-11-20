import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_controller.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../directory/presentation/visitors_directory_screen.dart';
import '../../history/presentation/visit_history_screen.dart';
import '../../checkin/presentation/quick_check_in_screen.dart';
import '../../programs/presentation/programs_screen.dart';
import '../../register/presentation/register_visitor_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../domain/nav_destination.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/app_top_bar.dart';

/// Top bar + sidebar + the currently selected module.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  NavDestination _selected = NavDestination.dashboard;

  @override
  void initState() {
    super.initState();
    // Begin background cloud sync (does nothing when cloud isn't configured).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncControllerProvider.notifier).start();
    });
  }

  Future<void> _signOut() async {
    await ref.read(sessionProvider.notifier).signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => SignInScreen(
          mode: AuthMode.signIn,
          onSignedIn: (ctx) => Navigator.of(ctx).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const AppShell()),
          ),
        ),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 960;
          return Column(
            children: [
              AppTopBar(compact: compact, onSignOut: _signOut),
              Expanded(
                child: Row(
                  children: [
                    AppSidebar(
                      selected: _selected,
                      compact: compact,
                      onSelected: (d) => setState(() => _selected = d),
                    ),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    return switch (_selected) {
      NavDestination.dashboard => const DashboardScreen(),
      NavDestination.quickCheckIn => const QuickCheckInScreen(),
      NavDestination.registerVisitor => const RegisterVisitorScreen(),
      NavDestination.visitorsDirectory => const VisitorsDirectoryScreen(),
      NavDestination.visitHistory => const VisitHistoryScreen(),
      NavDestination.programsAndActivities => const ProgramsScreen(),
      NavDestination.reports => const ReportsScreen(),
      NavDestination.settings => const SettingsScreen(),
    };
  }
}
