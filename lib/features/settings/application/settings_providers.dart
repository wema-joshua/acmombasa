import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/live_query.dart';
import '../../../core/providers.dart';

class SettingsValues {
  const SettingsValues({required this.capacity, required this.monthlyTarget});

  final int capacity;
  final int monthlyTarget;
}

final settingsValuesProvider = StreamProvider<SettingsValues>((ref) {
  final db = ref.watch(databaseProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  return watchQuery(db, () async {
    return SettingsValues(
      capacity: await settings.capacity(),
      monthlyTarget: await settings.monthlyTarget(),
    );
  });
});

final staffListProvider = StreamProvider<List<StaffUser>>((ref) {
  final db = ref.watch(databaseProvider);
  final auth = ref.watch(authRepositoryProvider);
  return watchQuery(db, auth.listStaff);
});
