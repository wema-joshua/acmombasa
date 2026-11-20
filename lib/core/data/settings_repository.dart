import 'package:drift/drift.dart';

import '../database/app_database.dart';

abstract final class SettingKeys {
  static const sessionStaffId = 'session_staff_id';
  static const capacity = 'capacity';
  static const monthlyTarget = 'monthly_footfall_target';
  static String syncCursor(String table) => 'sync_cursor_$table';
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const int defaultCapacity = 45;
  static const int defaultMonthlyTarget = 1500;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.settingKey.equals(key)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> set(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(settingKey: key, settingValue: value),
        );
  }

  Future<void> remove(String key) {
    return (_db.delete(_db.appSettings)
          ..where((t) => t.settingKey.equals(key)))
        .go();
  }

  Future<int> capacity() async {
    final raw = await get(SettingKeys.capacity);
    return int.tryParse(raw ?? '') ?? defaultCapacity;
  }

  Future<int> monthlyTarget() async {
    final raw = await get(SettingKeys.monthlyTarget);
    return int.tryParse(raw ?? '') ?? defaultMonthlyTarget;
  }

  Future<void> setCapacity(int value) =>
      set(SettingKeys.capacity, value.toString());

  Future<void> setMonthlyTarget(int value) =>
      set(SettingKeys.monthlyTarget, value.toString());
}
