import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/app_exception.dart';
import '../domain/program_models.dart';
import '../utils/id_generator.dart';
import 'visit_repository.dart';

/// Scheduling, rosters and admissions for the Programs & Activities page.
class SessionRepository {
  SessionRepository(this._db, this._visits);

  final AppDatabase _db;
  final VisitRepository _visits;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  // ------------------------------------------------------------ schedule

  Future<List<SessionView>> sessionsOn(DateTime date) async {
    final day = _day(date);
    final now = DateTime.now();
    final isToday = day == _day(now);
    final isPast = day.isBefore(_day(now));
    final minute = now.hour * 60 + now.minute;

    final programs = (await _db.select(_db.programs).get())
        .where((p) => ProgramSchedule.occursOn(p, day))
        .toList();

    final regs = await (_db.select(_db.programRegistrations)
          ..where((r) => r.sessionDay.equals(day)))
        .get();
    final visits = await (_db.select(_db.visits)
          ..where((v) =>
              v.programId.isNotNull() &
              v.checkInAt.isBiggerOrEqualValue(day) &
              v.checkInAt.isSmallerThanValue(
                  DateTime(day.year, day.month, day.day + 1))))
        .get();

    final views = <SessionView>[];
    for (final p in programs) {
      final registered = regs.where((r) => r.programId == p.id).toList();
      final registeredIds = registered.map((r) => r.visitorId).toSet();
      final present = visits.where((v) => v.programId == p.id).toList();
      final walkIns = present
          .map((v) => v.visitorId)
          .toSet()
          .where((id) => !registeredIds.contains(id))
          .length;

      final start = p.startMinute;
      final end = p.endMinute;
      SessionPhase phase;
      int? elapsed, toStart, remaining;
      if (start == null || end == null) {
        phase = SessionPhase.allDay;
      } else if (isPast) {
        phase = SessionPhase.completed;
      } else if (!isToday) {
        phase = SessionPhase.scheduled;
      } else if (minute >= end) {
        phase = SessionPhase.completed;
      } else if (minute >= start) {
        phase = SessionPhase.inSession;
        elapsed = minute - start;
        remaining = end - minute;
      } else if (start - minute <= 60) {
        phase = SessionPhase.startingSoon;
        toStart = start - minute;
      } else {
        phase = SessionPhase.scheduled;
      }

      views.add(SessionView(
        program: p,
        day: day,
        registered: registered.length,
        present: present.map((v) => v.visitorId).toSet().length,
        walkIns: walkIns,
        phase: phase,
        minutesElapsed: elapsed,
        minutesToStart: toStart,
        minutesRemaining: remaining,
      ));
    }

    views.sort((a, b) {
      final c = (a.program.startMinute ?? -1).compareTo(b.program.startMinute ?? -1);
      return c != 0 ? c : a.program.sortOrder.compareTo(b.program.sortOrder);
    });
    return views;
  }

  Future<DaySummary> summaryFor(DateTime date) async {
    final sessions = await sessionsOn(date);
    final live = sessions.where((s) => s.phase == SessionPhase.inSession).toList();

    var seatsTotal = 0;
    var seatsReserved = 0;
    for (final s in sessions) {
      final cap = s.program.capacity;
      if (cap == null) continue;
      seatsTotal += cap;
      seatsReserved += s.seatsTaken > cap ? cap : s.seatsTaken;
    }

    // Flagship: the program with the most check-ins in the last 30 days.
    final since = _day(DateTime.now()).subtract(const Duration(days: 30));
    final visits = await (_db.select(_db.visits)
          ..where((v) =>
              v.programId.isNotNull() & v.checkInAt.isBiggerOrEqualValue(since)))
        .get();
    final perProgram = <String, List<Visit>>{};
    for (final v in visits) {
      perProgram.putIfAbsent(v.programId!, () => []).add(v);
    }
    String? flagshipId;
    var best = 0;
    perProgram.forEach((id, list) {
      if (list.length > best) {
        best = list.length;
        flagshipId = id;
      }
    });
    String? flagshipName;
    var average = 0;
    if (flagshipId != null) {
      final program = await (_db.select(_db.programs)
            ..where((p) => p.id.equals(flagshipId!)))
          .getSingleOrNull();
      flagshipName = program?.name;
      final days = perProgram[flagshipId]!
          .map((v) => _day(v.checkInAt))
          .toSet()
          .length;
      average = (best / (days == 0 ? 1 : days)).round();
    }

    return DaySummary(
      sessions: sessions.length,
      ongoing: live.length,
      ongoingRoom: live.isEmpty ? null : live.first.program.location,
      preRegistered: sessions.fold(0, (a, s) => a + s.registered),
      walkIns: sessions.fold(0, (a, s) => a + s.walkIns),
      seatsTotal: seatsTotal,
      seatsReserved: seatsReserved,
      rooms: sessions.map((s) => s.program.location).toSet().toList()..sort(),
      flagshipName: flagshipName,
      flagshipAverage: average,
    );
  }

  /// Locations offered when scheduling: known rooms plus any already used.
  Future<List<String>> roomNames() async {
    final used = (await _db.select(_db.programs).get()).map((p) => p.location);
    return {...knownRooms.keys, ...used}.toList()..sort();
  }

  // -------------------------------------------------------------- roster

  Future<List<RosterEntry>> roster(String programId, DateTime date) async {
    final day = _day(date);
    final regs = await (_db.select(_db.programRegistrations)
          ..where((r) => r.programId.equals(programId) & r.sessionDay.equals(day)))
        .get();
    final visits = await (_db.select(_db.visits)
          ..where((v) =>
              v.programId.equals(programId) &
              v.checkInAt.isBiggerOrEqualValue(day) &
              v.checkInAt.isSmallerThanValue(
                  DateTime(day.year, day.month, day.day + 1)))
          ..orderBy([(v) => OrderingTerm.asc(v.checkInAt)]))
        .get();

    final ids = {...regs.map((r) => r.visitorId), ...visits.map((v) => v.visitorId)};
    if (ids.isEmpty) return const [];
    final visitors = {
      for (final v in await (_db.select(_db.visitors)..where((t) => t.id.isIn(ids))).get())
        v.id: v,
    };

    final entries = <RosterEntry>[];
    for (final id in ids) {
      final visitor = visitors[id];
      if (visitor == null) continue;
      final reg = regs.where((r) => r.visitorId == id).firstOrNull;
      final visit = visits.where((v) => v.visitorId == id).firstOrNull;
      entries.add(RosterEntry(
        visitor: visitor,
        visit: visit,
        registrationId: reg?.id,
        status: visit != null
            ? (reg == null ? RosterStatus.walkIn : RosterStatus.present)
            : RosterStatus.awaiting,
      ));
    }
    entries.sort((a, b) {
      final order = {
        RosterStatus.present: 0,
        RosterStatus.walkIn: 1,
        RosterStatus.awaiting: 2,
      };
      final c = order[a.status]!.compareTo(order[b.status]!);
      if (c != 0) return c;
      final ta = a.visit?.checkInAt;
      final tb = b.visit?.checkInAt;
      if (ta != null && tb != null) return tb.compareTo(ta);
      return a.visitor.fullName.compareTo(b.visitor.fullName);
    });
    return entries;
  }

  Future<void> preRegister({
    required Program program,
    required Visitor visitor,
    required DateTime date,
  }) async {
    final day = _day(date);
    if (day.isBefore(_day(DateTime.now()))) {
      throw const AppException('This session has already taken place.');
    }
    await _db.transaction(() async {
      final existing = await (_db.select(_db.programRegistrations)
            ..where((r) =>
                r.programId.equals(program.id) &
                r.visitorId.equals(visitor.id) &
                r.sessionDay.equals(day))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        throw AppException('${visitor.fullName} is already on this roster.');
      }
      final session = (await sessionsOn(day)).where((s) => s.program.id == program.id).firstOrNull;
      if (session != null && session.isFull) {
        throw AppException('"${program.name}" is full (${program.capacity} seats).');
      }
      final now = DateTime.now();
      await _db.into(_db.programRegistrations).insert(
            ProgramRegistrationsCompanion.insert(
              id: newId(),
              programId: program.id,
              visitorId: visitor.id,
              sessionDay: day,
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  /// Admits [visitor] to [program] today: checks them in against the program,
  /// or attaches a general visit they already have open.
  Future<void> admit({
    required Program program,
    required Visitor visitor,
    required String staffId,
  }) async {
    final today = _day(DateTime.now());
    if (!ProgramSchedule.occursOn(program, today)) {
      throw const AppException('This session does not run today.');
    }

    await _db.transaction(() async {
      final reg = await (_db.select(_db.programRegistrations)
            ..where((r) =>
                r.programId.equals(program.id) &
                r.visitorId.equals(visitor.id) &
                r.sessionDay.equals(today))
            ..limit(1))
          .getSingleOrNull();

      final session =
          (await sessionsOn(today)).where((s) => s.program.id == program.id).firstOrNull;
      final counted = reg != null;
      if (!counted) {
        if (!program.walkInsAllowed) {
          throw const AppException(
              'Walk-ins are not allowed for this session. Pre-register the visitor first.');
        }
        if (session != null && session.isFull) {
          throw AppException('"${program.name}" is full (${program.capacity} seats).');
        }
      }

      final open = await _visits.openVisitFor(visitor.id);
      if (open != null) {
        if (open.programId == program.id) {
          throw AppException('${visitor.fullName} is already admitted.');
        }
        if (open.programId != null) {
          throw AppException(
              '${visitor.fullName} is already inside for another program. Check them out first.');
        }
        final now = DateTime.now();
        await (_db.update(_db.visits)..where((v) => v.id.equals(open.id))).write(
          VisitsCompanion(
            programId: Value(program.id),
            purpose: Value(program.name),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
        return;
      }

      await _visits.checkIn(
        visitor: visitor,
        staffId: staffId,
        purpose: program.name,
        programId: program.id,
      );
    });
  }

  /// Admits every pre-registered visitor who has not arrived. Returns the
  /// number admitted.
  Future<int> admitAllRegistered({
    required Program program,
    required String staffId,
  }) async {
    final today = _day(DateTime.now());
    final entries = await roster(program.id, today);
    var admitted = 0;
    for (final e in entries.where((e) => e.status == RosterStatus.awaiting)) {
      try {
        await admit(program: program, visitor: e.visitor, staffId: staffId);
        admitted++;
      } on AppException {
        // Skip people who are inside for another program.
      }
    }
    return admitted;
  }

  // -------------------------------------------------- drafts and cancelling

  /// Saved-but-unpublished sessions, newest first.
  Future<List<Program>> draftSessions() {
    return (_db.select(_db.programs)
          ..where((p) => p.status.equals('draft') & p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]))
        .get();
  }

  Future<void> publishDraft(String programId) async {
    await _db.transaction(() async {
      final p = await (_db.select(_db.programs)..where((t) => t.id.equals(programId)))
          .getSingleOrNull();
      if (p == null) throw const AppException('Session not found.');
      final day = p.sessionDate == null ? _day(DateTime.now()) : _day(p.sessionDate!);
      if (day.isBefore(_day(DateTime.now())) && p.recurrence == Recurrence.none) {
        throw const AppException(
            'This draft is dated in the past. Create it again with a new date.');
      }
      if (p.startMinute != null && p.endMinute != null) {
        final clash = await _findRoomClash(
          NewSessionInput(
            title: p.name,
            pillar: p.pillar,
            format: p.format,
            day: day,
            startMinute: p.startMinute!,
            endMinute: p.endMinute!,
            recurrence: p.recurrence,
            room: p.location,
            capacity: p.capacity ?? 1,
            walkInsAllowed: p.walkInsAllowed,
            audience: const [],
            publish: true,
          ),
          day,
          ignoreId: p.id,
        );
        if (clash != null) {
          throw AppException(
              '${p.location} is already booked for "${clash.name}" at that time.');
        }
      }
      await (_db.update(_db.programs)..where((t) => t.id.equals(programId))).write(
        ProgramsCompanion(
          status: const Value('published'),
          updatedAt: Value(DateTime.now()),
          dirty: const Value(true),
        ),
      );
    });
  }

  /// Removes a session from the schedule and from check-in. Past attendance
  /// stays in the history and reports.
  Future<void> cancelSession(String programId) async {
    await (_db.update(_db.programs)..where((t) => t.id.equals(programId))).write(
      ProgramsCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(true),
      ),
    );
  }

  // ------------------------------------------------------------- creation

  Future<String> nextReference() async {
    final count = (await _db.select(_db.programs).get()).length;
    final now = DateTime.now();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    return 'PROG-${now.year}-Q$quarter-${(count + 1).toString().padLeft(3, '0')}';
  }

  Future<Program> createSession(NewSessionInput input) async {
    final title = input.title.trim();
    if (title.length < 3) {
      throw const AppException('Enter a program title (at least 3 letters).');
    }
    if (input.room.trim().isEmpty) {
      throw const AppException('Choose a venue / hall.');
    }
    if (input.endMinute <= input.startMinute) {
      throw const AppException('The end time must be after the start time.');
    }
    if (input.capacity < 1) {
      throw const AppException('Seat capacity must be at least 1.');
    }
    final roomLimit = knownRooms[input.room];
    if (roomLimit != null && input.capacity > roomLimit) {
      throw AppException('${input.room} seats at most $roomLimit.');
    }
    final day = _day(input.day);
    if (day.isBefore(_day(DateTime.now()))) {
      throw const AppException('Choose today or a later date.');
    }

    return _db.transaction(() async {
      if (input.publish) {
        final clash = await _findRoomClash(input, day);
        if (clash != null) {
          throw AppException(
              '${input.room} is already booked for "${clash.name}" at that time.');
        }
      }

      final id = newId();
      final now = DateTime.now();
      final order = (await _db.select(_db.programs).get()).length;
      await _db.into(_db.programs).insert(
            ProgramsCompanion.insert(
              id: id,
              name: title,
              location: input.room.trim(),
              updatedAt: now,
              startMinute: Value(input.startMinute),
              endMinute: Value(input.endMinute),
              note: Value(input.note),
              sessionDate: Value(day),
              recurrence: Value(input.recurrence),
              pillar: Value(input.pillar),
              format: Value(input.format),
              capacity: Value(input.capacity),
              facilitator: Value(input.facilitator),
              walkInsAllowed: Value(input.walkInsAllowed),
              audience: Value(input.audience.isEmpty ? null : input.audience.join(',')),
              status: Value(input.publish ? 'published' : 'draft'),
              sortOrder: Value(order),
            ),
          );
      return (_db.select(_db.programs)..where((p) => p.id.equals(id))).getSingle();
    });
  }

  Future<Program?> _findRoomClash(NewSessionInput input, DateTime day,
      {String? ignoreId}) async {
    final candidates = await (_db.select(_db.programs)
          ..where((p) => p.location.equals(input.room.trim())))
        .get();
    // A recurring new session is checked on its first day only.
    for (final p in candidates) {
      if (p.id == ignoreId) continue;
      if (!ProgramSchedule.occursOn(p, day)) continue;
      final s = p.startMinute;
      final e = p.endMinute;
      if (s == null || e == null) continue;
      if (input.startMinute < e && s < input.endMinute) return p;
    }
    return null;
  }
}
