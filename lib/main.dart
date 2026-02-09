import 'package:flutter/material.dart';
import 'services/bluetooth_service.dart';
import 'screens/home_screen.dart';

void main() async {
  // Indispensable pour l'initialisation asynchrone
  WidgetsFlutterBinding.ensureInitialized();

  final SentryBluetoothService bluetoothService = SentryBluetoothService();

  // Charge l'appareil associé depuis la mémoire
  await bluetoothService.init();

  runApp(MyApp(btService: bluetoothService));
}

class MyApp extends StatelessWidget {
  final SentryBluetoothService btService;
  const MyApp({super.key, required this.btService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'O2-Sentry',
      theme: ThemeData.dark(),
      home: HomeScreen(btService: btService),
    );
  }
}
