import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

enum SentryConnectionState { disconnected, scanning, connecting, connected }

class SentryBluetoothService {
  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? device;
  String? _savedMac;
  bool _isConnecting = false;
  bool _disposed = false;
  double currentMv = 0.0;
  double calMv = 10.5;
  double ppo2Limit = 1.4;
  DateTime? installationDate;

  final StreamController<double> _mvController =
      StreamController<double>.broadcast();
  Stream<double> get mvStream => _mvController.stream;

  final StreamController<SentryConnectionState> _stateController =
      StreamController<SentryConnectionState>.broadcast();
  Stream<SentryConnectionState> get connectionStateStream =>
      _stateController.stream;

  SentryConnectionState _currentState = SentryConnectionState.disconnected;
  SentryConnectionState get currentState => _currentState;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription? _charSubscription;
  Timer? _reconnectTimer;

  String? get associatedMac => _savedMac;

  void _setState(SentryConnectionState state) {
    if (_disposed) return;
    _currentState = state;
    _stateController.add(state);
  }

  /// Initialisation : Charge toutes les données sauvegardées
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedMac = prefs.getString('associated_mac');
    calMv = prefs.getDouble('cal_mv') ?? 10.5;
    ppo2Limit = prefs.getDouble('ppo2_limit') ?? 1.4;

    String? dateStr = prefs.getString('install_date');
    if (dateStr != null) {
      installationDate = DateTime.parse(dateStr);
    }
  }

  /// Sauvegarde la tension de calibration (mV à l'air)
  Future<void> saveCalibration(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cal_mv', value);
    calMv = value;
  }

  /// Sauvegarde la limite de ppO2 choisie (1.3 - 1.6)
  Future<void> savePPO2(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ppo2_limit', value);
    ppo2Limit = value;
  }

  /// Sauvegarde la date d'installation de la sonde
  Future<void> saveInstallDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('install_date', date.toIso8601String());
    installationDate = date;
  }

  /// Supprime l'association et déconnecte la sonde
  Future<void> forgetDevice() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
    _charSubscription?.cancel();
    _charSubscription = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('associated_mac');
    _savedMac = null;
    if (device != null) {
      await device!.disconnect();
    }
    device = null;
    _isConnecting = false;
    _setState(SentryConnectionState.disconnected);
  }

  /// Démarre le scan Bluetooth (Ciblé ou Global)
  void startScan() async {
    if (_isConnecting) return;
    if (_disposed) return;
    if (_currentState == SentryConnectionState.connected) return;

    _setState(SentryConnectionState.scanning);

    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }

    await FlutterBluePlus.stopScan();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String devName = r.device.platformName.toUpperCase();
        String devId = r.device.remoteId.toString();

        // 1. Si on connaît déjà la sonde, on ne se connecte qu'à elle
        if (_savedMac != null) {
          if (devId == _savedMac) {
            _connectToDevice(r.device);
            FlutterBluePlus.stopScan();
          }
        }
        // 2. Sinon, on cherche une sonde O2-SENTRY pour l'association
        else if (devName.contains("O2-SENTRY")) {
          _connectToDevice(r.device);
          FlutterBluePlus.stopScan();
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    // Après le timeout du scan, si toujours en scanning → disconnected
    if (_currentState == SentryConnectionState.scanning) {
      _setState(SentryConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Gère la connexion à l'appareil
  void _connectToDevice(BluetoothDevice d) async {
    if (_isConnecting) return;
    _isConnecting = true;
    _setState(SentryConnectionState.connecting);
    try {
      await d.connect();
      device = d;

      // Écouter les changements d'état de connexion du device
      _deviceStateSubscription?.cancel();
      _deviceStateSubscription = d.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          // Ne réagir que si on était connecté (évite les faux événements
          // pendant la phase de connexion/découverte de services)
          if (_currentState == SentryConnectionState.connected) {
            _setState(SentryConnectionState.disconnected);
            _charSubscription?.cancel();
            _charSubscription = null;
            _isConnecting = false;
            _scheduleReconnect();
          }
        }
      });

      // Sauvegarde la MAC si c'est une nouvelle association
      if (_savedMac == null) {
        final prefs = await SharedPreferences.getInstance();
        _savedMac = d.remoteId.toString();
        await prefs.setString('associated_mac', _savedMac!);
      }
      _discoverServices(d);
    } catch (e) {
      _isConnecting = false;
      _setState(SentryConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Découvre les services et s'abonne aux notifications de tension (mV)
  void _discoverServices(BluetoothDevice d) async {
    List<BluetoothService> services = await d.discoverServices();
    for (var s in services) {
      if (s.uuid.toString().toLowerCase() == serviceUuid) {
        for (var c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == charUuid) {
            await c.setNotifyValue(true);
            _charSubscription?.cancel();
            _charSubscription = c.onValueReceived.listen((data) {
              try {
                // Décodage du message envoyé par l'ESP32
                String raw = utf8.decode(data).trim();
                double? val = double.tryParse(raw);
                if (val != null) {
                  currentMv = val;
                  _mvController.add(val);
                }
              } catch (e) {
                // Erreur de parsing ignorée pour la stabilité
              }
            });
          }
        }
      }
    }
    _isConnecting = false;
    _setState(SentryConnectionState.connected);
  }

  /// Planifie une tentative de reconnexion après 3 secondes
  void _scheduleReconnect() {
    if (_disposed) return;
    if (_savedMac == null) return;
    if (_reconnectTimer?.isActive == true) return;

    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed &&
          _savedMac != null &&
          _currentState != SentryConnectionState.connected) {
        startScan();
      }
    });
  }

  /// Libère toutes les ressources
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _deviceStateSubscription?.cancel();
    _charSubscription?.cancel();
    _scanSubscription?.cancel();
    _mvController.close();
    _stateController.close();
  }
}
