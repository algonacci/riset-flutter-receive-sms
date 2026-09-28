import 'package:flutter_test/flutter_test.dart';
import 'package:riset_flutter_receive_sms/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('renders inbox page and permission button', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Inbox SMS'), findsOneWidget);
    expect(find.text('Minta Izin SMS'), findsOneWidget);
    expect(find.textContaining('Belum ada SMS masuk'), findsOneWidget);
  });
}
