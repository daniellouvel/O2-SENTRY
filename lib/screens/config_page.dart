import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

class ConfigPage extends StatefulWidget {
  final SentryBluetoothService btService;
  const ConfigPage({super.key, required this.btService});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final Map<String, List<double>> sensorSpecs = {
    "PSR-11-39-MDSX1 (Standard)": [9.0, 13.0],
    "AII SF-01 (Analytical Industries)": [7.0, 13.0],
    "Maxtec MAX-12": [9.0, 13.0],
    "Custom (Manuel)": [0.0, 0.0],
  };

  late String selectedSensor;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    // Charger le modèle sauvegardé, ou le premier par défaut
    final saved = widget.btService.sensorModel;
    selectedSensor = sensorSpecs.containsKey(saved)
        ? saved
        : sensorSpecs.keys.first;
    _sub = widget.btService.mvStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: widget.btService.installationDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (picked != null) {
      await widget.btService.saveInstallDate(picked);
      setState(() {});
    }
  }

  void _showError(String title, String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title, style: const TextStyle(color: Colors.redAccent)),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  /// Calcule l'écart-type d'une liste de valeurs
  double _stdDev(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance);
  }

  Future<bool> _confirm(String title, String msg) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(msg, style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("NON"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("OUI"),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    bool isExpired = false;
    if (widget.btService.installationDate != null) {
      // Alarme si plus de 12 mois (365 jours)
      isExpired =
          DateTime.now().difference(widget.btService.installationDate!).inDays >
          365;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Configuration"),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TENSION
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Tension Sonde",
                    style: TextStyle(color: Colors.white70),
                  ),
                  Text(
                    "${widget.btService.currentMv.toStringAsFixed(2)} mV",
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // 2. CHOIX DU TYPE DE SONDE
            const Text(
              "MODÈLE DE SONDE",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            DropdownButton<String>(
              value: selectedSensor,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              items: sensorSpecs.keys
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) {
                setState(() => selectedSensor = v!);
                final specs = sensorSpecs[v]!;
                // "Custom (Manuel)" a [0.0, 0.0] : garder les plages précédentes
                if (specs[0] > 0 && specs[1] > 0) {
                  widget.btService.saveSensorModel(v!, specs[0], specs[1]);
                } else {
                  // Sauvegarder seulement le nom, pas les plages
                  widget.btService.saveSensorModel(
                    v!,
                    widget.btService.sensorMvMin,
                    widget.btService.sensorMvMax,
                  );
                }
              },
            ),

            // 3. DATE D'INSTALLATION (Sous la sonde)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "Date d'installation",
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: Text(
                widget.btService.installationDate == null
                    ? "Non définie"
                    : "${widget.btService.installationDate!.day}/${widget.btService.installationDate!.month}/${widget.btService.installationDate!.year}",
                style: TextStyle(
                  color: isExpired ? Colors.redAccent : Colors.grey,
                ),
              ),
              trailing: IconButton(
                icon: Icon(
                  Icons.calendar_today,
                  color: isExpired ? Colors.redAccent : Colors.blueAccent,
                ),
                onPressed: () => _selectDate(context),
              ),
            ),
            if (isExpired)
              const Text(
                "⚠️ SONDE PÉRIMÉE (PLUS DE 12 MOIS)",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),

            const SizedBox(height: 30),

            // 4. RÉGLAGE PPO2
            const Text(
              "SÉCURITÉ",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                "Limite ppO2",
                style: TextStyle(color: Colors.white),
              ),
              trailing: DropdownButton<double>(
                value: widget.btService.ppo2Limit,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white, fontSize: 18),
                items: [1.3, 1.4, 1.5, 1.6]
                    .map(
                      (p) =>
                          DropdownMenuItem(value: p, child: Text(p.toString())),
                    )
                    .toList(),
                onChanged: (v) async {
                  await widget.btService.savePPO2(v!);
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 30),

            // 5. CALIBRAGE
            const Text(
              "MAINTENANCE",
              style: TextStyle(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.tune),
                label: const Text("CALIBRER À L'AIR (20.9%)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final currentMv = widget.btService.currentMv;

                  // Vérification 1 : plage mV valide (2.3)
                  if (currentMv < 5.0 || currentMv > 16.0) {
                    _showError(
                      "Calibration impossible",
                      "Tension hors plage (${currentMv.toStringAsFixed(2)} mV).\n"
                          "La tension doit être entre 5.0 et 16.0 mV.",
                    );
                    return;
                  }

                  // Vérification 2 : stabilité du signal (2.4)
                  final buffer = widget.btService.recentMv;
                  if (buffer.length < 10) {
                    _showError(
                      "Calibration impossible",
                      "Attendre plus de mesures...\n"
                          "(${buffer.length}/10 reçues)",
                    );
                    return;
                  }
                  if (_stdDev(buffer) > 0.15) {
                    _showError(
                      "Calibration impossible",
                      "Signal non stabilisé...\n"
                          "Écart-type : ${_stdDev(buffer).toStringAsFixed(3)} mV "
                          "(max 0.150 mV).",
                    );
                    return;
                  }

                  // Confirmation et calibration
                  bool ok = await _confirm(
                    "Calibration",
                    "Valider la calibration sur ${currentMv.toStringAsFixed(2)} mV ?",
                  );
                  if (ok) {
                    await widget.btService.saveCalibration(currentMv);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Capteur calibré !")),
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 40),

            // 6. CONNEXION
            const Text(
              "CONNEXION",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "ID MAC :",
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        widget.btService.associatedMac ?? "Aucun",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<SentryConnectionState>(
                    stream: widget.btService.connectionStateStream,
                    initialData: widget.btService.currentState,
                    builder: (context, snapshot) {
                      final state =
                          snapshot.data ?? SentryConnectionState.disconnected;
                      String label;
                      Color color;
                      switch (state) {
                        case SentryConnectionState.connected:
                          label = "Connecté";
                          color = Colors.greenAccent;
                          break;
                        case SentryConnectionState.scanning:
                          label = "Recherche...";
                          color = Colors.cyan;
                          break;
                        case SentryConnectionState.connecting:
                          label = "Connexion...";
                          color = Colors.orangeAccent;
                          break;
                        case SentryConnectionState.disconnected:
                          label = "Déconnecté";
                          color = Colors.redAccent;
                          break;
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Statut :",
                            style: TextStyle(color: Colors.white70),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: () async {
                        bool ok = await _confirm(
                          "Dissocier",
                          "Oublier ce capteur ?",
                        );
                        if (ok) {
                          await widget.btService.forgetDevice();
                          Navigator.pop(context);
                        }
                      },
                      child: const Text(
                        "DISSOCIER L'APPAREIL",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
