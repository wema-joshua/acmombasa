import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/auth_repository.dart';
import 'data/program_repository.dart';
import 'data/settings_repository.dart';
import 'data/visit_repository.dart';
import 'data/visitor_repository.dart';
import 'database/app_database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final visitorRepositoryProvider = Provider<VisitorRepository>(
  (ref) => VisitorRepository(ref.watch(databaseProvider)),
);

final visitRepositoryProvider = Provider<VisitRepository>(
  (ref) => VisitRepository(
    ref.watch(databaseProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final programRepositoryProvider = Provider<ProgramRepository>(
  (ref) => ProgramRepository(ref.watch(databaseProvider)),
);

/// The signed-in staff member, or null when signed out.
final sessionProvider =
    NotifierProvider<SessionController, StaffUser?>(SessionController.new);

class SessionController extends Notifier<StaffUser?> {
  @override
  StaffUser? build() => null;

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<StaffUser?> restore() async {
    state = await _auth.restoreSession();
    return state;
  }

  Future<void> signIn(String email, String password) async {
    state = await _auth.signIn(email, password);
  }

  Future<void> createFirstAdmin({
    required String displayName,
    required String email,
    required String password,
  }) async {
    state = await _auth.createFirstAdmin(
      displayName: displayName,
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = null;
  }
}
