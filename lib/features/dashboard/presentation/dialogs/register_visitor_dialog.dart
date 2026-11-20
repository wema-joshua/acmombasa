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
import '../../../../core/widgets/pill.dart';
import '../../application/dashboard_providers.dart';

const List<String> _areas = [
  'Mvita',
  'Nyali',
  'Kisauni',
  'Likoni',
  'Changamwe',
  'Jomvu',
  'Kilifi County',
  'Kwale County',
  'Other',
];

const List<String> _ageRanges = [
  'Under 13',
  '13 - 17',
  '18 - 24',
  '25 - 34',
  '35 - 44',
  '45 and above',
];

/// Register New Visitor. Registers the visitor, then checks them in with the
/// chosen purpose. Returns the new visitor, or null if cancelled.
Future<Visitor?> showRegisterVisitorDialog(
  BuildContext context, {
  String initialQuery = '',
}) {
  return showDialog<Visitor>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RegisterVisitorDialog(initialQuery: initialQuery),
  );
}

class _RegisterVisitorDialog extends ConsumerStatefulWidget {
  const _RegisterVisitorDialog({required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<_RegisterVisitorDialog> createState() =>
      _RegisterVisitorDialogState();
}

class _RegisterVisitorDialogState
    extends ConsumerState<_RegisterVisitorDialog> {
  static const Color _fill = Color(0xFFF1F5FF);
  static const Color _line = Color(0xFFDCE6FB);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _email = TextEditingController();
  final _occupation = TextEditingController();

  String? _purposeKey;
  String? _area;
  String? _gender;
  String? _age;
  bool _consent = false;

  bool _submitted = false;
  bool _saving = false;
  String? _error;
  String _reference = 'ACM-····-····';

  static const _generalKey = 'general';

  @override
  void initState() {
    super.initState();
    // Reuse whatever was typed in the search box.
    final q = widget.initialQuery.trim();
    final looksLikePhone = RegExp(r'^[\d\s+()\-]{6,}$').hasMatch(q);
    _name = TextEditingController(text: looksLikePhone ? '' : q);
    _phone = TextEditingController(text: looksLikePhone ? _localDigits(q) : '');
    _loadReference();
  }

  Future<void> _loadReference() async {
    try {
      final id = await ref.read(visitorRepositoryProvider).previewNextMemberId();
      if (mounted) setState(() => _reference = id);
    } catch (_) {
      // Display only; the real ID is assigned on save.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _occupation.dispose();
    super.dispose();
  }

  /// The nine digits after +254 ("0712 345 678" and "+254712345678" both
  /// become "712345678").
  static String _localDigits(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('254') && d.length > 9) d = d.substring(3);
    return d.replaceFirst(RegExp(r'^0+'), '');
  }

  PurposeOption? _selectedOption(List<PurposeOption> options) {
    for (final o in options) {
      if ((o.programId ?? _generalKey) == _purposeKey) return o;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _submitted = true;
      _error = null;
    });

    final options = ref.read(purposeOptionsProvider).asData?.value ??
        const [PurposeOption.general];
    final option = _selectedOption(options);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || option == null || !_consent) return;

    setState(() => _saving = true);

    final Visitor visitor;
    try {
      visitor = await ref.read(visitorRepositoryProvider).register(
            fullName: _name.text,
            phone: '+254${_localDigits(_phone.text)}',
            email: _email.text,
            gender: _gender,
            ageBracket: _age,
            residence: _area,
            occupation: _occupation.text,
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
        });
      }
      return;
    }

    String? warning;
    try {
      final staff = ref.read(sessionProvider);
      if (staff == null) {
        throw const AppException('Sign in again to check the visitor in.');
      }
      await ref.read(visitRepositoryProvider).checkIn(
            visitor: visitor,
            staffId: staff.id,
            purpose: option.label,
            programId: option.programId,
          );
    } catch (e) {
      warning = 'Visitor registered, but check-in failed: ${friendlyError(e)}';
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(visitor);
    if (warning != null) {
      messenger.showSnackBar(SnackBar(content: Text(warning)));
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final options = ref.watch(purposeOptionsProvider).asData?.value ??
        const [PurposeOption.general];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f10): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_saving) Navigator.of(context).pop();
        },
      },
      child: Dialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              _buildReferenceBand(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) => _buildForm(
                      options,
                      wide: constraints.maxWidth >= 520,
                    ),
                  ),
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add_alt_1_outlined,
                color: AppColors.brightBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Register New Visitor',
                        style: AppTextStyles.cardTitle.copyWith(fontSize: 18)),
                    const Pill(
                      label: 'NEW PROFILE',
                      background: AppColors.infoSoft,
                      foreground: AppColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Create a permanent visitor profile for American Corner '
                  'Mombasa. First-time registration issues a unique ACM '
                  'Visitor ID.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _KeyChip(label: 'ESC'),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceBand() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.badge_outlined,
                size: 18, color: AppColors.brightBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ASSIGNED VISITOR REFERENCE',
                    style: AppTextStyles.label),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _reference,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Pill(
                      label: 'Ready',
                      background: AppColors.successSoft,
                      foreground: AppColors.success,
                      dotColor: AppColors.successDot,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Auto-generated upon submission',
              textAlign: TextAlign.right,
              style: AppTextStyles.caption.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(List<PurposeOption> options, {required bool wide}) {
    final purposeMissing = _submitted && _purposeKey == null;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pair(
            wide,
            _labeled(
              label: 'Full Name',
              required: true,
              hint: 'As per official ID / Student ID',
              child: TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: AppTextStyles.bodyStrong,
                decoration: _decoration('e.g., Juma Bakari Khamis',
                    icon: Icons.badge_outlined),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter the visitor\'s full name.'
                    : null,
              ),
            ),
            _labeled(
              label: 'First Visit Purpose',
              required: true,
              hint: 'Stat Report Metric',
              hintColor: AppColors.brightBlue,
              child: _dropdown(
                hint: 'Select intended program or resource...',
                value: _purposeKey,
                error: purposeMissing,
                items: [
                  for (final o in options)
                    DropdownMenuItem(
                      value: o.programId ?? _generalKey,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _purposeKey = v),
              ),
              error: purposeMissing ? 'Choose a purpose for this visit.' : null,
            ),
          ),
          const SizedBox(height: 14),
          _pair(
            wide,
            _labeled(
              label: 'Phone Number',
              required: true,
              hint: 'SMS confirmation',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _fill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _line),
                    ),
                    child: const Text(
                      'KE  +254',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      style: AppTextStyles.bodyStrong,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
                      ],
                      decoration: _decoration('712 345 678'),
                      validator: (v) => _localDigits(v ?? '').length == 9
                          ? null
                          : 'Enter 9 digits, e.g. 712 345 678.',
                    ),
                  ),
                ],
              ),
            ),
            _labeled(
              label: 'Area of Residence',
              optionalNote: '(Coastal Region)',
              child: _dropdown(
                hint: 'Select Sub-county / Locality',
                value: _area,
                items: [
                  for (final a in _areas)
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() => _area = v),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _pair(
            wide,
            _labeled(
              label: 'Email Address',
              optionalNote: '(Optional)',
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: AppTextStyles.bodyStrong,
                decoration: _decoration('juma.bakari@example.com',
                    icon: Icons.mail_outline),
              ),
            ),
            _labeled(
              label: 'Gender',
              optionalNote: '(Optional)',
              child: Row(
                children: [
                  for (final g in const [
                    ('Female', Icons.female),
                    ('Male', Icons.male),
                    ('Unspecified', null),
                  ]) ...[
                    Expanded(
                      child: _GenderButton(
                        label: g.$1,
                        icon: g.$2,
                        selected: _gender == g.$1,
                        onTap: () => setState(
                          () => _gender = _gender == g.$1 ? null : g.$1,
                        ),
                      ),
                    ),
                    if (g.$1 != 'Unspecified') const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _pair(
            wide,
            _labeled(
              label: 'Age Range',
              optionalNote: '(Optional)',
              child: _dropdown(
                hint: 'Select visitor age group',
                value: _age,
                items: [
                  for (final a in _ageRanges)
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() => _age = v),
              ),
            ),
            _labeled(
              label: 'Occupation / Institution',
              optionalNote: '(Optional)',
              child: TextFormField(
                controller: _occupation,
                style: AppTextStyles.bodyStrong,
                decoration: _decoration(
                  'e.g., Technical University of Mombasa student',
                  icon: Icons.school_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildConsent(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 18, color: AppColors.americanRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.americanRed,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsent() {
    final missing = _submitted && !_consent;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: missing ? AppColors.americanRed : _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text.rich(
                    TextSpan(
                      text: 'Visitor Consent & Data Privacy Acknowledgment',
                      children: [
                        TextSpan(
                          text: ' *',
                          style: TextStyle(color: AppColors.americanRed),
                        ),
                      ],
                    ),
                    style: AppTextStyles.bodyStrong,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'I confirm the visitor has formally consented to the '
                    'collection and institutional use of their contact '
                    'information in accordance with American Spaces Kenya '
                    'visitor guidelines and KNLS data privacy standards. '
                    'Records are retained strictly for center attendance and '
                    'safety metrics.',
                    style: AppTextStyles.caption,
                  ),
                  if (missing) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Consent is required before the visitor can be '
                      'registered.',
                      style: TextStyle(
                        color: AppColors.americanRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.brightBlue),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Immediately checks the visitor into the space upon profile '
              'creation.',
              style: AppTextStyles.caption,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Cancel'),
                      SizedBox(width: 8),
                      _KeyChip(label: 'Esc'),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brightBlue,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.how_to_reg_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Save Visitor & Check In'),
                            SizedBox(width: 10),
                            _KeyChip(label: 'F10', onDark: true),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- helpers

  Widget _pair(bool wide, Widget a, Widget b) {
    if (!wide) {
      return Column(children: [a, const SizedBox(height: 14), b]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
      ],
    );
  }

  Widget _labeled({
    required String label,
    required Widget child,
    bool required = false,
    String? optionalNote,
    String? hint,
    Color? hintColor,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (required)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: AppColors.americanRed),
                      ),
                    if (optionalNote != null)
                      TextSpan(
                        text: ' $optionalNote',
                        style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                      ),
                  ],
                ),
                style: AppTextStyles.bodyStrong.copyWith(fontSize: 12.5),
              ),
            ),
            if (hint != null)
              Flexible(
                child: Text(
                  hint,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10.5,
                    color: hintColor ?? AppColors.textMuted,
                    fontWeight:
                        hintColor == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error,
              style: const TextStyle(
                  color: AppColors.americanRed, fontSize: 11.5)),
        ],
      ],
    );
  }

  OutlineInputBorder _outline(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color),
      );

  InputDecoration _decoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13),
      prefixIcon:
          icon == null ? null : Icon(icon, size: 18, color: AppColors.textFaint),
      filled: true,
      fillColor: _fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
      border: _outline(_line),
      enabledBorder: _outline(_line),
      focusedBorder: _outline(AppColors.brightBlue),
      errorBorder: _outline(AppColors.americanRed),
      focusedErrorBorder: _outline(AppColors.americanRed),
      errorStyle: const TextStyle(fontSize: 11.5),
    );
  }

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    bool error = false,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: error ? AppColors.americanRed : _line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(10),
          dropdownColor: AppColors.white,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          style: AppTextStyles.bodyStrong,
          hint: Text(
            hint,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          items: items,
          onChanged: _saving ? null : onChanged,
        ),
      ),
    );
  }
}

class _GenderButton extends StatelessWidget {
  const _GenderButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brightBlue : AppColors.textSecondary;

    return Material(
      color: selected ? AppColors.infoSoft : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brightBlue : const Color(0xFFDCE6FB),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small keyboard-shortcut badge ("Esc", "F10").
class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label, this.onDark = false});

  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.22)
            : AppColors.neutralSoft,
        borderRadius: BorderRadius.circular(4),
        border: onDark ? null : Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onDark ? AppColors.white : AppColors.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
