import 'package:flutter/services.dart';

import '../data/sms_store.dart';
import '../models/sms_entry.dart';
import 'sender_allowlist.dart';

class InboxSyncer {
  InboxSyncer({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.riset_flutter_receive_sms/inbox');

  final MethodChannel _channel;

  Future<int> sync(
    SmsStore store, {
    SenderAllowlist allowlist = const SenderAllowlist([]),
  }) async {
    final maxTimestamp = await store.maxTimestamp();
    final raw = await _channel.invokeMethod<dynamic>(
      'readInbox',
      {'afterMillis': maxTimestamp ?? 0},
    );
    if (raw is! List || raw.isEmpty) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = <SmsEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<Object?, Object?>.from(item);
      final date = (map['date'] as num?)?.toInt();
      if (date == null) continue;
      final address = map['address'] as String? ?? '';
      if (!allowlist.allows(address)) continue;
      entries.add(SmsEntry(
        address: address,
        body: map['body'] as String? ?? '',
        timestamp: date,
        receivedAt: now,
      ));
    }
    await store.insertAll(entries);
    return entries.length;
  }
}
