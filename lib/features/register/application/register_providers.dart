import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/live_query.dart';
import '../../../core/providers.dart';

/// The 15 most recently registered visitors.
final recentRegistrationsProvider = StreamProvider<List<Visitor>>((ref) {
  final db = ref.watch(databaseProvider);
  return watchQuery(db, () {
    return (db.select(db.visitors)
          ..orderBy([(v) => OrderingTerm.desc(v.registeredAt)])
          ..limit(15))
        .get();
  });
});
