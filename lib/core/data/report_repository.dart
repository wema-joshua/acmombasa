import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/program_models.dart';
import '../domain/report_models.dart';
import '../utils/date_format.dart';
import 'settings_repository.dart';

/// Aggregates for the Reports & Statistical Analytics page. Everything is
/// computed from the local visits, visitors and programs tables.
class ReportRepository {
  ReportRepository(this._db, this._settings);

  final AppDatabase _db;
  final SettingsRepository _settings;

  static const cohortLabels = [
    'Secondary / Under 18',
    'Primary Youth (18-24)',
    'Young Professional (25-34)',
    'Adult / Senior (35+)',
  ];

  static String? cohortOf(String? age) => switch (age) {
        'Under 13' || '13 - 17' => cohortLabels[0],
        '18 - 24' => cohortLabels[1],
        '25 - 34' => cohortLabels[2],
        '35 - 44' || '45 and above' => cohortLabels[3],
        _ => null,
      };

  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  /// Months that have any data, newest first (always includes this month).
  Future<List<DateTime>> availableMonths() async {
    final now = monthStart(DateTime.now());
    final first = await (_db.select(_db.visits)
          ..orderBy([(v) => OrderingTerm.asc(v.checkInAt)])
          ..limit(1))
        .getSingleOrNull();
    final from = first == null ? now : monthStart(first.checkInAt);
    final months = <DateTime>[];
    var m = now;
    while (!m.isBefore(from) && months.length < 36) {
      months.add(m);
      m = DateTime(m.year, m.month - 1);
    }
    return months;
  }

  Future<MonthlyReport> load(DateTime month) async {
    final start = monthStart(month);
    final end = DateTime(start.year, start.month + 1);
    final prevStart = DateTime(start.year, start.month - 1);

    final programs = {
      for (final p in await _db.select(_db.programs).get()) p.id: p,
    };

    final visits = await _visitsBetween(start, end);
    final previous = await _visitsBetween(prevStart, start);

    final visitorIds = visits.map((v) => v.visitorId).toSet();
    final visitors = visitorIds.isEmpty
        ? <String, Visitor>{}
        : {
            for (final v in await (_db.select(_db.visitors)
                  ..where((t) => t.id.isIn(visitorIds)))
                .get())
              v.id: v,
          };

    final newMembers = (await (_db.select(_db.visitors)
              ..where((v) =>
                  v.registeredAt.isBiggerOrEqualValue(start) &
                  v.registeredAt.isSmallerThanValue(end)))
            .get())
        .length;

    // Demographics over unique visitors in the month.
    var female = 0, male = 0, youth = 0, ageRecorded = 0, residenceRecorded = 0;
    final residence = <String, int>{};
    final cohorts = {for (final c in cohortLabels) c: 0};
    for (final v in visitors.values) {
      if (v.gender == 'Female') female++;
      if (v.gender == 'Male') male++;
      final cohort = cohortOf(v.ageBracket);
      if (cohort != null) {
        ageRecorded++;
        cohorts.update(cohort, (c) => c + 1);
        if (v.ageBracket == '18 - 24' || v.ageBracket == '25 - 34') youth++;
      }
      final r = v.residence;
      if (r != null && r.isNotEmpty) {
        residenceRecorded++;
        residence.update(r, (c) => c + 1, ifAbsent: () => 1);
      }
    }

    // Pillars and ledger from program visits.
    final pillarVisits = <String, int>{};
    final pillarPeople = <String, Set<String>>{};
    final pillarSessions = <String, Set<String>>{};
    var eduVisits = 0;
    final eduPeople = <String>{};
    for (final v in visits) {
      final program = v.programId == null ? null : programs[v.programId];
      if (program == null) continue;
      final pillar = program.pillar;
      pillarVisits.update(pillar, (c) => c + 1, ifAbsent: () => 1);
      pillarPeople.putIfAbsent(pillar, () => {}).add(v.visitorId);
      pillarSessions
          .putIfAbsent(pillar, () => {})
          .add('${program.id}|${DateFormatter.isoDate(v.checkInAt)}');
      if (pillar == Pillars.educationUsa) {
        eduVisits++;
        eduPeople.add(v.visitorId);
      }
    }
    final programTotal = pillarVisits.values.fold(0, (a, b) => a + b);
    final pillarNames = [
      ...Pillars.all,
      ...pillarVisits.keys.where((k) => !Pillars.all.contains(k)),
    ];
    final pillars = [
      for (final name in pillarNames)
        PillarShare(
          label: name,
          count: pillarVisits[name] ?? 0,
          fraction: programTotal == 0 ? 0 : (pillarVisits[name] ?? 0) / programTotal,
        ),
    ]..sort((a, b) => b.count.compareTo(a.count));
    final ledger = [
      for (final name in pillarNames)
        PillarLedgerRow(
          pillar: name,
          visits: pillarVisits[name] ?? 0,
          sessions: pillarSessions[name]?.length ?? 0,
          uniqueAttendees: pillarPeople[name]?.length ?? 0,
        ),
    ];

    // Six month trend ending with the selected month.
    final trend = <MonthBar>[];
    for (var i = 5; i >= 0; i--) {
      final s = DateTime(start.year, start.month - i);
      final e = DateTime(s.year, s.month + 1);
      final list = s == start ? visits : await _visitsBetween(s, e);
      final withProgram = list.where((v) => v.programId != null).length;
      trend.add(MonthBar(
        label: DateFormatter.monthShort(s),
        walkIns: list.length - withProgram,
        programVisits: withProgram,
        isSelected: s == start,
      ));
    }

    final now = DateTime.now();
    final daysCounted = monthStart(now) == start
        ? now.day
        : end.difference(start).inDays;

    List<ShareRow> top(Map<String, int> m, int total, int n) {
      final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in list.take(n))
          ShareRow(
            label: e.key,
            count: e.value,
            fraction: total == 0 ? 0 : e.value / total,
          ),
      ];
    }

    return MonthlyReport(
      month: start,
      footfall: visits.length,
      previousFootfall: previous.length,
      target: await _settings.monthlyTarget(),
      dailyAverage: visits.length / (daysCounted == 0 ? 1 : daysCounted),
      uniqueVisitors: visitorIds.length,
      newMembers: newMembers,
      female: female,
      male: male,
      genderRecorded: female + male,
      youth: youth,
      ageRecorded: ageRecorded,
      educationUsaVisits: eduVisits,
      educationUsaAttendees: eduPeople.length,
      trend: trend,
      pillars: pillars,
      ledger: ledger,
      residence: top(residence, residenceRecorded, 5),
      residenceRecorded: residenceRecorded,
      cohorts: [
        for (final c in cohortLabels)
          ShareRow(
            label: c,
            count: cohorts[c]!,
            fraction: ageRecorded == 0 ? 0 : cohorts[c]! / ageRecorded,
          ),
      ],
    );
  }

  Future<List<Visit>> _visitsBetween(DateTime start, DateTime end) {
    return (_db.select(_db.visits)
          ..where((v) =>
              v.checkInAt.isBiggerOrEqualValue(start) &
              v.checkInAt.isSmallerThanValue(end)))
        .get();
  }

  // ---------------------------------------------------- template exports

  /// Venue & facilitator utilisation: one row per program.
  Future<List<List<String>>> utilizationRows(DateTime month) async {
    final start = monthStart(month);
    final end = DateTime(start.year, start.month + 1);
    final visits = (await _visitsBetween(start, end)).where((v) => v.programId != null);
    final programs = await _db.select(_db.programs).get();

    final rows = <List<String>>[
      [
        'Program',
        'Pillar',
        'Venue',
        'Facilitator',
        'Sessions held',
        'Total check-ins',
        'Unique attendees',
        'Seat capacity',
        'Average fill %',
      ],
    ];
    for (final p in programs) {
      final list = visits.where((v) => v.programId == p.id).toList();
      if (list.isEmpty) continue;
      final days = list.map((v) => DateFormatter.isoDate(v.checkInAt)).toSet().length;
      final people = list.map((v) => v.visitorId).toSet().length;
      final fill = p.capacity == null
          ? ''
          : '${((list.length / days) / p.capacity! * 100).round()}';
      rows.add([
        p.name,
        p.pillar,
        p.location,
        p.facilitator ?? '',
        '$days',
        '${list.length}',
        '$people',
        p.capacity?.toString() ?? '',
        fill,
      ]);
    }
    return rows;
  }

  /// Patron retention: who came this month and whether they were new.
  Future<List<List<String>>> retentionRows(DateTime month) async {
    final start = monthStart(month);
    final end = DateTime(start.year, start.month + 1);
    final visits = await _visitsBetween(start, end);
    final perVisitor = <String, int>{};
    for (final v in visits) {
      perVisitor.update(v.visitorId, (c) => c + 1, ifAbsent: () => 1);
    }
    final visitors = perVisitor.isEmpty
        ? <Visitor>[]
        : await (_db.select(_db.visitors)..where((t) => t.id.isIn(perVisitor.keys))).get();

    final rows = <List<String>>[
      ['Member ID', 'Name', 'Visits this month', 'Member since', 'Type'],
    ];
    for (final v in visitors) {
      final isNew = !v.registeredAt.isBefore(start) && v.registeredAt.isBefore(end);
      rows.add([
        v.memberId,
        v.fullName,
        '${perVisitor[v.id]}',
        DateFormatter.isoDate(v.registeredAt),
        isNew ? 'New member' : (perVisitor[v.id]! > 1 ? 'Returning' : 'Single visit'),
      ]);
    }
    return rows;
  }

  /// Partner sheet: attendance per program per day.
  Future<List<List<String>>> partnerRows(DateTime month) async {
    final start = monthStart(month);
    final end = DateTime(start.year, start.month + 1);
    final visits = (await _visitsBetween(start, end)).where((v) => v.programId != null);
    final programs = {
      for (final p in await _db.select(_db.programs).get()) p.id: p,
    };
    final grouped = <String, Set<String>>{};
    for (final v in visits) {
      final key = '${DateFormatter.isoDate(v.checkInAt)}|${v.programId}';
      grouped.putIfAbsent(key, () => {}).add(v.visitorId);
    }
    final keys = grouped.keys.toList()..sort();
    return [
      ['Date', 'Program', 'Pillar', 'Venue', 'Attendees'],
      for (final k in keys)
        [
          k.split('|').first,
          programs[k.split('|').last]?.name ?? '',
          programs[k.split('|').last]?.pillar ?? '',
          programs[k.split('|').last]?.location ?? '',
          '${grouped[k]!.length}',
        ],
    ];
  }
}
