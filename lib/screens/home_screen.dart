import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/bluetooth_service.dart';
import '../services/o2_math_engine.dart';
import 'config_page.dart';
import 'help_page.dart';

class HomeScreen extends StatefulWidget {
  final SentryBluetoothService btService;
  const HomeScreen({super.key, required this.btService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String appVersion = "...";
  DateTime? _lastVibration;
  DateTime? _lastReconnectTap;

  // Historique FO2 pour sparkline (max 60 points)
  final List<double> _fo2History = [];
  static const int _maxHistory = 60;

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
    widget.btService.startScan();
    _loadVersion();
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
        return GestureDetector(
          onTap: _manualReconnect,
          child: Container(
            width: double.infinity,
            color: Colors.red.shade800,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh, color: Colors.white70, size: 14),
                SizedBox(width: 6),
                Text(
                  "SONDE DÉCONNECTÉE - APPUYEZ POUR RECONNECTER",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
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
                builder: (context) => ConfigPage(btService: widget.btService),
              ),
            ).then((_) => setState(() {})),
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
                        "⚠️ ALARME : TENSION SONDE ANORMALE",
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
                        "⚠️ MÉLANGE HYPEROXIQUE (FO2 > 40%)",
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
                        "⚠️ SONDE PÉRIMÉE (PLUS DE 12 MOIS)",
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
                                    "O₂",
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
