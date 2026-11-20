import 'package:flutter/material.dart';

/// Sidebar destinations, in the order shown in the reference design.
enum NavDestination {
  dashboard('Dashboard', Icons.dashboard_outlined),
  quickCheckIn('Quick Check-In', Icons.how_to_reg_outlined),
  registerVisitor('Register Visitor', Icons.person_add_alt_outlined),
  visitorsDirectory('Visitors Directory', Icons.groups_outlined),
  visitHistory('Visit History', Icons.history),
  programsAndActivities('Programs & Activities', Icons.event_note_outlined),
  reports('Reports', Icons.bar_chart_outlined),
  settings('Settings', Icons.settings_outlined);

  const NavDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}
