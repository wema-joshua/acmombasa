import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/domain/app_exception.dart';
import '../../../../core/domain/models.dart';
import '../../../../core/providers.dart';
import '../../../../core/services/badge_printer.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../../../core/utils/text_utils.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/pill.dart';
import '../../application/dashboard_providers.dart';
import '../dialogs/register_visitor_dialog.dart';
import '../dialogs/visitor_history_dialog.dart';

/// "Find a Visitor": search, select, then check in / check out / print badge.
class FindVisitorCard extends ConsumerStatefulWidget {
  const FindVisitorCard({super.key});

  @override
  ConsumerState<FindVisitorCard> createState() => _FindVisitorCardState();
}

class _FindVisitorCardState extends ConsumerState<FindVisitorCard> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  List<Visitor> _results = const [];
  String? _selectedId;
  bool _searched = false;
  bool _searching = false;
  bool _busy = false;

  String? _purposeKey;
  bool _assignWorkstation = true;

  String? _notice;
  bool _noticeIsError = false;

  // Latest data seen during build, used by the F2 shortcut.
  VisitorSummary? _currentSummary;
  List<PurposeOption> _currentOptions = const [PurposeOption.general];

  static const _generalKey = 'general';

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- actions

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _selectedId = null;
        _notice = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _notice = null;
    });
    try {
      // A scanned member ID or full phone number should jump straight in.
      final repo = ref.read(visitorRepositoryProvider);
      final exact = await repo.findByScan(query);
      final results = exact != null ? [exact] : await repo.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
        _selectedId = results.length == 1 ? results.first.id : null;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _notice = friendlyError(e);
        _noticeIsError = true;
      });
    }
  }

  void _select(Visitor visitor) {
    setState(() {
      _selectedId = visitor.id;
      _notice = null;
    });
  }

  Future<void> _registerNew() async {
    final visitor =
        await showRegisterVisitorDialog(context, initialQuery: _search.text);
    if (visitor == null || !mounted) return;
    setState(() {
      _search.text = visitor.fullName;
      _results = [visitor];
      _searched = true;
      _selectedId = visitor.id;
      _notice = null;
    });
  }

  PurposeOption _optionFor(List<PurposeOption> options) {
    for (final o in options) {
      if ((o.programId ?? _generalKey) == _purposeKey) return o;
    }
    return options.first;
  }

  Future<void> _primaryAction() async {
    final summary = _currentSummary;
    if (summary == null || _busy) return;
    if (summary.isInside) {
      await _checkOut(summary);
    } else {
      await _checkIn(summary);
    }
  }

  Future<void> _checkIn(VisitorSummary summary) async {
    final staff = ref.read(sessionProvider);
    if (staff == null) return;
    final option = _optionFor(_currentOptions);

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await ref.read(visitRepositoryProvider).checkIn(
            visitor: summary.visitor,
            staffId: staff.id,
            purpose: option.label,
            programId: option.programId,
            assignWorkstation: _assignWorkstation,
          );
      if (!mounted) return;
      if (result.workstationFull) {
        setState(() {
          _notice = 'Checked in, but all workstations are in use.';
          _noticeIsError = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = friendlyError(e);
        _noticeIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut(VisitorSummary summary) async {
    final open = summary.openVisit;
    if (open == null) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref.read(visitRepositoryProvider).checkOut(open.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = friendlyError(e);
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printBadge(VisitorSummary summary) async {
    try {
      await BadgePrinter.print(
        visitor: summary.visitor,
        visit: summary.openVisit ?? summary.latestTodayVisit,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = 'Could not open the print dialog.';
        _noticeIsError = true;
      });
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(purposeOptionsProvider).asData?.value ??
        const [PurposeOption.general];
    _currentOptions = options;

    final summary = _selectedId == null
        ? null
        : ref.watch(visitorSummaryProvider(_selectedId!)).asData?.value;
    _currentSummary = summary;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _primaryAction,
      },
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 6),
            const Text(
              'Quick lookup by phone, name, or assigned ID to record '
              'attendance with 1-click.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            _buildSearchRow(),
            if (_searched && _selectedId == null) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildResults(),
            ],
            if (_notice != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _Notice(text: _notice!, isError: _noticeIsError),
            ],
            const SizedBox(height: AppSpacing.md),
            if (summary != null)
              _buildVisitorPanel(summary, options)
            else if (_selectedId != null)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _buildEmptyPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.person_search, size: 22, color: AppColors.brightBlue),
        const SizedBox(width: 8),
        const Text('Find a Visitor', style: AppTextStyles.cardTitle),
        const Spacer(),
        Flexible(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            onTap: _searchFocus.requestFocus,
            child: const Tooltip(
              message: 'Scan a card or type, then press Enter',
              child: Pill(
                label: 'RFID/Scanner Armed',
                icon: Icons.sensors,
                background: AppColors.neutralSoft,
                foreground: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchRow() {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: c),
        );

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            autofocus: true,
            style: AppTextStyles.bodyStrong,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by name, phone or ID',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _search.clear();
                        _runSearch();
                        _searchFocus.requestFocus();
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: border(AppColors.borderStrong),
              enabledBorder: border(AppColors.borderStrong),
              focusedBorder: border(AppColors.brightBlue),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: _searching ? null : _runSearch,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: _searching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.white),
                )
              : const Text('SEARCH'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _registerNew,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('New'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.americanRed,
            side: BorderSide(
                color: AppColors.americanRed.withValues(alpha: 0.45)),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.neutralSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_off, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('No visitor matches that search.',
                  style: AppTextStyles.body),
            ),
            TextButton(
              onPressed: _registerNew,
              child: const Text('Register new visitor'),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _results.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            InkWell(
              onTap: () => _select(_results[i]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    InitialsAvatar(
                        initials: initialsOf(_results[i].fullName), size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_results[i].fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyStrong),
                    ),
                    Text(
                      '${_results[i].memberId}  •  '
                      '${PhoneUtils.format(_results[i].phone)}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceTinted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: const Color(0xFFD6E4FF)),
      ),
      child: const Column(
        children: [
          Icon(Icons.badge_outlined, size: 36, color: AppColors.textFaint),
          SizedBox(height: 10),
          Text('Search for a visitor to check them in.',
              style: AppTextStyles.bodyStrong),
          SizedBox(height: 4),
          Text(
            'Type a name, phone number or member ID, or scan a card. '
            'Not registered yet? Use New.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorPanel(
    VisitorSummary summary,
    List<PurposeOption> options,
  ) {
    final visitor = summary.visitor;
    final last = summary.lastVisit;
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceTinted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: const Color(0xFFD6E4FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Pill(
                      label: visitor.isVerified
                          ? 'Active Member • Verified Profile'
                          : 'Active Member • Unverified',
                      background: visitor.isVerified
                          ? AppColors.successSoft
                          : AppColors.warningSoft,
                      foreground: visitor.isVerified
                          ? AppColors.success
                          : AppColors.warning,
                      icon: Icons.verified_outlined,
                    ),
                    Pill(label: visitor.memberId),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  last == null
                      ? 'First visit'
                      : 'Last visited: ${DateFormatter.shortDate(last.checkInAt)} '
                          '(${DateFormatter.relativeDay(last.checkInAt, now)})',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(initials: initialsOf(visitor.fullName), size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            visitor.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle,
                          ),
                        ),
                        if (visitor.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified,
                              size: 16, color: AppColors.brightBlue),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(visitor.email ?? 'No email on file',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption),
                    Text(
                      PhoneUtils.format(visitor.phone),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.brightBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('MEMBER SINCE', style: AppTextStyles.label),
                  Text(DateFormatter.longDate(visitor.registeredAt),
                      style: AppTextStyles.bodyStrong),
                  const SizedBox(height: 8),
                  const Text('CUMULATIVE ATTENDANCE',
                      style: AppTextStyles.label),
                  Text(
                    '${summary.totalVisits} '
                    '${summary.totalVisits == 1 ? 'visit' : 'visits'} total',
                    style: AppTextStyles.bodyStrong,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPurposeField(summary, options)),
              const SizedBox(width: 14),
              Expanded(child: _buildResources(summary)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _buildActionRow(summary),
          const SizedBox(height: 12),
          _buildStatusBanner(summary),
        ],
      ),
    );
  }

  Widget _buildPurposeField(
    VisitorSummary summary,
    List<PurposeOption> options,
  ) {
    final selected = _optionFor(options);
    final locked = summary.isInside;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Purpose of Visit', style: AppTextStyles.bodyStrong),
            ),
            InkWell(
              onTap: () => showVisitorHistoryDialog(context, summary.visitor),
              child: Text(
                'Privacy Activity',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.brightBlue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: locked ? AppColors.neutralSoft : AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected.programId ?? _generalKey,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              style: AppTextStyles.bodyStrong,
              items: [
                for (final o in options)
                  DropdownMenuItem(
                    value: o.programId ?? _generalKey,
                    child: Text(o.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: locked ? null : (v) => setState(() => _purposeKey = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResources(VisitorSummary summary) {
    final locked = summary.isInside;
    final assigned = summary.openVisit?.workstation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Terminal Resources', style: AppTextStyles.bodyStrong),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: locked ? AppColors.neutralSoft : AppColors.white,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Row(
            children: [
              Checkbox(
                value: locked ? assigned != null : _assignWorkstation,
                visualDensity: VisualDensity.compact,
                onChanged: locked
                    ? null
                    : (v) => setState(() => _assignWorkstation = v ?? false),
              ),
              Expanded(
                child: Text(
                  locked && assigned != null
                      ? 'Assigned Public Workstation: $assigned'
                      : 'Assign Public Workstation',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(VisitorSummary summary) {
    final inside = summary.isInside;

    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : _primaryAction,
            style: FilledButton.styleFrom(
              backgroundColor:
                  inside ? AppColors.americanRed : AppColors.brightBlue,
              minimumSize: const Size(0, 48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        inside
                            ? Icons.logout_outlined
                            : Icons.how_to_reg_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          inside ? 'CHECK OUT VISITOR' : 'CHECK IN VISITOR',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child:
                            const Text('F2', style: TextStyle(fontSize: 10.5)),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () => _printBadge(summary),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print Badge'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(VisitorSummary summary) {
    final first = summary.visitor.fullName.split(' ').first;
    final open = summary.openVisit;
    final latest = summary.latestTodayVisit;

    if (open != null) {
      final ws = open.workstation == null
          ? ''
          : ' • Assigned to ${open.workstation}';
      return _StatusBanner(
        icon: Icons.check_circle,
        color: AppColors.success,
        background: AppColors.successSoft,
        border: const Color(0xFFBBF7D0),
        bold: '$first checked in today at ${DateFormatter.time12(open.checkInAt)}',
        rest: '$ws (${open.purpose})',
      );
    }
    if (latest != null && latest.checkOutAt != null) {
      return _StatusBanner(
        icon: Icons.logout,
        color: AppColors.textSecondary,
        background: AppColors.neutralSoft,
        border: AppColors.border,
        bold: '$first checked out at ${DateFormatter.time12(latest.checkOutAt!)}',
        rest: ' • Visited from ${DateFormatter.time12(latest.checkInAt)}',
      );
    }
    return const _StatusBanner(
      icon: Icons.info_outline,
      color: AppColors.info,
      background: AppColors.infoSoft,
      border: Color(0xFFBFD4FF),
      bold: 'Not checked in yet today',
      rest: ' • Choose a purpose and check in.',
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.bold,
    required this.rest,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final Color border;
  final String bold;
  final String rest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: bold,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: rest),
                ],
              ),
              style: TextStyle(color: color, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.americanRed : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isError ? AppColors.dangerSoft : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
