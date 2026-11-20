import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/domain/models.dart';
import '../../../core/providers.dart';
import '../../../core/utils/date_format.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../splash/presentation/widgets/splash_background.dart';

enum _KioskMode { checkIn, checkOut }

enum _Kind { success, warning, error }

class _Entry {
  const _Entry(this.kind, this.message, this.time);

  final _Kind kind;
  final String message;
  final DateTime time;
}

/// Full-screen rapid check-in / check-out. A barcode or card scanner types the
/// member ID and presses Enter, so staff can process a queue without the mouse.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final List<_Entry> _entries = [];

  _KioskMode _mode = _KioskMode.checkIn;
  String? _purposeKey;
  bool _working = false;
  int _processed = 0;

  static const _generalKey = 'general';

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(_Kind kind, String message) {
    setState(() {
      _entries.insert(0, _Entry(kind, message, DateTime.now()));
      if (_entries.length > 8) _entries.removeLast();
    });
  }

  Future<void> _process(String raw) async {
    final text = raw.trim();
    _input.clear();
    _focus.requestFocus();
    if (text.isEmpty || _working) return;

    final staff = ref.read(sessionProvider);
    if (staff == null) return;

    setState(() => _working = true);
    try {
      final visitor = await ref.read(visitorRepositoryProvider).findByScan(text);
      if (visitor == null) {
        _add(_Kind.error, 'No visitor found for "$text".');
        return;
      }

      final visits = ref.read(visitRepositoryProvider);
      if (_mode == _KioskMode.checkIn) {
        final options = ref.read(purposeOptionsProvider).asData?.value ??
            const [PurposeOption.general];
        final option = options.firstWhere(
          (o) => (o.programId ?? _generalKey) == _purposeKey,
          orElse: () => options.first,
        );
        await visits.checkIn(
          visitor: visitor,
          staffId: staff.id,
          purpose: option.label,
          programId: option.programId,
        );
        _processed++;
        _add(_Kind.success, '${visitor.fullName} checked in (${option.label}).');
      } else {
        final open = await visits.openVisitFor(visitor.id);
        if (open == null) {
          _add(_Kind.warning, '${visitor.fullName} is not checked in.');
          return;
        }
        await visits.checkOut(open.id);
        _processed++;
        _add(_Kind.success, '${visitor.fullName} checked out.');
      }
    } catch (e) {
      _add(
        e is AppException ? _Kind.warning : _Kind.error,
        friendlyError(e),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(purposeOptionsProvider).asData?.value ??
        const [PurposeOption.general];
    final selected = options.firstWhere(
      (o) => (o.programId ?? _generalKey) == _purposeKey,
      orElse: () => options.first,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SplashBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tv_outlined,
                              color: AppColors.white, size: 26),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Batch Kiosk Mode',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Exit (Esc)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.white,
                              side: const BorderSide(color: AppColors.whiteMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<_KioskMode>(
                              segments: const [
                                ButtonSegment(
                                  value: _KioskMode.checkIn,
                                  label: Text('Check in'),
                                  icon: Icon(Icons.login),
                                ),
                                ButtonSegment(
                                  value: _KioskMode.checkOut,
                                  label: Text('Check out'),
                                  icon: Icon(Icons.logout),
                                ),
                              ],
                              selected: {_mode},
                              onSelectionChanged: (s) {
                                setState(() => _mode = s.first);
                                _focus.requestFocus();
                              },
                            ),
                            if (_mode == _KioskMode.checkIn) ...[
                              const SizedBox(height: AppSpacing.md),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Purpose for everyone scanned',
                                  border: OutlineInputBorder(),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selected.programId ?? _generalKey,
                                    isExpanded: true,
                                    isDense: true,
                                    items: [
                                      for (final o in options)
                                        DropdownMenuItem(
                                          value: o.programId ?? _generalKey,
                                          child: Text(o.label),
                                        ),
                                    ],
                                    onChanged: (v) {
                                      setState(() => _purposeKey = v);
                                      _focus.requestFocus();
                                    },
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _input,
                              focusNode: _focus,
                              autofocus: true,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(fontSize: 22),
                              decoration: InputDecoration(
                                labelText: 'Scan card or type member ID / phone, '
                                    'then press Enter',
                                prefixIcon: const Icon(Icons.qr_code_scanner),
                                border: const OutlineInputBorder(),
                                suffixIcon: _working
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : null,
                              ),
                              onSubmitted: _process,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              '$_processed processed this session',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (_entries.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    'Results will appear here.',
                                    style:
                                        TextStyle(color: AppColors.textFaint),
                                  ),
                                ),
                              )
                            else
                              for (final e in _entries) _EntryTile(entry: e),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final (color, background, icon) = switch (entry.kind) {
      _Kind.success => (
          AppColors.success,
          AppColors.successSoft,
          Icons.check_circle,
        ),
      _Kind.warning => (
          AppColors.warning,
          AppColors.warningSoft,
          Icons.info_outline,
        ),
      _Kind.error => (
          AppColors.americanRed,
          AppColors.dangerSoft,
          Icons.error_outline,
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormatter.time12(entry.time),
            style: TextStyle(color: color, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
