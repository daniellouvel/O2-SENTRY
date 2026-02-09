import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/bluetooth_service.dart';
import '../services/o2_math_engine.dart';
import 'config_page.dart';
import 'help_page.dart'; // Import de la nouvelle page d'aide

class HomeScreen extends StatefulWidget {
  final SentryBluetoothService btService;
  const HomeScreen({super.key, required this.btService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String appVersion = "1.4.0";

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Empêche la mise en veille
    widget.btService.startScan();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
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
          child: Text(
            appVersion,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
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
      body: StreamBuilder<double>(
        stream: widget.btService.mvStream,
        builder: (context, snapshot) {
          double mv = snapshot.hasData ? snapshot.data! : 0.0;
          double fo2 = O2MathEngine.calculateFO2(mv, widget.btService.calMv);
          double mod = O2MathEngine.calculateMOD(
            fo2,
            widget.btService.ppo2Limit,
          );

          // Alarme tension sonde (basée sur les réglages standards)
          bool mvAlarm = (mv < 7.0 || mv > 14.0) && snapshot.hasData;

          return Column(
            children: [
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
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 60),
                      // BLOC MOD
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 40,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
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
      ),
    );
  }
}
