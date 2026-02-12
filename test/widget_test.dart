import 'package:flutter_test/flutter_test.dart';

import 'package:o2_sentry/main.dart';
import 'package:o2_sentry/services/bluetooth_service.dart';
import 'package:o2_sentry/services/printer_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final btService = SentryBluetoothService();
    final printerService = SentryPrinterService();
    await tester.pumpWidget(MyApp(btService: btService, printerService: printerService));
    expect(find.text('O2-SENTRY'), findsOneWidget);
  });
}
