import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/bluetooth_service.dart';
import '../services/printer_service.dart';
import '../services/o2_math_engine.dart';
import '../services/label_builder.dart';
import 'config_page.dart';
import 'help_page.dart';

class HomeScreen extends StatefulWidget {
  final SentryBluetoothService btService;
  final SentryPrinterService printerService;
  const HomeScreen({super.key, required this.btService, required this.printerService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String appVersion = "...";
  DateTime? _lastVibration;
  DateTime? _lastReconnectTap;
  StreamSubscription<Map<String, String>>? _probesSub;

  // Historique FO2 pour sparkline (max 60 points)
  final List<double> _fo2History = [];
  static const int _maxHistory = 60;

  Future<void> _printLabel() async {
    final mv = widget.btService.currentMv;
    final fo2 = O2MathEngine.calculateFO2(mv, widget.btService.calMv);
    final mod = O2MathEngine.calculateMOD(fo2, widget.btService.ppo2Limit);
    final ppo2 = widget.btService.ppo2Limit;
    final now = DateTime.now();

    if (!widget.printerService.isPaired) {
      // Pas d'imprimante → partager l'etiquette en image
      await _shareLabel(fo2, ppo2, mod, now);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      ),
    );

    try {
      final fmt = widget.printerService.labelFormat;
      final pngBytes = await LabelBuilder.buildNitroxLabelImage(
        fo2: fo2,
        ppo2Limit: ppo2,
        mod: mod,
        dateTime: now,
        widthPx: fmt.widthPx,
        heightPx: fmt.heightPx,
      );
      await widget.printerService.connectAndPrint(
        pngBytes: pngBytes,
        labelWidth: fmt.widthPx,
        labelHeight: fmt.heightPx,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Etiquette imprimee !")),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur impression : $e")),
        );
      }
    }
  }

  Future<void> _shareLabel(double fo2, double ppo2, double mod, DateTime dateTime) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.cyan),
      ),
    );

    try {
      final pngBytes = await LabelBuilder.buildNitroxLabelImage(
        fo2: fo2,
        ppo2Limit: ppo2,
        mod: mod,
        dateTime: dateTime,
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/o2_sentry_label.png');
      await file.writeAsBytes(pngBytes);

      if (mounted) Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'O2-Sentry Nitrox - FO2: ${fo2.toStringAsFixed(1)}% | '
            'ppO2: ${ppo2.toStringAsFixed(2)} bar | '
            'MOD: ${mod.toStringAsFixed(0)}m',
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur partage : $e")),
        );
      }
    }
  }

  void _manualReconnect() {
    final now = DateTime.now();
    if (_lastReconnectTap != null &&
        now.difference(_lastReconnectTap!).inSeconds < 5) {
      return;
    }
    _lastReconnectTap = now;
    widget.btService.startScan();
  }

  void _triggerAlarmVibration() {
    final now = DateTime.now();
    if (_lastVibration == null ||
        now.difference(_lastVibration!).inSeconds >= 3) {
      _lastVibration = now;
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // Empêche la mise en veille
    _loadVersion();

    if (!widget.btService.isPaired) {
      // Aucune sonde associée → lancer scan + afficher dialog de sélection
      widget.btService.startScan();
      _listenForProbes();
    } else {
      // Sonde associée par MAC → scan pour auto-connexion
      widget.btService.startScan();
    }
  }

  void _listenForProbes() {
    _probesSub?.cancel();
    _probesSub = widget.btService.discoveredProbesStream.listen((probes) {
      if (probes.isNotEmpty && mounted) {
        _probesSub?.cancel();
        _probesSub = null;
        _showProbeSelectionDialog();
      }
    });
  }

  void _showProbeSelectionDialog() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return StreamBuilder<Map<String, String>>(
              stream: widget.btService.discoveredProbesStream,
              builder: (context, snapshot) {
                final probes = snapshot.data ?? {};
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "ASSOCIER UNE SONDE",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (probes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.cyan,
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                "Recherche en cours...",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...probes.entries.map((entry) {
                          final mac = entry.key;
                          final name = entry.value;
                          // Afficher les 6 derniers caractères du MAC
                          final shortMac = mac.length >= 8
                              ? mac.substring(mac.length - 8)
                              : mac;
                          return ListTile(
                            leading: const Icon(
                              Icons.bluetooth,
                              color: Colors.cyan,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              shortMac,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              widget.btService.selectProbe(mac);
                            },
                          );
                        }),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              "ANNULER",
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.btService.startScan();
                              _listenForProbes();
                            },
                            child: const Text(
                              "RELANCER",
                              style: TextStyle(color: Colors.cyan),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = info.version;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.btService.startScan();
    }
  }

  @override
  void dispose() {
    _probesSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  Widget _buildConnectionBanner(SentryConnectionState state) {
    switch (state) {
      case SentryConnectionState.connected:
        return const SizedBox.shrink();
      case SentryConnectionState.scanning:
        return Container(
          width: double.infinity,
          color: Colors.cyan.shade800,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text(
                "RECHERCHE DE LA SONDE...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      case SentryConnectionState.connecting:
        return Container(
          width: double.infinity,
          color: Colors.orange.shade800,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: const Text(
            "CONNEXION EN COURS...",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      case SentryConnectionState.disconnected:
        if (widget.btService.isPaired) {
          // Sonde associée mais déconnectée → bannière rouge plus visible
          return GestureDetector(
            onTap: _manualReconnect,
            child: Container(
              width: double.infinity,
              color: Colors.red.shade800,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      "SONDE DECONNECTEE\nAPPUYEZ POUR RECONNECTER",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Aucune sonde associée → gros bouton bien visible
          return GestureDetector(
            onTap: () {
              widget.btService.startScan();
              _listenForProbes();
            },
            child: Container(
              width: double.infinity,
              color: Colors.blueGrey.shade700,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_searching,
                      color: Colors.white, size: 36),
                  SizedBox(height: 8),
                  Text(
                    "AUCUNE SONDE ASSOCIEE",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "APPUYEZ ICI POUR RECHERCHER",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
    }
  }

  Color _dotColor(SentryConnectionState state) {
    switch (state) {
      case SentryConnectionState.connected:
        return Colors.greenAccent;
      case SentryConnectionState.scanning:
      case SentryConnectionState.connecting:
        return Colors.orangeAccent;
      case SentryConnectionState.disconnected:
        return Colors.redAccent;
    }
  }

  Widget _buildFO2Sparkline() {
    if (_fo2History.length < 2) return const SizedBox.shrink();

    final spots = _fo2History
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final minY = _fo2History.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = _fo2History.reduce((a, b) => a > b ? a : b) + 1;

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 40),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          minX: 0,
          maxX: (_fo2History.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
              barWidth: 1.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF00E5FF).withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text("O2-SENTRY"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                appVersion,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(width: 4),
              StreamBuilder<SentryConnectionState>(
                stream: widget.btService.connectionStateStream,
                initialData: widget.btService.currentState,
                builder: (context, snapshot) {
                  return Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _dotColor(
                        snapshot.data ?? SentryConnectionState.disconnected,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          // BOUTON IMPRESSION
          IconButton(
            icon: const Icon(Icons.print_outlined, color: Colors.white70),
            onPressed: _printLabel,
          ),
          // BOUTON AIDE
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HelpPage()),
            ),
          ),
          // BOUTON PARAMÈTRES
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ConfigPage(btService: widget.btService, printerService: widget.printerService),
              ),
            ).then((_) {
              setState(() {});
              // Après dissociation, relancer le scan automatiquement
              if (!widget.btService.isPaired) {
                widget.btService.startScan();
                _listenForProbes();
              }
            }),
          ),
        ],
      ),
      body: StreamBuilder<SentryConnectionState>(
        stream: widget.btService.connectionStateStream,
        initialData: widget.btService.currentState,
        builder: (context, connSnapshot) {
          final connState =
              connSnapshot.data ?? SentryConnectionState.disconnected;
          return StreamBuilder<double>(
            stream: widget.btService.mvStream,
            builder: (context, snapshot) {
              double mv = snapshot.hasData ? snapshot.data! : 0.0;
              double fo2 =
                  O2MathEngine.calculateFO2(mv, widget.btService.calMv);
              double mod = O2MathEngine.calculateMOD(
                fo2,
                widget.btService.ppo2Limit,
              );

              // Alarme tension sonde (seuils dynamiques selon modèle)
              bool mvAlarm = (mv < widget.btService.sensorMvMin ||
                      mv > widget.btService.sensorMvMax) &&
                  snapshot.hasData;

              // Alarme mélange hyperoxique
              bool fo2Alarm = fo2 > 40 && snapshot.hasData;

              // Alarme sonde périmée (> 365 jours)
              bool expiredAlarm = false;
              if (widget.btService.installationDate != null) {
                expiredAlarm = DateTime.now()
                        .difference(widget.btService.installationDate!)
                        .inDays >
                    365;
              }

              // Alarme calibration périmée (> 24h ou jamais faite)
              bool calAlarm = false;
              if (widget.btService.calibrationDate == null) {
                calAlarm = true;
              } else {
                calAlarm = DateTime.now()
                        .difference(widget.btService.calibrationDate!)
                        .inHours >
                    24;
              }

              // Historique FO2 pour sparkline
              if (snapshot.hasData) {
                _fo2History.add(fo2);
                if (_fo2History.length > _maxHistory) {
                  _fo2History.removeAt(0);
                }
              }

              // Vibration sur alarme active (cooldown 3s)
              if (mvAlarm || expiredAlarm || fo2Alarm) {
                _triggerAlarmVibration();
              }

              return Column(
                children: [
                  _buildConnectionBanner(connState),
                  if (mvAlarm)
                    Container(
                      width: double.infinity,
                      color: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: const Text(
                        "ALARME : TENSION SONDE ANORMALE",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (fo2Alarm)
                    Container(
                      width: double.infinity,
                      color: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: const Text(
                        "MELANGE HYPEROXIQUE (FO2 > 40%)",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (expiredAlarm)
                    Container(
                      width: double.infinity,
                      color: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: const Text(
                        "SONDE PERIMEE (PLUS DE 12 MOIS)",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (calAlarm)
                    Container(
                      width: double.infinity,
                      color: Colors.amber.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: const Text(
                        "CALIBRATION REQUISE (> 24H)",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // JAUGE CIRCULAIRE
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 280,
                                height: 280,
                                child: CircularProgressIndicator(
                                  value: (fo2 / 100).clamp(0, 1),
                                  strokeWidth: 12,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation(
                                    fo2 > 40
                                        ? Colors.orange
                                        : const Color(0xFF00E5FF),
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    "O2",
                                    style: TextStyle(
                                      fontSize: 28,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    "${fo2.toStringAsFixed(1)}%",
                                    style: const TextStyle(
                                      fontSize: 65,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${mv.toStringAsFixed(2)} mV",
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white38,
                                    ),
                                  ),
                                  // Affichage batterie (masqué si ancien firmware)
                                  StreamBuilder<int>(
                                    stream: widget.btService.batteryStream,
                                    builder: (context, batSnapshot) {
                                      final bat = batSnapshot.data ??
                                          widget.btService.batteryLevel;
                                      if (bat == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          "Batterie: $bat%",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: bat > 20
                                                ? Colors.greenAccent
                                                : Colors.redAccent,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          _buildFO2Sparkline(),
                          const SizedBox(height: 15),
                          // BLOC MOD
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 40,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "MOD (${widget.btService.ppo2Limit})",
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "${mod.toStringAsFixed(0)}m",
                                  style: const TextStyle(
                                    fontSize: 80,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
