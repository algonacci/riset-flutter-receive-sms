import 'package:flutter_test/flutter_test.dart';
import 'package:riset_flutter_receive_sms/data/sms_store.dart';
import 'package:riset_flutter_receive_sms/models/sms_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SmsStore store;

  setUp(() async {
    store = SmsStore(dbPath: inMemoryDatabasePath);
    await store.init();
  });

  tearDown(() async {
    await store.close();
  });

  SmsEntry entry({
    int timestamp = 1000,
    String address = '6281234567890',
    String body = 'hello',
  }) {
    return SmsEntry(
      address: address,
      body: body,
      timestamp: timestamp,
      receivedAt: 2000,
    );
  }

  test('insert lalu getAll urut timestamp DESC', () async {
    await store.insert(entry(timestamp: 100));
    await store.insert(entry(timestamp: 300, body: 'ketiga'));
    await store.insert(entry(timestamp: 200, body: 'kedua'));

    final all = await store.getAll();

    expect(all, hasLength(3));
    expect(all[0].timestamp, 300);
    expect(all[1].timestamp, 200);
    expect(all[2].timestamp, 100);
  });

  test('dedupe: insert ganda (alamat+body+timestamp sama) diabaikan', () async {
    await store.insert(entry());
    await store.insert(entry());
    await store.insert(entry());

    expect(await store.count(), 1);

    await store.insert(entry(body: 'beda'));
    expect(await store.count(), 2);
  });

  test('insertAll dengan data duplikat antar batch tetap unik', () async {
    await store.insertAll([entry(timestamp: 10), entry(timestamp: 20)]);
    await store.insertAll([entry(timestamp: 10), entry(timestamp: 30)]);

    expect(await store.count(), 3);
    expect(await store.maxTimestamp(), 30);
  });

  test('maxTimestamp null saat kosong, lalu ikut data terbaru', () async {
    expect(await store.maxTimestamp(), isNull);

    await store.insert(entry(timestamp: 500));
    await store.insert(entry(timestamp: 900));

    expect(await store.maxTimestamp(), 900);
  });

  test('deleteById hanya menghapus satu baris', () async {
    await store.insert(entry(timestamp: 100, body: 'satu'));
    await store.insert(entry(timestamp: 200, body: 'dua'));

    final first = (await store.getAll()).last;
    await store.deleteById(first.id!);

    final all = await store.getAll();
    expect(all, hasLength(1));
    expect(all.single.body, 'dua');
  });

  test('clearAll mengosongkan tabel', () async {
    await store.insertAll([entry(timestamp: 1), entry(timestamp: 2)]);
    expect(await store.count(), 2);

    await store.clearAll();

    expect(await store.count(), 0);
    expect(await store.getAll(), isEmpty);
    expect(await store.maxTimestamp(), isNull);
  });

  test('sebelum init() membuang StateError', () async {
    final fresh = SmsStore(dbPath: inMemoryDatabasePath);
    expect(() => fresh.count(), throwsA(isA<StateError>()));
  });

  group('allowed_senders', () {
    test('tambah, cek, dan list nomor diizinkan', () async {
      expect(await store.getAllowedSenders(), isEmpty);

      await store.addAllowedSender('628111111111');
      await store.addAllowedSender('628222222222');

      final senders = await store.getAllowedSenders();
      expect(senders, hasLength(2));
      expect(senders.first.number, '628111111111');
      expect(await store.containsAllowedSender('628111111111'), isTrue);
      expect(await store.containsAllowedSender('628999999999'), isFalse);
    });

    test('nomor ganda tidak ditambahkan dua kali', () async {
      await store.addAllowedSender('628111111111');
      await store.addAllowedSender('628111111111');

      expect(await store.getAllowedSenders(), hasLength(1));
    });

    test('removeAllowedSender menghapus per id', () async {
      await store.addAllowedSender('628111111111');
      await store.addAllowedSender('628222222222');

      final target = (await store.getAllowedSenders())
          .firstWhere((sender) => sender.number == '628111111111');
      await store.removeAllowedSender(target.id!);

      final remaining = await store.getAllowedSenders();
      expect(remaining, hasLength(1));
      expect(remaining.single.number, '628222222222');
    });
  });

  group('antrian forward', () {
    test('SMS baru pending, urut timestamp ASC, markForwarded mengurangi', () async {
      await store.insert(entry(timestamp: 200, body: 'kedua'));
      await store.insert(entry(timestamp: 100, body: 'pertama'));

      expect(await store.countUnforwarded(), 2);

      final pending = await store.getUnforwarded();
      expect(pending.map((e) => e.timestamp), [100, 200]);

      await store.markForwarded(pending.first.id!);

      expect(await store.countUnforwarded(), 1);
      expect((await store.getUnforwarded()).single.timestamp, 200);
    });

    test('insert yang di-ignore (duplikat) tidak menambah antrian', () async {
      await store.insert(entry(timestamp: 100));
      await store.markForwarded(
        (await store.getUnforwarded()).single.id!,
      );

      await store.insert(entry(timestamp: 100));

      expect(await store.countUnforwarded(), 0);
    });
  });

  group('app_settings', () {
    test('get null saat belum diisi, set dan timpa jalan', () async {
      expect(await store.getSetting('backend_url'), isNull);

      await store.setSetting('backend_url', 'http://192.168.1.5:5000');
      expect(await store.getSetting('backend_url'), 'http://192.168.1.5:5000');

      await store.setSetting('backend_url', 'http://10.0.2.2:5000');
      expect(await store.getSetting('backend_url'), 'http://10.0.2.2:5000');
      expect(await store.getSetting('gateway_id'), isNull);
    });
  });
}
