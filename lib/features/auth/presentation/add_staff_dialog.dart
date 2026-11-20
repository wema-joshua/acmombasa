import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/data/auth_repository.dart';
import '../../../core/domain/app_exception.dart';
import '../../../core/providers.dart';

/// Lets an administrator create another staff account on this terminal.
Future<void> showAddStaffDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AddStaffDialog(),
  );
}

class _AddStaffDialog extends ConsumerStatefulWidget {
  const _AddStaffDialog();

  @override
  ConsumerState<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends ConsumerState<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String _role = AuthRepository.roleReceptionist;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final requester = ref.read(sessionProvider);
    if (requester == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await ref.read(authRepositoryProvider).addStaff(
            requester: requester,
            displayName: _name.text,
            email: _email.text,
            password: _password.text,
            role: _role,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created for ${user.displayName}.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff account'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name.' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter a valid email.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary password',
                  helperText: 'At least 8 characters',
                ),
                validator: (v) =>
                    (v == null || v.length < AuthRepository.minPasswordLength)
                        ? 'Use at least ${AuthRepository.minPasswordLength} '
                            'characters.'
                        : null,
              ),
              const SizedBox(height: AppSpacing.md),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Role'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _role,
                    isExpanded: true,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                        value: AuthRepository.roleReceptionist,
                        child: Text('Receptionist'),
                      ),
                      DropdownMenuItem(
                        value: AuthRepository.roleAdmin,
                        child: Text('Administrator'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _role = v);
                    },
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.americanRed,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
      ],
    );
  }
}
