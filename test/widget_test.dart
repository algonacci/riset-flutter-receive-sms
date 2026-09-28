import 'package:flutter_test/flutter_test.dart';
import 'package:riset_flutter_receive_sms/main.dart';

void main() {
  testWidgets('renders inbox page and permission button', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Riset Receive SMS'), findsOneWidget);
    expect(find.text('Minta Izin SMS'), findsOneWidget);
    expect(find.textContaining('Belum ada SMS masuk'), findsOneWidget);
  });
}
