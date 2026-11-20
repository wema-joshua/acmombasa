import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/app_exception.dart';
import '../security/password_hasher.dart';
import '../utils/id_generator.dart';
import 'settings_repository.dart';

/// Local staff accounts and the persisted "who is signed in" session.
///
/// Accounts live only on this terminal's database. Cloud sync uses its own
/// Supabase sign-in (see SyncService).
class AuthRepository {
  AuthRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  static const int minPasswordLength = 8;
  static const String roleAdmin = 'admin';
  static const String roleReceptionist = 'receptionist';

  final List<DateTime> _failures = [];

  Future<bool> hasStaff() async {
    final rows = await (_db.select(_db.staffUsers)..limit(1)).get();
    return rows.isNotEmpty;
  }

  /// First-run setup. Only allowed while no account exists.
  Future<StaffUser> createFirstAdmin({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (await hasStaff()) {
      throw const AppException('Setup has already been completed.');
    }
    final user = await _insert(
      displayName: displayName,
      email: email,
      password: password,
      role: roleAdmin,
    );
    await _settings.set(SettingKeys.sessionStaffId, user.id);
    return user;
  }

  /// Adds another staff account. Only administrators may do this.
  Future<StaffUser> addStaff({
    required StaffUser requester,
    required String displayName,
    required String email,
    required String password,
    required String role,
  }) async {
    if (requester.role != roleAdmin) {
      throw const AppException('Only administrators can add staff accounts.');
    }
    return _insert(
      displayName: displayName,
      email: email,
      password: password,
      role: role == roleAdmin ? roleAdmin : roleReceptionist,
    );
  }

  Future<List<StaffUser>> listStaff() {
    return (_db.select(_db.staffUsers)
          ..orderBy([(u) => OrderingTerm.asc(u.displayName)]))
        .get();
  }

  /// Turns a staff account on or off. Administrators only; you cannot switch
  /// off your own account or the last active administrator.
  Future<void> setStaffActive({
    required StaffUser requester,
    required String staffId,
    required bool active,
  }) async {
    if (requester.role != roleAdmin) {
      throw const AppException('Only administrators can change staff accounts.');
    }
    if (!active) {
      if (staffId == requester.id) {
        throw const AppException('You cannot switch off your own account.');
      }
      final admins = await (_db.select(_db.staffUsers)
            ..where((u) => u.role.equals(roleAdmin) & u.isActive.equals(true)))
          .get();
      final target = admins.where((u) => u.id == staffId).firstOrNull;
      if (target != null && admins.length <= 1) {
        throw const AppException('At least one administrator must stay active.');
      }
    }
    await (_db.update(_db.staffUsers)..where((u) => u.id.equals(staffId)))
        .write(StaffUsersCompanion(isActive: Value(active)));
  }

  Future<StaffUser> signIn(String email, String password) async {
    final now = DateTime.now();
    _failures.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_failures.length >= 5) {
      throw const AppException(
        'Too many failed attempts. Please wait a minute and try again.',
      );
    }

    final normalized = email.trim().toLowerCase();
    final user = await (_db.select(_db.staffUsers)
          ..where((u) => u.email.equals(normalized)))
        .getSingleOrNull();

    final ok = user != null &&
        user.isActive &&
        await PasswordHasher.verify(password, user.passwordSalt, user.passwordHash);

    if (!ok) {
      _failures.add(now);
      throw const AppException('Incorrect email or password.');
    }

    _failures.clear();
    await _settings.set(SettingKeys.sessionStaffId, user.id);
    return user;
  }

  Future<StaffUser?> restoreSession() async {
    final id = await _settings.get(SettingKeys.sessionStaffId);
    if (id == null) return null;
    final user = await (_db.select(_db.staffUsers)
          ..where((u) => u.id.equals(id)))
        .getSingleOrNull();
    if (user == null || !user.isActive) {
      await _settings.remove(SettingKeys.sessionStaffId);
      return null;
    }
    return user;
  }

  Future<void> signOut() => _settings.remove(SettingKeys.sessionStaffId);

  Future<StaffUser> _insert({
    required String displayName,
    required String email,
    required String password,
    required String role,
  }) async {
    final name = displayName.trim();
    final normalized = email.trim().toLowerCase();

    if (name.isEmpty) throw const AppException('Enter a name.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw const AppException('Enter a valid email address.');
    }
    if (password.length < minPasswordLength) {
      throw const AppException(
        'Password must be at least $minPasswordLength characters.',
      );
    }

    final existing = await (_db.select(_db.staffUsers)
          ..where((u) => u.email.equals(normalized)))
        .getSingleOrNull();
    if (existing != null) {
      throw const AppException('An account with this email already exists.');
    }

    final salt = PasswordHasher.generateSalt();
    final hash = await PasswordHasher.hash(password, salt);
    final id = newId();

    await _db.into(_db.staffUsers).insert(
          StaffUsersCompanion.insert(
            id: id,
            email: normalized,
            displayName: name,
            passwordHash: hash,
            passwordSalt: salt,
            createdAt: DateTime.now(),
            role: Value(role),
          ),
        );

    return (_db.select(_db.staffUsers)..where((u) => u.id.equals(id)))
        .getSingle();
  }
}
