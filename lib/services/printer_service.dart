import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';

enum PrinterConnectionState { disconnected, scanning, connecting, connected }

/// Formats d'etiquettes Niimbot courants (mm → pixels a 203 DPI)
class LabelFormat {
  final String label;
  final int widthMm;
  final int heightMm;
  final int widthPx;
  final int heightPx;

  const LabelFormat(this.label, this.widthMm, this.heightMm, this.widthPx, this.heightPx);

  String get key => '${widthMm}x$heightMm';
}

const List<LabelFormat> labelFormats = [
  LabelFormat('50 x 30 mm', 50, 30, 400, 240),
  LabelFormat('40 x 30 mm', 40, 30, 320, 240),
  LabelFormat('50 x 40 mm', 50, 40, 400, 320),
  LabelFormat('40 x 20 mm', 40, 20, 320, 160),
  LabelFormat('50 x 50 mm', 50, 50, 400, 400),
];

class SentryPrinterService {
  // Imprimante sauvegardee
  String? _savedPrinterMac;
  String? _savedPrinterName;
  LabelFormat _labelFormat = labelFormats[0]; // 50x30 par defaut

  // Etat
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
  LabelFormat get labelFormat => _labelFormat;

  StreamSubscription? _scanSubscription;

  void _setState(PrinterConnectionState state) {
    if (_disposed) return;
    _currentState = state;
    _stateController.add(state);
  }

  /// Charge le MAC/nom/format de l'imprimante sauvegardee
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedPrinterMac = prefs.getString('printer_mac');
      _savedPrinterName = prefs.getString('printer_name');
      final formatKey = prefs.getString('label_format');
      if (formatKey != null) {
        _labelFormat = labelFormats.firstWhere(
          (f) => f.key == formatKey,
          orElse: () => labelFormats[0],
        );
      }
    } catch (_) {}
  }

  /// Change le format d'etiquette
  Future<void> saveLabelFormat(LabelFormat format) async {
    _labelFormat = format;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('label_format', format.key);
    } catch (_) {}
  }

  /// Scan BLE pour trouver des imprimantes Niimbot
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
        if (devName.isEmpty) continue;

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
    final name = _discoveredPrinters[mac] ?? "Imprimante";

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('printer_mac');
      await prefs.remove('printer_name');
    } catch (_) {}
    _savedPrinterMac = null;
    _savedPrinterName = null;
    _isConnecting = false;
    _setState(PrinterConnectionState.disconnected);
  }

  /// Connexion + impression via niim_blue_flutter + deconnexion
  ///
  /// [pngBytes] : image PNG de l'etiquette
  /// [labelWidth] / [labelHeight] : dimensions en pixels pour la PrintPage
  Future<void> connectAndPrint({
    required Uint8List pngBytes,
    required int labelWidth,
    required int labelHeight,
  }) async {
    if (_savedPrinterMac == null) {
      throw Exception("Aucune imprimante associee");
    }
    if (_isConnecting) {
      throw Exception("Impression deja en cours");
    }

    _isConnecting = true;
    final client = NiimbotBluetoothClient();

    try {
      // 1. Trouver le device BLE sauvegarde
      _setState(PrinterConnectionState.scanning);

      BluetoothDevice? targetDevice;

      // Chercher dans les appareils bonded (Android)
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

      // Si pas trouve, scan rapide
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

      // 2. Connexion via niim_blue_flutter
      _setState(PrinterConnectionState.connecting);
      client.setDevice(targetDevice);
      await client.connect();
      client.stopHeartbeat();

      _setState(PrinterConnectionState.connected);

      // 3. Creer la tache d'impression
      final task = client.createPrintTask(
        const PrintOptions(totalPages: 1, density: 3),
      );

      if (task == null) {
        throw Exception("Modele d'imprimante non supporte");
      }

      // 4. Construire la page avec l'image PNG
      final page = PrintPage(labelWidth, labelHeight);
      page.addImageFromBuffer(ImageFromBufferOptions(
        x: 0,
        y: 0,
        width: labelWidth,
        height: labelHeight,
        buffer: pngBytes,
        threshold: 128,
      ));

      // 5. Imprimer
      await task.printInit();
      await task.printPage(page.toEncodedImage(), 1);
      await task.waitForFinished();

      // 6. Deconnexion
      await client.disconnect();
      _setState(PrinterConnectionState.disconnected);
    } catch (e) {
      try {
        await client.disconnect();
      } catch (_) {}
      _setState(PrinterConnectionState.disconnected);
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  void dispose() {
    _disposed = true;
    _scanSubscription?.cancel();
    _stateController.close();
    _discoveredPrintersController.close();
  }
}
