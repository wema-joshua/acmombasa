import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config/supabase_config.dart';
import '../data/settings_repository.dart';
import '../database/app_database.dart';
import '../domain/app_exception.dart';

class SyncResult {
  const SyncResult({required this.pushed, required this.pulled});

  final int pushed;
  final int pulled;
}

/// Two-way sync between the local database and Supabase.
///
/// * Push: every row marked `dirty` is upserted to the cloud, then marked clean
///   (only if it wasn't edited again while the upload was running).
/// * Pull: rows changed in the cloud since the last cursor are merged in.
///   When both sides changed the same row, the newer `updated_at` wins.
///
/// Uses only the public anon key plus the signed-in Supabase user's session;
/// access is enforced by the row-level-security policies in supabase/schema.sql.
class SyncService {
  SyncService(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  static const _pageSize = 500;
  static final _epoch = DateTime.utc(1970).toIso8601String();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  bool get isAvailable => SupabaseConfig.isAvailable;
  bool get isSignedIn => isAvailable && _client.auth.currentSession != null;
  String? get cloudEmail => isSignedIn ? _client.auth.currentUser?.email : null;

  Future<void> signIn(String email, String password) async {
    if (!isAvailable) {
      throw const AppException('Cloud sync is not configured.');
    }
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } on sb.AuthException catch (e) {
      throw AppException(e.message);
    } catch (_) {
      throw const AppException(
        'Could not reach the cloud. Check the internet connection.',
      );
    }
  }

  Future<void> signOut() async {
    if (isAvailable) await _client.auth.signOut();
  }

  /// Number of local rows waiting to be uploaded.
  Future<int> pendingCount() async {
    var total = 0;
    total += await _count(_db.visitors, _db.visitors.dirty);
    total += await _count(_db.programs, _db.programs.dirty);
    total += await _count(
        _db.programRegistrations, _db.programRegistrations.dirty);
    total += await _count(_db.visits, _db.visits.dirty);
    return total;
  }

  Future<int> _count(TableInfo<Table, dynamic> table, GeneratedColumn<bool> dirty) async {
    final count = countAll();
    final query = _db.selectOnly(table)
      ..addColumns([count])
      ..where(dirty.equals(true));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<SyncResult> sync() async {
    if (!isSignedIn) {
      throw const AppException('Sign in to the cloud account first.');
    }
    try {
      final pushed = await _pushAll();
      final pulled = await _pullAll();
      return SyncResult(pushed: pushed, pulled: pulled);
    } on sb.PostgrestException catch (e) {
      throw AppException('Cloud rejected the sync: ${e.message}');
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Could not reach the cloud. Changes are kept and will sync later.',
      );
    }
  }

  // ---------------------------------------------------------------- push

  Future<int> _pushAll() async {
    var total = 0;
    total += await _pushVisitors();
    total += await _pushPrograms();
    total += await _pushRegistrations();
    total += await _pushVisits();
    return total;
  }

  Future<int> _pushVisitors() async {
    final rows =
        await (_db.select(_db.visitors)..where((t) => t.dirty.equals(true))).get();
    if (rows.isEmpty) return 0;
    await _upsertInChunks('visitors', [
      for (final r in rows)
        {
          'id': r.id,
          'member_id': r.memberId,
          'full_name': r.fullName,
          'phone': r.phone,
          'email': r.email,
          'category': r.category,
          'is_verified': r.isVerified,
          'card_issued': r.cardIssued,
          'gender': r.gender,
          'age_bracket': r.ageBracket,
          'residence': r.residence,
          'occupation': r.occupation,
          'registered_at': _utc(r.registeredAt),
          'updated_at': _utc(r.updatedAt),
        },
    ]);
    for (final r in rows) {
      await (_db.update(_db.visitors)
            ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
          .write(const VisitorsCompanion(dirty: Value(false)));
    }
    return rows.length;
  }

  Future<int> _pushPrograms() async {
    final rows =
        await (_db.select(_db.programs)..where((t) => t.dirty.equals(true))).get();
    if (rows.isEmpty) return 0;
    await _upsertInChunks('programs', [
      for (final r in rows)
        {
          'id': r.id,
          'name': r.name,
          'location': r.location,
          'start_minute': r.startMinute,
          'end_minute': r.endMinute,
          'note': r.note,
          'session_date': r.sessionDate == null ? null : _utc(r.sessionDate!),
          'recurrence': r.recurrence,
          'pillar': r.pillar,
          'format': r.format,
          'capacity': r.capacity,
          'facilitator': r.facilitator,
          'walk_ins_allowed': r.walkInsAllowed,
          'audience': r.audience,
          'status': r.status,
          'is_active': r.isActive,
          'sort_order': r.sortOrder,
          'updated_at': _utc(r.updatedAt),
        },
    ]);
    for (final r in rows) {
      await (_db.update(_db.programs)
            ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
          .write(const ProgramsCompanion(dirty: Value(false)));
    }
    return rows.length;
  }

  Future<int> _pushRegistrations() async {
    final rows = await (_db.select(_db.programRegistrations)
          ..where((t) => t.dirty.equals(true)))
        .get();
    if (rows.isEmpty) return 0;
    await _upsertInChunks('program_registrations', [
      for (final r in rows)
        {
          'id': r.id,
          'program_id': r.programId,
          'visitor_id': r.visitorId,
          'session_day': _utc(r.sessionDay),
          'created_at': _utc(r.createdAt),
          'updated_at': _utc(r.updatedAt),
        },
    ]);
    for (final r in rows) {
      await (_db.update(_db.programRegistrations)
            ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
          .write(const ProgramRegistrationsCompanion(dirty: Value(false)));
    }
    return rows.length;
  }

  Future<int> _pushVisits() async {
    final rows =
        await (_db.select(_db.visits)..where((t) => t.dirty.equals(true))).get();
    if (rows.isEmpty) return 0;
    await _upsertInChunks('visits', [
      for (final r in rows)
        {
          'id': r.id,
          'visitor_id': r.visitorId,
          'program_id': r.programId,
          'purpose': r.purpose,
          'workstation': r.workstation,
          'check_in_at': _utc(r.checkInAt),
          'check_out_at': r.checkOutAt == null ? null : _utc(r.checkOutAt!),
          'staff_id': r.staffId,
          'updated_at': _utc(r.updatedAt),
        },
    ]);
    for (final r in rows) {
      await (_db.update(_db.visits)
            ..where((t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt)))
          .write(const VisitsCompanion(dirty: Value(false)));
    }
    return rows.length;
  }

  Future<void> _upsertInChunks(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    for (var i = 0; i < rows.length; i += 200) {
      final chunk = rows.sublist(i, i + 200 > rows.length ? rows.length : i + 200);
      await _client.from(table).upsert(chunk, onConflict: 'id');
    }
  }

  // ---------------------------------------------------------------- pull

  /// Parents first so visits never reference a visitor we don't have yet.
  Future<int> _pullAll() async {
    var total = 0;
    total += await _pull('visitors', _mergeVisitor);
    total += await _pull('programs', _mergeProgram);
    total += await _pull('program_registrations', _mergeRegistration);
    total += await _pull('visits', _mergeVisit);
    return total;
  }

  Future<int> _pull(
    String table,
    Future<void> Function(Map<String, dynamic> row) merge,
  ) async {
    final key = SettingKeys.syncCursor(table);
    var cursor = await _settings.get(key) ?? _epoch;
    var total = 0;

    while (true) {
      final List<dynamic> page = await _client
          .from(table)
          .select()
          .gt('updated_at', cursor)
          .order('updated_at', ascending: true)
          .limit(_pageSize);

      for (final item in page) {
        await merge(Map<String, dynamic>.from(item as Map));
      }
      total += page.length;
      if (page.isNotEmpty) {
        cursor = (page.last as Map)['updated_at'] as String;
        await _settings.set(key, cursor);
      }
      if (page.length < _pageSize) break;
    }
    return total;
  }

  Future<void> _mergeVisitor(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final remoteUpdated = _local(m['updated_at']);
    final local = await (_db.select(_db.visitors)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && local.dirty && local.updatedAt.isAfter(remoteUpdated)) {
      return; // local edit is newer; it will be pushed next time.
    }
    await _db.into(_db.visitors).insertOnConflictUpdate(
          VisitorsCompanion(
            id: Value(id),
            memberId: Value(m['member_id'] as String),
            fullName: Value(m['full_name'] as String),
            phone: Value(m['phone'] as String),
            email: Value(m['email'] as String?),
            category: Value((m['category'] as String?) ?? 'General Visitor'),
            isVerified: Value((m['is_verified'] as bool?) ?? true),
            cardIssued: Value((m['card_issued'] as bool?) ?? false),
            gender: Value(m['gender'] as String?),
            ageBracket: Value(m['age_bracket'] as String?),
            residence: Value(m['residence'] as String?),
            occupation: Value(m['occupation'] as String?),
            registeredAt: Value(_local(m['registered_at'])),
            updatedAt: Value(remoteUpdated),
            dirty: const Value(false),
          ),
        );
  }

  Future<void> _mergeProgram(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final remoteUpdated = _local(m['updated_at']);
    final local = await (_db.select(_db.programs)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && local.dirty && local.updatedAt.isAfter(remoteUpdated)) {
      return;
    }
    await _db.into(_db.programs).insertOnConflictUpdate(
          ProgramsCompanion(
            id: Value(id),
            name: Value(m['name'] as String),
            location: Value(m['location'] as String),
            startMinute: Value(m['start_minute'] as int?),
            endMinute: Value(m['end_minute'] as int?),
            note: Value(m['note'] as String?),
            sessionDate: Value(
              m['session_date'] == null ? null : _local(m['session_date']),
            ),
            recurrence: Value((m['recurrence'] as String?) ?? 'daily'),
            pillar: Value((m['pillar'] as String?) ?? 'General Programs'),
            format: Value((m['format'] as String?) ?? 'in_person'),
            capacity: Value(m['capacity'] as int?),
            facilitator: Value(m['facilitator'] as String?),
            walkInsAllowed: Value((m['walk_ins_allowed'] as bool?) ?? true),
            audience: Value(m['audience'] as String?),
            status: Value((m['status'] as String?) ?? 'published'),
            isActive: Value((m['is_active'] as bool?) ?? true),
            sortOrder: Value((m['sort_order'] as int?) ?? 0),
            updatedAt: Value(remoteUpdated),
            dirty: const Value(false),
          ),
        );
  }

  Future<void> _mergeRegistration(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final remoteUpdated = _local(m['updated_at']);
    final local = await (_db.select(_db.programRegistrations)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && local.dirty && local.updatedAt.isAfter(remoteUpdated)) {
      return;
    }
    await _db.into(_db.programRegistrations).insertOnConflictUpdate(
          ProgramRegistrationsCompanion(
            id: Value(id),
            programId: Value(m['program_id'] as String),
            visitorId: Value(m['visitor_id'] as String),
            sessionDay: Value(_local(m['session_day'])),
            createdAt: Value(_local(m['created_at'])),
            updatedAt: Value(remoteUpdated),
            dirty: const Value(false),
          ),
        );
  }

  Future<void> _mergeVisit(Map<String, dynamic> m) async {
    final id = m['id'] as String;
    final remoteUpdated = _local(m['updated_at']);
    final local = await (_db.select(_db.visits)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && local.dirty && local.updatedAt.isAfter(remoteUpdated)) {
      return;
    }
    await _db.into(_db.visits).insertOnConflictUpdate(
          VisitsCompanion(
            id: Value(id),
            visitorId: Value(m['visitor_id'] as String),
            programId: Value(m['program_id'] as String?),
            purpose: Value(m['purpose'] as String),
            workstation: Value(m['workstation'] as String?),
            checkInAt: Value(_local(m['check_in_at'])),
            checkOutAt: Value(
              m['check_out_at'] == null ? null : _local(m['check_out_at']),
            ),
            staffId: Value(m['staff_id'] as String),
            updatedAt: Value(remoteUpdated),
            dirty: const Value(false),
          ),
        );
  }

  static String _utc(DateTime d) => d.toUtc().toIso8601String();
  static DateTime _local(dynamic v) => DateTime.parse(v as String).toLocal();
}
