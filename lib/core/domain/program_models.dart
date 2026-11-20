import '../database/app_database.dart';

abstract final class Pillars {
  static const english = 'English Language & Teaching';
  static const stem = 'STEM & Makerspace Innovation';
  static const educationUsa = 'EducationUSA & Library';
  static const alumni = 'Alumni & Civic Engagement';
  static const culture = 'Cultural Programs & Arts';

  static const all = [english, stem, educationUsa, alumni, culture];

  /// "STEM & Makerspace Innovation" -> "#StemMakerspaceInnovation".
  static String hashtag(String pillar) {
    final words = pillar
        .replaceAll('&', ' ')
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty);
    return '#${words.map((w) => w[0].toUpperCase() + w.substring(1)).join()}';
  }
}

abstract final class ProgramFormat {
  static const inPerson = 'in_person';
  static const hybrid = 'hybrid';
  static const outreach = 'outreach';

  static String label(String f) => switch (f) {
        hybrid => 'Hybrid / Virtual Sync',
        outreach => 'Outreach / Partner Site',
        _ => 'In-Person (Center)',
      };
}

abstract final class Recurrence {
  static const none = 'none';
  static const daily = 'daily';
  static const weekly = 'weekly';

  static String label(String r) => switch (r) {
        daily => 'Daily',
        weekly => 'Weekly',
        _ => 'One-time Session',
      };
}

/// Rooms offered when scheduling, with their seat limits.
const Map<String, int> knownRooms = {
  'Burhani Hall': 60,
  'Makerspace & STEM Lab 2': 16,
  'Quiet Study Zone': 20,
  'Creative Corner Lab': 24,
  'Lab 2': 20,
  'Main Hall': 60,
};

abstract final class ProgramSchedule {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Does [p] run on [day]? Legacy programs (no date) run every day.
  static bool occursOn(Program p, DateTime day) {
    if (!p.isActive || p.status != 'published') return false;
    final d = _day(day);
    final first = p.sessionDate == null ? null : _day(p.sessionDate!);
    if (first != null && d.isBefore(first)) return false;
    return switch (p.recurrence) {
      Recurrence.none => first == null || d == first,
      Recurrence.weekly => first == null || d.weekday == first.weekday,
      _ => true,
    };
  }
}

enum SessionPhase { inSession, startingSoon, scheduled, completed, allDay }

class SessionView {
  const SessionView({
    required this.program,
    required this.day,
    required this.registered,
    required this.present,
    required this.walkIns,
    required this.phase,
    this.minutesElapsed,
    this.minutesToStart,
    this.minutesRemaining,
  });

  final Program program;
  final DateTime day;
  final int registered;

  /// Visitors checked in to this session on [day].
  final int present;
  final int walkIns;
  final SessionPhase phase;
  final int? minutesElapsed;
  final int? minutesToStart;
  final int? minutesRemaining;

  /// People holding a seat: pre-registered plus walk-ins admitted.
  int get seatsTaken => registered + walkIns;

  bool get isFull =>
      program.capacity != null && seatsTaken >= program.capacity!;
}

enum RosterStatus { present, walkIn, awaiting }

class RosterEntry {
  const RosterEntry({
    required this.visitor,
    required this.status,
    this.visit,
    this.registrationId,
  });

  final Visitor visitor;
  final RosterStatus status;
  final Visit? visit;
  final String? registrationId;
}

class DaySummary {
  const DaySummary({
    required this.sessions,
    required this.ongoing,
    required this.ongoingRoom,
    required this.preRegistered,
    required this.walkIns,
    required this.seatsTotal,
    required this.seatsReserved,
    required this.rooms,
    required this.flagshipName,
    required this.flagshipAverage,
  });

  final int sessions;
  final int ongoing;
  final String? ongoingRoom;
  final int preRegistered;
  final int walkIns;
  final int seatsTotal;
  final int seatsReserved;
  final List<String> rooms;
  final String? flagshipName;
  final int flagshipAverage;

  double get occupancy => seatsTotal == 0 ? 0 : seatsReserved / seatsTotal;
}

class NewSessionInput {
  const NewSessionInput({
    required this.title,
    required this.pillar,
    required this.format,
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.recurrence,
    required this.room,
    required this.capacity,
    required this.walkInsAllowed,
    required this.audience,
    required this.publish,
    this.facilitator,
    this.note,
  });

  final String title;
  final String pillar;
  final String format;
  final DateTime day;
  final int startMinute;
  final int endMinute;
  final String recurrence;
  final String room;
  final int capacity;
  final bool walkInsAllowed;
  final List<String> audience;
  final bool publish;
  final String? facilitator;
  final String? note;
}
