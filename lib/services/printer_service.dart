import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

enum PrinterConnectionState { disconnected, scanning, connecting, connected }

class SentryPrinterService {
  // UUIDs connus des imprimantes thermiques BLE
  static const List<String> _knownServiceUuids = [
    "000018f0-0000-1000-8000-00805f9b34fb", // Standard BLE Print
    "0000ff00-0000-1000-8000-00805f9b34fb", // Imprimantes chinoises courantes
    "6e400001-b5a3-f393-e0a9-e50e24dcca9e", // Nordic UART (NUS)
    "49535343-fe7d-4ae5-8fa9-9fafd205e455", // Microchip BLE
  ];

  // Imprimante sauvegardee
  String? _savedPrinterMac;
  String? _savedPrinterName;

  // Etat BLE
  BluetoothDevice? _printerDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  bool _isConnecting = false;
  bool _disposed = false;

  // Imprimantes decouvertes
  final Map<String, String> _discoveredPrinters = {};
  final Map<String, BluetoothDevice> _discoveredDeviceMap = {};

  // Streams
  final StreamController<PrinterConnectionState> _stateController =
      StreamController<PrinterConnectionState>.broadcast();
  final StreamController<Map<String, String>> _discoveredPrintersController =
      StreamController<Map<String, String>>.broadcast();

  PrinterConnectionState _currentState = PrinterConnectionState.disconnected;
  PrinterConnectionState get currentState => _currentState;
  Stream<PrinterConnectionState> get connectionStateStream =>
      _stateController.stream;
  Stream<Map<String, String>> get discoveredPrintersStream =>
      _discoveredPrintersController.stream;

  String? get savedPrinterName => _savedPrinterName;
  String? get savedPrinterMac => _savedPrinterMac;
  bool get isPaired => _savedPrinterMac != null;

  StreamSubscription? _scanSubscription;

  void _setState(PrinterConnectionState state) {
    if (_disposed) return;
    _currentState = state;
    _stateController.add(state);
  }

  /// Charge le MAC/nom de l'imprimante sauvegardee
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedPrinterMac = prefs.getString('printer_mac');
      _savedPrinterName = prefs.getString('printer_name');
    } catch (_) {}
  }

  /// Scan BLE pour trouver des imprimantes
  void startScan() async {
    if (_isConnecting || _disposed) return;
    _setState(PrinterConnectionState.scanning);

    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }

    await FlutterBluePlus.stopScan();

    _discoveredPrinters.clear();
    _discoveredDeviceMap.clear();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String devName = r.advertisementData.advName;
        if (devName.isEmpty) devName = r.device.platformName;
        if (devName.isEmpty) continue; // Ignorer les appareils sans nom

        final mac = r.device.remoteId.str;

        if (!_discoveredPrinters.containsKey(mac)) {
          _discoveredPrinters[mac] = devName;
          _discoveredDeviceMap[mac] = r.device;
          _discoveredPrintersController.add(Map.of(_discoveredPrinters));
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidScanMode: AndroidScanMode.lowLatency,
    );

    if (_currentState == PrinterConnectionState.scanning) {
      _setState(PrinterConnectionState.disconnected);
    }
  }

  /// Associe une imprimante par son MAC
  Future<void> selectPrinter(String mac) async {
    final device = _discoveredDeviceMap[mac];
    final name = _discoveredPrinters[mac] ?? "Imprimante";
    if (device == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('printer_mac', mac);
      await prefs.setString('printer_name', name);
      _savedPrinterMac = mac;
      _savedPrinterName = name;
    } catch (_) {}
  }

  /// Oublie l'imprimante sauvegardee
  Future<void> forgetPrinter() async {
    try {
      if (_printerDevice != null) {
        await _printerDevice!.disconnect();
      }
    } catch (_) {}
    _printerDevice = null;
    _writeCharacteristic = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('printer_mac');
      await prefs.remove('printer_name');
    } catch (_) {}
    _savedPrinterMac = null;
    _savedPrinterName = null;
    _isConnecting = false;
    _setState(PrinterConnectionState.disconnected);
  }

  /// Connexion a la demande + impression + deconnexion
  Future<void> connectAndPrint(List<int> bytes) async {
    if (_savedPrinterMac == null) {
      throw Exception("Aucune imprimante associee");
    }

    _setState(PrinterConnectionState.scanning);

    BluetoothDevice? targetDevice;

    // 1. Chercher dans les appareils bonded (Android)
    if (Platform.isAndroid) {
      try {
        final bonded = await FlutterBluePlus.bondedDevices;
        for (var d in bonded) {
          if (d.remoteId.str == _savedPrinterMac) {
            targetDevice = d;
            break;
          }
        }
      } catch (_) {}
    }

    // 2. Si pas trouve, scan rapide
    if (targetDevice == null) {
      final completer = Completer<BluetoothDevice?>();
      late final StreamSubscription sub;

      sub = FlutterBluePlus.onScanResults.listen((results) {
        for (var r in results) {
          if (r.device.remoteId.str == _savedPrinterMac) {
            sub.cancel();
            if (!completer.isCompleted) completer.complete(r.device);
            return;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      // Attendre le resultat ou timeout
      targetDevice = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
      sub.cancel();
      await FlutterBluePlus.stopScan();
    }

    if (targetDevice == null) {
      _setState(PrinterConnectionState.disconnected);
      throw Exception("Imprimante introuvable");
    }

    // 3. Connexion
    _setState(PrinterConnectionState.connecting);
    _isConnecting = true;
    try {
      await targetDevice.connect(timeout: const Duration(seconds: 10));
      _printerDevice = targetDevice;

      // 4. Decouvrir les services et trouver la characteristic d'ecriture
      await _findWriteCharacteristic(targetDevice);

      if (_writeCharacteristic == null) {
        await targetDevice.disconnect();
        _printerDevice = null;
        _isConnecting = false;
        _setState(PrinterConnectionState.disconnected);
        throw Exception("Aucune characteristic d'ecriture trouvee");
      }

      _setState(PrinterConnectionState.connected);

      // 5. Demander MTU eleve
      try {
        await targetDevice.requestMtu(512);
      } catch (_) {}

      // 6. Envoyer les bytes par chunks
      await _writeBytes(bytes);

      // 7. Deconnecter
      await Future.delayed(const Duration(milliseconds: 500));
      await targetDevice.disconnect();
      _printerDevice = null;
      _writeCharacteristic = null;
      _isConnecting = false;
      _setState(PrinterConnectionState.disconnected);
    } catch (e) {
      try {
        await targetDevice.disconnect();
      } catch (_) {}
      _printerDevice = null;
      _writeCharacteristic = null;
      _isConnecting = false;
      _setState(PrinterConnectionState.disconnected);
      rethrow;
    }
  }

  /// Recherche la characteristic d'ecriture parmi les services connus
  Future<void> _findWriteCharacteristic(BluetoothDevice device) async {
    final services = await device.discoverServices();

    // Chercher dans les UUIDs connus d'abord
    for (var serviceUuid in _knownServiceUuids) {
      for (var s in services) {
        if (s.uuid.toString().toLowerCase() == serviceUuid) {
          for (var c in s.characteristics) {
            if (c.properties.write || c.properties.writeWithoutResponse) {
              _writeCharacteristic = c;
              return;
            }
          }
        }
      }
    }

    // Fallback : chercher toute characteristic writable
    for (var s in services) {
      for (var c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          _writeCharacteristic = c;
          return;
        }
      }
    }
  }

  /// Envoie les bytes par chunks selon le MTU
  Future<void> _writeBytes(List<int> bytes) async {
    if (_writeCharacteristic == null || _printerDevice == null) return;

    final mtu = _printerDevice!.mtuNow;
    final chunkSize = (mtu - 3).clamp(20, 512);
    final useWithoutResponse =
        _writeCharacteristic!.properties.writeWithoutResponse;

    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize > bytes.length) ? bytes.length : i + chunkSize;
      final chunk = bytes.sublist(i, end);
      await _writeCharacteristic!.write(
        chunk,
        withoutResponse: useWithoutResponse,
      );
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  void dispose() {
    _disposed = true;
    _scanSubscription?.cancel();
    _stateController.close();
    _discoveredPrintersController.close();
  }
}
