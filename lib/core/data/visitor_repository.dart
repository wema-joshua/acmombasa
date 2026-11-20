import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/app_exception.dart';
import '../domain/models.dart';
import '../utils/id_generator.dart';
import '../utils/phone_utils.dart';

class VisitorRepository {
  VisitorRepository(this._db);

  final AppDatabase _db;

  Future<Visitor?> getById(String id) {
    return (_db.select(_db.visitors)..where((v) => v.id.equals(id)))
        .getSingleOrNull();
  }

  /// Name, member ID or phone number (any format).
  Future<List<Visitor>> search(String query, {int limit = 8}) async {
    final q = query.trim().replaceAll(RegExp(r'[%_]'), '');
    if (q.isEmpty) return const [];
    final phoneFragment = PhoneUtils.searchFragment(q);
    final looksLikePhone = phoneFragment.length >= 3 &&
        RegExp(r'^[\d\s+()\-]+$').hasMatch(q);

    return (_db.select(_db.visitors)
          ..where((v) {
            final byName = v.fullName.like('%$q%');
            final byId = v.memberId.like('%$q%');
            if (looksLikePhone) {
              return byName | byId | v.phone.like('%$phoneFragment%');
            }
            return byName | byId;
          })
          ..orderBy([(v) => OrderingTerm.asc(v.fullName)])
          ..limit(limit))
        .get();
  }

  /// Exact match used by scanners: member ID, or a full phone number.
  Future<Visitor?> findByScan(String input) async {
    final text = input.trim();
    if (text.isEmpty) return null;

    final byId = await (_db.select(_db.visitors)
          ..where((v) => v.memberId.lower().equals(text.toLowerCase()))
          ..limit(1))
        .getSingleOrNull();
    if (byId != null) return byId;

    final phone = PhoneUtils.normalize(text);
    if (phone == null) return null;
    return (_db.select(_db.visitors)
          ..where((v) => v.phone.equals(phone))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<Visitor> register({
    required String fullName,
    required String phone,
    String? email,
    String category = 'General Visitor',
    bool cardIssued = false,
    String? gender,
    String? ageBracket,
    String? residence,
    String? occupation,
  }) async {
    final name = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 2) throw const AppException('Enter the visitor\'s name.');

    final normalizedPhone = PhoneUtils.normalize(phone);
    if (normalizedPhone == null) {
      throw const AppException('Enter a valid phone number.');
    }

    final cleanEmail = email?.trim();
    if (cleanEmail != null &&
        cleanEmail.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanEmail)) {
      throw const AppException('Enter a valid email address or leave it blank.');
    }

    return _db.transaction(() async {
      final duplicate = await (_db.select(_db.visitors)
            ..where((v) => v.phone.equals(normalizedPhone))
            ..limit(1))
          .getSingleOrNull();
      if (duplicate != null) {
        throw AppException(
          'This phone number is already registered to ${duplicate.fullName} '
          '(${duplicate.memberId}).',
        );
      }

      final now = DateTime.now();
      final id = newId();
      await _db.into(_db.visitors).insert(
            VisitorsCompanion.insert(
              id: id,
              memberId: await _nextMemberId(now),
              fullName: name,
              phone: normalizedPhone,
              registeredAt: now,
              updatedAt: now,
              email: Value(
                (cleanEmail == null || cleanEmail.isEmpty) ? null : cleanEmail,
              ),
              category: Value(category),
              cardIssued: Value(cardIssued),
              gender: Value(_clean(gender)),
              ageBracket: Value(_clean(ageBracket)),
              residence: Value(_clean(residence)),
              occupation: Value(_clean(occupation)),
            ),
          );
      return (_db.select(_db.visitors)..where((v) => v.id.equals(id)))
          .getSingle();
    });
  }

  Future<VisitorSummary?> summary(String visitorId) async {
    final visitor = await getById(visitorId);
    if (visitor == null) return null;

    final visits = await (_db.select(_db.visits)
          ..where((v) => v.visitorId.equals(visitorId))
          ..orderBy([(v) => OrderingTerm.desc(v.checkInAt)]))
        .get();

    final start = startOfDay(DateTime.now());
    final today = visits.where((v) => !v.checkInAt.isBefore(start)).toList();
    final open = today.where((v) => v.checkOutAt == null).firstOrNull;
    final earlier = visits.where((v) => v.checkInAt.isBefore(start));

    return VisitorSummary(
      visitor: visitor,
      totalVisits: visits.length,
      lastVisit: earlier.firstOrNull,
      openVisit: open,
      latestTodayVisit: today.firstOrNull,
    );
  }

  Future<List<Visit>> history(String visitorId, {int limit = 30}) {
    return (_db.select(_db.visits)
          ..where((v) => v.visitorId.equals(visitorId))
          ..orderBy([(v) => OrderingTerm.desc(v.checkInAt)])
          ..limit(limit))
        .get();
  }

  /// The member ID the next registration will receive (display only).
  Future<String> previewNextMemberId() => _nextMemberId(DateTime.now());

  /// "ACM-2026-0001". Sequence restarts each year; collisions are skipped.
  Future<String> _nextMemberId(DateTime now) async {
    final prefix = 'ACM-${now.year}-';
    final existing = await (_db.select(_db.visitors)
          ..where((v) => v.memberId.like('$prefix%')))
        .get();
    var next = existing.length + 1;
    final taken = existing.map((v) => v.memberId).toSet();
    String candidate;
    do {
      candidate = '$prefix${next.toString().padLeft(4, '0')}';
      next++;
    } while (taken.contains(candidate));
    return candidate;
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
