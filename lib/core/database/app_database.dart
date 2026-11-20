import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Local SQLite database (Drift). The `.g.dart` part is generated; run
/// `dart run build_runner build` after adding the packages (see SETUP.md).
@DriftDatabase(tables: [StaffUsers, Visitors, Programs, ProgramRegistrations, Visits, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'american_corner'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Each step checks first, so a half-finished earlier upgrade can
            // never crash the app with "duplicate column".
            await _addIfMissing(m, visitors, visitors.gender);
            await _addIfMissing(m, visitors, visitors.ageBracket);
            await _addIfMissing(m, visitors, visitors.residence);
            await _addIfMissing(m, visitors, visitors.occupation);
            await _addIfMissing(m, programs, programs.sessionDate);
            await _addIfMissing(m, programs, programs.recurrence);
            await _addIfMissing(m, programs, programs.pillar);
            await _addIfMissing(m, programs, programs.format);
            await _addIfMissing(m, programs, programs.capacity);
            await _addIfMissing(m, programs, programs.facilitator);
            await _addIfMissing(m, programs, programs.walkInsAllowed);
            await _addIfMissing(m, programs, programs.audience);
            await _addIfMissing(m, programs, programs.status);
            await m.createTable(programRegistrations);

            // Give the starter programs sensible pillars and mark them for sync.
            const pillars = {
              'English Conversation': 'English Language & Teaching',
              'English Lessons & TOEFL Prep': 'English Language & Teaching',
              'Research & Study': 'EducationUSA & Library',
              'American Culture Activities': 'Cultural Programs & Arts',
              'Games Corner & Makerspace': 'STEM & Makerspace Innovation',
            };
            for (final e in pillars.entries) {
              await (update(programs)..where((p) => p.name.equals(e.key))).write(
                ProgramsCompanion(
                  pillar: Value(e.value),
                  updatedAt: Value(DateTime.now()),
                  dirty: const Value(true),
                ),
              );
            }
            // Existing visitors gained new columns: push them again.
            await customStatement('UPDATE visitors SET dirty = 1');
          }
        },
      );

  Future<void> _addIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn column,
  ) async {
    final rows = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).get();
    final exists = rows.any((r) => r.read<String>('name') == column.name);
    if (!exists) await m.addColumn(table, column);
  }
}
