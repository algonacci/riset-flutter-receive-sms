import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riset_flutter_receive_sms/models/sms_entry.dart';
import 'package:riset_flutter_receive_sms/services/forward_service.dart';

void main() {
  SmsEntry entry() => const SmsEntry(
        address: '6281234567890',
        body: 'TEMP=31.2',
        timestamp: 1759070000000,
        receivedAt: 1759070001000,
      );

  group('ForwardService.forward', () {
    test('201 dari server -> saved, payload sesuai spek', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{"status":"ok","saved":1}', 201);
      });
      final service = ForwardService(client: client);

      final outcome = await service.forward(
        baseUrl: 'http://192.168.1.5:5000/',
        entry: entry(),
        gatewayId: 'hp-01',
      );

      expect(outcome, ForwardOutcome.saved);
      expect(captured, isNotNull);
      expect(captured!.url.toString(), 'http://192.168.1.5:5000/api/sms');
      expect(captured!.method, 'POST');
      expect(captured!.body, contains('"sender":"6281234567890"'));
      expect(captured!.body, contains('"message":"TEMP=31.2"'));
      expect(captured!.body, contains('"timestamp":1759070000000'));
      expect(captured!.body, contains('"gateway_id":"hp-01"'));
    });

    test('200 duplikat -> saved (tidak dikirim ulang)', () async {
      final client = MockClient(
        (_) async => http.Response('{"status":"ok","saved":0}', 200),
      );
      final service = ForwardService(client: client);

      expect(
        await service.forward(baseUrl: 'http://x:5000', entry: entry()),
        ForwardOutcome.saved,
      );
    });

    test('X-Api-Key dikirim kalau diisi, tidak dikirim kalau kosong', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{"status":"ok","saved":1}', 201);
      });
      final service = ForwardService(client: client);

      await service.forward(
        baseUrl: 'http://x:5000',
        entry: entry(),
        apiKey: 'rahasia-123',
      );
      expect(captured!.headers['x-api-key'], 'rahasia-123');

      await service.forward(baseUrl: 'http://x:5000', entry: entry());
      expect(captured!.headers.containsKey('x-api-key'), isFalse);
    });

    test('400 -> rejected (data tak valid, jangan blok antrian)', () async {
      final client = MockClient(
        (_) async => http.Response('{"errors":["x"]}', 400),
      );
      final service = ForwardService(client: client);

      expect(
        await service.forward(baseUrl: 'http://x:5000', entry: entry()),
        ForwardOutcome.rejected,
      );
    });

    test('500 dan koneksi gagal -> failed', () async {
      final serverError = ForwardService(
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      expect(
        await serverError.forward(baseUrl: 'http://x:5000', entry: entry()),
        ForwardOutcome.failed,
      );

      final down = ForwardService(
        client: MockClient((_) async => throw Exception('connection refused')),
      );
      expect(
        await down.forward(baseUrl: 'http://x:5000', entry: entry()),
        ForwardOutcome.failed,
      );
    });

    test('URL kosong/tanpa skema/0.0.0.0 -> failed tanpa request', () async {
      var called = false;
      final service = ForwardService(
        client: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );

      expect(
        await service.forward(baseUrl: '', entry: entry()),
        ForwardOutcome.failed,
      );
      expect(
        await service.forward(baseUrl: 'bukan-url', entry: entry()),
        ForwardOutcome.failed,
      );
      expect(
        await service.forward(baseUrl: 'http://0.0.0.0:5000', entry: entry()),
        ForwardOutcome.failed,
      );
      expect(called, isFalse);
    });
  });

  group('ForwardService.testConnection', () {
    test('health 200 -> true', () async {
      final service = ForwardService(
        client: MockClient((_) async => http.Response('{"status":"ok"}', 200)),
      );
      expect(await service.testConnection('http://x:5000'), isTrue);
      expect(
        await service.testConnection('http://x:5000/'),
        isTrue,
      );
    });

    test('koneksi gagal atau 0.0.0.0 -> false', () async {
      final service = ForwardService(
        client: MockClient((_) async => throw Exception('down')),
      );
      expect(await service.testConnection('http://x:5000'), isFalse);
      expect(await service.testConnection(''), isFalse);

      var called = false;
      final noCall = ForwardService(
        client: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      expect(await noCall.testConnection('http://0.0.0.0:5000'), isFalse);
      expect(called, isFalse);
    });

    test('health ikut bawa X-Api-Key kalo diisi', () async {
      http.Request? captured;
      final service = ForwardService(
        client: MockClient((request) async {
          captured = request;
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      expect(
        await service.testConnection('http://x:5000', apiKey: 'kunci'),
        isTrue,
      );
      expect(captured!.headers['x-api-key'], 'kunci');
    });
  });
}
