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
  String? _savedProbeName;
  String? _savedProbeMac;
  bool _isConnecting = false;
  bool _disposed = false;
  double currentMv = 0.0;
  double calMv = 10.5;
  double ppo2Limit = 1.4;
  DateTime? installationDate;
  DateTime? calibrationDate;

  // Modèle de sonde et plages mV dynamiques
  String sensorModel = "Teledyne R-17MED";
  double sensorMvMin = 7.0;
  double sensorMvMax = 13.0;

  // Buffer des dernières mesures mV (pour vérification stabilité)
  final List<double> _mvBuffer = [];
  List<double> get recentMv => List.unmodifiable(_mvBuffer);

  // Batterie
  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;
  final StreamController<int> _batteryController =
      StreamController<int>.broadcast();
  Stream<int> get batteryStream => _batteryController.stream;

  // Sondes découvertes (pour le dialog de sélection)
  // Clé = adresse MAC (identifiant unique), valeur = nom d'affichage
  final Map<String, String> _discoveredProbes = {};
  final Map<String, BluetoothDevice> _discoveredDeviceMap = {};
  final StreamController<Map<String, String>> _discoveredProbesController =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get discoveredProbesStream =>
      _discoveredProbesController.stream;

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
  Timer? _mvWatchdog;
  DateTime? _lastScanTime;
  static const int _minScanIntervalSeconds = 10;

  String? get associatedProbeName => _savedProbeName;
  String? get associatedProbeMac => _savedProbeMac;

  /// Vrai si une sonde est associée (verrouillée par MAC).
  bool get isPaired => _savedProbeMac != null;

  void _setState(SentryConnectionState state) {
    if (_disposed) return;
    _currentState = state;
    _stateController.add(state);
  }

  /// Initialisation : Charge toutes les données sauvegardées
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _savedProbeMac = prefs.getString('associated_probe_mac');
      _savedProbeName = prefs.getString('associated_probe_name');
      calMv = prefs.getDouble('cal_mv') ?? 10.5;
      ppo2Limit = prefs.getDouble('ppo2_limit') ?? 1.4;

      String? dateStr = prefs.getString('install_date');
      if (dateStr != null) {
        installationDate = DateTime.parse(dateStr);
      }

      String? calDateStr = prefs.getString('calibration_date');
      if (calDateStr != null) {
        calibrationDate = DateTime.parse(calDateStr);
      }

      // Charger le modèle de sonde et ses plages mV
      sensorModel = prefs.getString('sensor_model') ?? sensorModel;
      sensorMvMin = prefs.getDouble('sensor_mv_min') ?? sensorMvMin;
      sensorMvMax = prefs.getDouble('sensor_mv_max') ?? sensorMvMax;
    } catch (e) {
      // Garder les valeurs par défaut si SharedPreferences échoue
    }
  }

  /// Sauvegarde la tension de calibration (mV à l'air) et la date
  Future<void> saveCalibration(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setDouble('cal_mv', value);
      await prefs.setString('calibration_date', now.toIso8601String());
      calMv = value;
      calibrationDate = now;
    } catch (e) {
      // Ne pas mettre à jour si la sauvegarde échoue
    }
  }

  /// Sauvegarde la limite de ppO2 choisie (1.3 - 1.6)
  Future<void> savePPO2(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('ppo2_limit', value);
      ppo2Limit = value;
    } catch (e) {
      // Ne pas mettre à jour ppo2Limit si la sauvegarde échoue
    }
  }

  /// Sauvegarde la date d'installation de la sonde
  Future<void> saveInstallDate(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('install_date', date.toIso8601String());
      installationDate = date;
    } catch (e) {
      // Ne pas mettre à jour installationDate si la sauvegarde échoue
    }
  }

  /// Sauvegarde le modèle de sonde et ses plages mV
  Future<void> saveSensorModel(String name, double min, double max) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sensor_model', name);
      await prefs.setDouble('sensor_mv_min', min);
      await prefs.setDouble('sensor_mv_max', max);
      sensorModel = name;
      sensorMvMin = min;
      sensorMvMax = max;
    } catch (e) {
      // Ne pas mettre à jour si la sauvegarde échoue
    }
  }

  /// Supprime l'association et déconnecte la sonde
  Future<void> forgetDevice() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _mvWatchdog?.cancel();
    _mvWatchdog = null;
    _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
    _charSubscription?.cancel();
    _charSubscription = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('associated_probe_mac');
      await prefs.remove('associated_probe_name');
    } catch (e) {
      // La déconnexion doit continuer même si le storage échoue
    }
    _savedProbeMac = null;
    _savedProbeName = null;
    _discoveredProbes.clear();
    _discoveredDeviceMap.clear();
    _batteryLevel = null;
    if (device != null) {
      await device!.disconnect();
    }
    device = null;
    _isConnecting = false;
    _setState(SentryConnectionState.disconnected);
  }

  /// Appelée par le UI quand l'utilisateur choisit une sonde par son MAC
  Future<void> selectProbe(String mac) async {
    final device = _discoveredDeviceMap[mac];
    final name = _discoveredProbes[mac] ?? "O2-SENTRY";
    if (device != null) {
      _connectToDevice(device, name);
    }
  }

  /// Vérifie si un appareil BLE advertise notre service UUID
  bool _hasOurService(ScanResult r) {
    return r.advertisementData.serviceUuids
        .any((uuid) => uuid.toString().toLowerCase() == serviceUuid);
  }

  /// Démarre le scan Bluetooth
  void startScan() async {
    if (_isConnecting) return;
    if (_disposed) return;
    if (_currentState == SentryConnectionState.connected) return;

    // Anti-spam : empecher les scans trop rapproches (Android throttle a ~5 scans/30s)
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!).inSeconds < _minScanIntervalSeconds) {
      _scheduleReconnect();
      return;
    }
    _lastScanTime = now;

    _setState(SentryConnectionState.scanning);

    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }

    // 1. Vérifier les appareils bonded (Android) pour connexion rapide par MAC
    if (_savedProbeMac != null && Platform.isAndroid) {
      try {
        final bondedDevices = await FlutterBluePlus.bondedDevices;
        for (var d in bondedDevices) {
          if (d.remoteId.str == _savedProbeMac) {
            final name = d.platformName.isNotEmpty
                ? d.platformName
                : _savedProbeName ?? "O2-SENTRY";
            _connectToDevice(d, name);
            return;
          }
        }
      } catch (_) {}
    }

    await FlutterBluePlus.stopScan();

    // Vider les sondes découvertes pour un scan frais
    _discoveredProbes.clear();
    _discoveredDeviceMap.clear();

    // 2. Scan BLE — détection par nom ET par UUID de service
    //    Dédupliqué par adresse MAC pour éviter les doublons
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        String devName = r.advertisementData.advName;
        if (devName.isEmpty) {
          devName = r.device.platformName;
        }

        bool hasService = _hasOurService(r);
        final mac = r.device.remoteId.str;

        // Ni nom ni service connu → ignorer
        if (devName.isEmpty && !hasService) continue;

        if (_savedProbeMac != null) {
          // Sonde associée → auto-connexion UNIQUEMENT par MAC
          if (mac == _savedProbeMac) {
            final name = devName.isNotEmpty
                ? devName
                : _savedProbeName ?? "O2-SENTRY";
            _connectToDevice(r.device, name);
            FlutterBluePlus.stopScan();
            return;
          }
        } else {
          // Mode découverte → collecter O2-SENTRY, dédupliqué par MAC
          bool isO2Sentry =
              devName.toUpperCase().startsWith("O2-SENTRY") || hasService;
          if (isO2Sentry) {
            String displayName =
                devName.isNotEmpty ? devName : "O2-SENTRY [$mac]";

            final existingName = _discoveredProbes[mac];
            if (existingName == null) {
              // Nouveau device
              _discoveredProbes[mac] = displayName;
              _discoveredDeviceMap[mac] = r.device;
              _discoveredProbesController.add(Map.of(_discoveredProbes));
            } else if (existingName.contains('[') &&
                !displayName.contains('[')) {
              // Nom réel reçu → remplacer le placeholder MAC
              _discoveredProbes[mac] = displayName;
              _discoveredDeviceMap[mac] = r.device;
              _discoveredProbesController.add(Map.of(_discoveredProbes));
            }
          }
        }
      }
    });

    // Mode lowLatency = scan plus rapide (duty cycle max)
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidScanMode: AndroidScanMode.lowLatency,
    );

    // Après le timeout du scan, si toujours en scanning → disconnected
    if (_currentState == SentryConnectionState.scanning) {
      _setState(SentryConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Gère la connexion à l'appareil
  void _connectToDevice(BluetoothDevice d, String probeName) async {
    if (_isConnecting) return;
    _isConnecting = true;
    _setState(SentryConnectionState.connecting);
    try {
      await d.connect(timeout: const Duration(seconds: 10));
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
            _mvWatchdog?.cancel();
            _mvWatchdog = null;
            _isConnecting = false;
            _scheduleReconnect();
          }
        }
      });

      // Sauvegarder l'association par MAC + nom (affichage uniquement)
      final mac = d.remoteId.str;
      final hasGoodName = probeName.isNotEmpty && !probeName.contains('[');

      if (_savedProbeMac != mac || (hasGoodName && probeName != _savedProbeName)) {
        _savedProbeMac = mac;
        if (hasGoodName) _savedProbeName = probeName;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('associated_probe_mac', mac);
          if (_savedProbeName != null) {
            await prefs.setString('associated_probe_name', _savedProbeName!);
          }
        } catch (e) {
          // Continuer même si la sauvegarde échoue
        }
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
    try {
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
                  // Format attendu : "mV,batterie" ou "mV" (rétrocompat)
                  String raw = utf8.decode(data).trim();
                  double? mv;
                  int? battery;

                  if (raw.contains(',')) {
                    final parts = raw.split(',');
                    mv = double.tryParse(parts[0]);
                    if (parts.length >= 2) {
                      battery = int.tryParse(parts[1]);
                    }
                  } else {
                    mv = double.tryParse(raw);
                  }

                  if (mv != null) {
                    currentMv = mv;
                    _mvController.add(mv);
                    _resetMvWatchdog();

                    // Buffer circulaire des 10 dernières mesures
                    _mvBuffer.add(mv);
                    if (_mvBuffer.length > 10) {
                      _mvBuffer.removeAt(0);
                    }
                  }
                  if (battery != null && battery >= 0 && battery <= 100) {
                    _batteryLevel = battery;
                    _batteryController.add(battery);
                  }
                } catch (e) {
                  // Erreur de parsing ignorée pour la stabilité
                }
              });
              _resetMvWatchdog();
            }
          }
        }
      }
      _isConnecting = false;
      _setState(SentryConnectionState.connected);
    } catch (e) {
      _isConnecting = false;
      _setState(SentryConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Reset le watchdog mV — si aucune donnée pendant 10s, force reconnexion
  void _resetMvWatchdog() {
    _mvWatchdog?.cancel();
    _mvWatchdog = Timer(const Duration(seconds: 10), () {
      if (_currentState == SentryConnectionState.connected) {
        _setState(SentryConnectionState.disconnected);
        _charSubscription?.cancel();
        _charSubscription = null;
        _isConnecting = false;
        device?.disconnect();
        _scheduleReconnect();
      }
    });
  }

  /// Planifie une tentative de reconnexion
  /// - 5s si sonde associée par MAC (avec anti-spam scan)
  /// - Pas de retry auto si aucune sonde associée
  void _scheduleReconnect() {
    if (_disposed) return;
    if (_savedProbeMac == null) return;
    if (_reconnectTimer?.isActive == true) return;

    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed &&
          _savedProbeMac != null &&
          _currentState != SentryConnectionState.connected) {
        startScan();
      }
    });
  }

  /// Libère toutes les ressources
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _mvWatchdog?.cancel();
    _deviceStateSubscription?.cancel();
    _charSubscription?.cancel();
    _scanSubscription?.cancel();
    _mvController.close();
    _stateController.close();
    _batteryController.close();
    _discoveredProbesController.close();
  }
}
