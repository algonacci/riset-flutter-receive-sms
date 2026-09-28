import 'package:flutter_test/flutter_test.dart';
import 'package:riset_flutter_receive_sms/services/sender_allowlist.dart';

void main() {
  group('SenderAllowlist.normalize', () {
    test('0812, +62812, 62812 menghasilkan bentuk sama', () {
      expect(SenderAllowlist.normalize('081234567890'), '6281234567890');
      expect(SenderAllowlist.normalize('+6281234567890'), '6281234567890');
      expect(SenderAllowlist.normalize('6281234567890'), '6281234567890');
      expect(SenderAllowlist.normalize('81234567890'), '6281234567890');
    });

    test('buang semua non-digit (spasi, strip, kurung)', () {
      expect(
        SenderAllowlist.normalize('+62 812-3456 (7890)'),
        '6281234567890',
      );
    });

    test('string kosong/tanpa digit hasilnya kosong', () {
      expect(SenderAllowlist.normalize(''), '');
      expect(SenderAllowlist.normalize('iker'), '');
    });
  });

  group('SenderAllowlist.allows', () {
    test('daftar kosong = semua nomor dibaca', () {
      const allowlist = SenderAllowlist([]);
      expect(allowlist.allows('628111111111'), isTrue);
      expect(allowlist.allows('random'), isTrue);
      expect(allowlist.allows(''), isTrue);
    });

    test('exact match: variasi format nomor yang sama diizinkan', () {
      const allowlist = SenderAllowlist(['6281234567890']);
      expect(allowlist.allows('081234567890'), isTrue);
      expect(allowlist.allows('+6281234567890'), isTrue);
      expect(allowlist.allows('6281234567890'), isTrue);
    });

    test('nomor lain ditolak, termasuk yang prefix-nya mirip', () {
      const allowlist = SenderAllowlist(['6281234567890']);
      expect(allowlist.allows('081234567891'), isFalse);
      expect(allowlist.allows('6281234567890123'), isFalse);
      expect(allowlist.allows('628123456789'), isFalse);
      expect(allowlist.allows(''), isFalse);
    });
  });
}
