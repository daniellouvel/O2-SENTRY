import 'package:flutter/material.dart';
import 'services/bluetooth_service.dart';
import 'services/printer_service.dart';
import 'screens/home_screen.dart';

void main() async {
  // Indispensable pour l'initialisation asynchrone
  WidgetsFlutterBinding.ensureInitialized();

  final SentryBluetoothService bluetoothService = SentryBluetoothService();
  final SentryPrinterService printerService = SentryPrinterService();

  // Charge les appareils associés depuis la mémoire
  await bluetoothService.init();
  await printerService.init();

  runApp(MyApp(btService: bluetoothService, printerService: printerService));
}

class MyApp extends StatelessWidget {
  final SentryBluetoothService btService;
  final SentryPrinterService printerService;
  const MyApp({super.key, required this.btService, required this.printerService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'O2-Sentry',
      theme: ThemeData.dark(),
      home: HomeScreen(btService: btService, printerService: printerService),
    );
  }
}
