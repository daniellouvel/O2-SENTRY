import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class SentryBluetoothService {
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  
  BluetoothDevice? device;
  String? _savedMac;
  bool _isConnecting = false;
  double currentMv = 0.0; 
  double calMv = 10.5;
  double ppo2Limit = 1.4;

  final StreamController<double> _mvController = StreamController<double>.broadcast();
  Stream<double> get mvStream => _mvController.stream;
  
  StreamSubscription? _scanSubscription;

  String? get associatedMac => _savedMac;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedMac = prefs.getString('associated_mac');
    calMv = prefs.getDouble('cal_mv') ?? 10.5;
    ppo2Limit = prefs.getDouble('ppo2_limit') ?? 1.4;
  }

  Future<void> saveCalibration(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cal_mv', value);
    calMv = value;
  }

  Future<void> savePPO2(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ppo2_limit', value);
    ppo2Limit = value;
  }

  Future<void> forgetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('associated_mac');
    _savedMac = null;
    if (device != null) await device!.disconnect();
  }

  void startScan() async {
    if (_isConnecting) return;
    
    if (Platform.isAndroid) {
      await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    }

    await FlutterBluePlus.stopScan();

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String devName = r.device.platformName.toUpperCase();
        String devId = r.device.remoteId.toString();

        if (_savedMac != null) {
          if (devId == _savedMac) {
            _connectToDevice(r.device);
            FlutterBluePlus.stopScan();
          }
        } else if (devName.contains("O2-SENTRY")) {
          _connectToDevice(r.device);
          FlutterBluePlus.stopScan();
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  void _connectToDevice(BluetoothDevice d) async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      await d.connect();
      device = d;
      if (_savedMac == null) {
        final prefs = await SharedPreferences.getInstance();
        _savedMac = d.remoteId.toString();
        await prefs.setString('associated_mac', _savedMac!);
      }
      _discoverServices(d);
    } catch (e) {
      _isConnecting = false;
    }
  }

  void _discoverServices(BluetoothDevice d) async {
    List<BluetoothService> services = await d.discoverServices();
    for (var s in services) {
      if (s.uuid.toString().toLowerCase() == serviceUuid) {
        for (var c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == charUuid) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen((data) {
              try {
                String raw = utf8.decode(data).trim();
                double? val = double.tryParse(raw);
                if (val != null) {
                  currentMv = val;
                  _mvController.add(val);
                }
              } catch (e) {}
            });
          }
        }
      }
    }
    _isConnecting = false;
  }
}