import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/domain/app_exception.dart';
import '../../../../core/domain/program_models.dart';
import '../../../../core/providers.dart';
import '../../../../core/services/report_exporters.dart';
import '../../../../core/services/visit_exporter.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/pill.dart';
import '../../application/programs_providers.dart';

enum _Tab { all, checkedIn, pending, walkIns }

class RosterPanel extends ConsumerStatefulWidget {
  const RosterPanel({super.key, required this.session});

  final SessionView session;

  @override
  ConsumerState<RosterPanel> createState() => _RosterPanelState();
}

class _RosterPanelState extends ConsumerState<RosterPanel> {
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  _Tab _tab = _Tab.all;
  int _page = 0;
  bool _busy = false;

  static const _pageSize = 6;

  @override
  void dispose() {
    _scan.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isToday => DateUtils.isSameDay(widget.session.day, DateTime.now());

  /// Admit today, or pre-register when the session is on a later day.
  Future<void> admit() async {
    final input = _scan.text.trim();
    if (input.isEmpty) {
      _toast('Scan a badge or type a name / ACM ID first.');
      return;
    }
    final staff = ref.read(sessionProvider);
    if (staff == null) return;

    await _run(() async {
      final visitors = ref.read(visitorRepositoryProvider);
      var visitor = await visitors.findByScan(input);
      if (visitor == null) {
        final matches = await visitors.search(input, limit: 5);
        if (matches.isEmpty) throw const AppException('No visitor found. Register them first.');
        if (matches.length > 1) {
          if (!mounted) return;
          visitor = await showDialog<Visitor>(
            context: context,
            builder: (_) => SimpleDialog(
              title: const Text('Which visitor?'),
              children: [
                for (final m in matches)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(m),
                    child: Text('${m.fullName} • ${m.memberId}'),
                  ),
              ],
            ),
          );
          if (visitor == null) return;
        } else {
          visitor = matches.first;
        }
      }
      final repo = ref.read(sessionRepositoryProvider);
      final program = widget.session.program;
      if (_isToday) {
        await repo.admit(program: program, visitor: visitor, staffId: staff.id);
        _toast('${visitor.fullName} admitted to ${program.name}.');
      } else {
        await repo.preRegister(program: program, visitor: visitor, date: widget.session.day);
        _toast('${visitor.fullName} pre-registered.');
      }
      _scan.clear();
      _scanFocus.requestFocus();
    });
  }

  Future<void> _batchAdmit() async {
    final staff = ref.read(sessionProvider);
    if (staff == null) return;
    await _run(() async {
      final n = await ref
          .read(sessionRepositoryProvider)
          .admitAllRegistered(program: widget.session.program, staffId: staff.id);
      _toast(n == 0 ? 'Nobody is waiting to be admitted.' : '$n attendee${n == 1 ? '' : 's'} admitted.');
    });
  }

  Future<void> _export(List<RosterEntry> entries) => _run(() async {
        final p = widget.session.program;
        final rows = <List<String>>[
          ['Member ID', 'Name', 'Category', 'Status', 'Check-in'],
          for (final e in entries)
            [
              e.visitor.memberId,
              e.visitor.fullName,
              e.visitor.category,
              _statusLabel(e),
              e.visit == null ? '' : DateFormatter.time12(e.visit!.checkInAt),
            ],
        ];
        final safe = p.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
        final file = await ReportExporters.writeCsv(
            'roster-$safe-${DateFormatter.isoDate(widget.session.day)}.csv', rows);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Roster saved to ${file.path}'),
          action: SnackBarAction(label: 'Show', onPressed: () => VisitExporter.reveal(file)),
        ));
      });

  Future<void> _cancelSession() async {
    final p = widget.session.program;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this session?'),
        content: Text(
          '"${p.name}" will be removed from the schedule and from check-in. '
          'Past attendance stays in the history and reports.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep session'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.americanRed),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(sessionRepositoryProvider).cancelSession(p.id);
      ref.read(selectedSessionIdProvider.notifier).set(null);
      _toast('"${p.name}" cancelled.');
    });
  }

  String _statusLabel(RosterEntry e) => switch (e.status) {
        RosterStatus.present => 'Present (${DateFormatter.time12(e.visit!.checkInAt)})',
        RosterStatus.walkIn => 'Walk-in Added (${DateFormatter.time12(e.visit!.checkInAt)})',
        RosterStatus.awaiting => 'Registered / Awaiting',
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final p = s.program;
    final rosterAsync = ref.watch(rosterProvider(p.id));
    final entries = rosterAsync.asData?.value ?? const <RosterEntry>[];

    final present = entries.where((e) => e.status == RosterStatus.present).length;
    final walkIns = entries.where((e) => e.status == RosterStatus.walkIn).length;
    final pending = entries.where((e) => e.status == RosterStatus.awaiting).length;

    final shown = switch (_tab) {
      _Tab.all => entries,
      _Tab.checkedIn => entries.where((e) => e.status != RosterStatus.awaiting).toList(),
      _Tab.pending => entries.where((e) => e.status == RosterStatus.awaiting).toList(),
      _Tab.walkIns => entries.where((e) => e.status == RosterStatus.walkIn).toList(),
    };
    final pages = (shown.length / _pageSize).ceil().clamp(1, 100000);
    final page = _page.clamp(0, pages - 1);
    final slice = shown.skip(page * _pageSize).take(_pageSize).toList();

    final complete = entries.isEmpty
        ? 0
        : entries
                .where((e) =>
                    e.visitor.gender != null &&
                    e.visitor.ageBracket != null &&
                    e.visitor.residence != null)
                .length /
            entries.length;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Row(children: [
                  Expanded(
                    child: Text('OFFICIAL ${p.pillar.toUpperCase()} PROGRAM',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.info,
                            letterSpacing: 0.6)),
                  ),
                  FilledButton(
                    onPressed: (_busy || !_isToday || pending == 0) ? null : _batchAdmit,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.brightBlue),
                    child: const Text('Batch Admit All'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _export(entries),
                    child: const Text('Export CSV'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    enabled: !_busy,
                    onSelected: (v) {
                      if (v == 'cancel') _cancelSession();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'cancel', child: Text('Cancel this session')),
                    ],
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text(p.name, style: AppTextStyles.pageTitle)),
                  if (s.phase == SessionPhase.inSession)
                    const Pill(
                      label: 'Live Check-In',
                      background: AppColors.successSoft,
                      foreground: AppColors.success,
                      dotColor: AppColors.successDot,
                    ),
                ]),
                const SizedBox(height: 6),
                if (p.facilitator != null)
                  Text('Facilitator(s): ${p.facilitator}', style: AppTextStyles.body),
                if (s.minutesRemaining != null)
                  Text('Remaining: ${s.minutesRemaining} mins', style: AppTextStyles.body),
                Text(p.location, style: AppTextStyles.body),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceTinted,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(children: [
                    const Icon(Icons.qr_code_scanner, size: 20, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _scan,
                        focusNode: _scanFocus,
                        onSubmitted: (_) => admit(),
                        decoration: const InputDecoration.collapsed(
                          hintText: 'Scan visitor badge / Name, ACM ID…',
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : admit,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
                      icon: const Icon(Icons.person_add_alt, size: 16),
                      label: Text(_isToday ? 'Admit to Program  F3' : 'Pre-register'),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 6, children: [
                  _tabChip('All Roster (${entries.length})', _Tab.all),
                  _tabChip('Checked-in ($present)', _Tab.checkedIn, count: present + walkIns),
                  _tabChip('Pending / Expected ($pending)', _Tab.pending),
                  _tabChip('Walk-ins ($walkIns)', _Tab.walkIns),
                ]),
                const SizedBox(height: 10),
                const Row(children: [
                  Expanded(flex: 4, child: Text('VISITOR & ACM ID', style: AppTextStyles.label)),
                  Expanded(flex: 4, child: Text('STATUS', style: AppTextStyles.label)),
                  Expanded(flex: 3, child: Text('CATEGORY', style: AppTextStyles.label)),
                ]),
                const Divider(height: 14),
                if (slice.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('No attendees yet. Scan a badge to admit someone.',
                            style: AppTextStyles.body)),
                  )
                else
                  for (final e in slice)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(
                          flex: 4,
                          child: Row(children: [
                            InitialsAvatar(initials: initialsOf(e.visitor.fullName), size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.visitor.fullName,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodyStrong),
                                  Text(e.visitor.memberId, style: AppTextStyles.caption),
                                ],
                              ),
                            ),
                          ]),
                        ),
                        Expanded(flex: 4, child: _statusPill(e)),
                        Expanded(
                          flex: 3,
                          child: Text(e.visitor.category,
                              overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
                        ),
                      ]),
                    ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                      'Showing ${slice.length} of ${shown.length} registered',
                      style: AppTextStyles.caption,
                    ),
                  ),
                  TextButton(
                      onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                      child: const Text('Previous')),
                  Text('${page + 1} / $pages', style: AppTextStyles.caption),
                  TextButton(
                      onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null,
                      child: const Text('Next')),
                ]),
                Row(children: [
                  const Icon(Icons.verified_outlined, size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${(complete * 100).round()}% of this roster has complete ECA demographics recorded.',
                      style: AppTextStyles.caption,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(14),
            color: AppColors.surfaceTinted,
            child: Row(children: [
              const Icon(Icons.build_circle_outlined, size: 20, color: AppColors.brightBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Session Logistics & Physical Equipment',
                        style: AppTextStyles.bodyStrong),
                    Text(
                      p.note ?? 'No equipment or logistics notes recorded for this session.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              Pill(
                label: 'REF ${p.id.substring(0, 6).toUpperCase()}',
                background: AppColors.neutralSoft,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, _Tab tab, {int? count}) {
    final on = _tab == tab;
    return InkWell(
      onTap: () => setState(() {
        _tab = tab;
        _page = 0;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.surface,
          border: Border.all(color: on ? AppColors.navy : AppColors.borderStrong),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? Colors.white : AppColors.textSecondary,
            )),
      ),
    );
  }

  Widget _statusPill(RosterEntry e) {
    final (bg, fg, dot) = switch (e.status) {
      RosterStatus.present => (AppColors.successSoft, AppColors.success, AppColors.successDot),
      RosterStatus.walkIn => (AppColors.infoSoft, AppColors.info, AppColors.brightBlue),
      RosterStatus.awaiting => (AppColors.neutralSoft, AppColors.textSecondary, AppColors.textFaint),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Pill(label: _statusLabel(e), background: bg, foreground: fg, dotColor: dot, fontSize: 10),
    );
  }
}
