import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/domain/app_exception.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../application/directory_providers.dart';

const _baseCategories = ['General Visitor', 'Student', 'Educator', 'Researcher'];

/// Edits name, phone, email and category. Returns the saved visitor.
Future<Visitor?> showEditVisitorDialog(BuildContext context, Visitor visitor) {
  return showDialog<Visitor>(
    context: context,
    builder: (_) => _EditVisitorDialog(visitor: visitor),
  );
}

class _EditVisitorDialog extends ConsumerStatefulWidget {
  const _EditVisitorDialog({required this.visitor});

  final Visitor visitor;

  @override
  ConsumerState<_EditVisitorDialog> createState() => _EditVisitorDialogState();
}

class _EditVisitorDialogState extends ConsumerState<_EditVisitorDialog> {
  late final _name = TextEditingController(text: widget.visitor.fullName);
  late final _phone =
      TextEditingController(text: PhoneUtils.format(widget.visitor.phone));
  late final _email = TextEditingController(text: widget.visitor.email ?? '');
  late String _category = widget.visitor.category;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref.read(directoryRepositoryProvider).updateVisitor(
            id: widget.visitor.id,
            fullName: _name.text,
            phone: _phone.text,
            email: _email.text,
            category: _category,
          );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final known = ref.watch(directoryCategoriesProvider).asData?.value ?? const [];
    final categories = {..._baseCategories, ...known, _category}.toList();

    return AlertDialog(
      title: Text('Edit Profile • ${widget.visitor.memberId}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Full name', _name),
            const SizedBox(height: AppSpacing.md),
            _field('Phone', _phone, keyboard: TextInputType.phone),
            const SizedBox(height: AppSpacing.md),
            _field('Email (optional)', _email,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: AppSpacing.md),
            const Text('Category', style: AppTextStyles.bodyStrong),
            const SizedBox(height: 6),
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged:
                      _busy ? null : (v) => setState(() => _category = v ?? _category),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!,
                  style: const TextStyle(color: AppColors.americanRed, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          child: Text(_busy ? 'Saving…' : 'Save Changes'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {TextInputType? keyboard}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodyStrong),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
