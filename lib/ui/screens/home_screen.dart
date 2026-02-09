import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';
import '../../models/sensor_model.dart';
import '../../services/o2_math_engine.dart';
import '../../services/bluetooth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SentryBluetoothService _bt = SentryBluetoothService();
  SensorProfile selectedSensor = sensorLibrary[0];
  double currentMv = 0.0;
  double calMv = 11.5;

  @override
  void initState() {
    super.initState();
    _bt.startScan();
    _bt.mvStream.listen((mv) => setState(() => currentMv = mv));
  }

  @override
  Widget build(BuildContext context) {
    double fo2 = O2MathEngine.calculateFO2(currentMv, calMv);
    return Scaffold(
      backgroundColor: kScaffoldBg,
      appBar: AppBar(title: const Text("O2-SENTRY"), backgroundColor: Colors.black),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("${fo2.toStringAsFixed(1)}%", style: const TextStyle(fontSize: 60, color: kSentryBlue)),
            const Text("OXYGENE", style: TextStyle(color: Colors.white)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => setState(() => calMv = currentMv),
              child: const Text("CALIBRER"),
            ),
          ],
        ),
      ),
    );
  }
}
