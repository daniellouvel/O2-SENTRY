import os

# Structure du projet O2-Sentry
project_structure = {
    "lib/core/constants.dart": """
import 'package:flutter/material.dart';
const String appVersion = "1.2.0-Sentry";
const Color kSentryBlue = Color(0xFF00E5FF);
const Color kScaffoldBg = Color(0xFF121212);
const Color kCardBg = Color(0xFF1E1E1E);
""",
    "lib/models/sensor_model.dart": """
class SensorProfile {
  final String name;
  final double airVoltage;
  const SensorProfile({required this.name, required this.airVoltage});
}
const List<SensorProfile> sensorLibrary = [
  SensorProfile(name: "PSR-11-39-MDSX1", airVoltage: 11.5),
  SensorProfile(name: "AII SF-01", airVoltage: 10.5),
  SensorProfile(name: "Maxtec MAX-12", airVoltage: 13.0),
];
""",
    "lib/services/o2_math_engine.dart": """
class O2MathEngine {
  static double calculateFO2(double currentMv, double calMv) {
    if (calMv == 0) return 20.9;
    return (currentMv / calMv) * 20.9;
  }
  static double calculateMOD(double fo2, double ppO2Limit) {
    if (fo2 <= 0) return 0;
    return ((ppO2Limit / (fo2 / 100)) - 1) * 10;
  }
}
""",
    "lib/services/bluetooth_service.dart": """
import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SentryBluetoothService {
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  BluetoothDevice? device;
  final StreamController<double> _mvController = StreamController<double>.broadcast();
  Stream<double> get mvStream => _mvController.stream;

  void startScan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == "O2-Sentry") {
          r.device.connect().then((_) => _discover(r.device));
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });
  }

  void _discover(BluetoothDevice d) async {
    device = d;
    List<BluetoothService> services = await d.discoverServices();
    for (var s in services) {
      if (s.uuid.toString() == serviceUuid) {
        for (var c in s.characteristics) {
          if (c.uuid.toString() == charUuid) {
            await c.setNotifyValue(true);
            c.lastValueStream.listen((data) {
              double? val = double.tryParse(utf8.decode(data));
              if (val != null) _mvController.add(val);
            });
          }
        }
      }
    }
  }
}
"""
}

def create_project():
    for path, content in project_structure.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content.strip())
        print(f"✅ Fichier créé : {path}")

if __name__ == "__main__":
    create_project()