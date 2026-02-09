import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

class SensorInfo {
  final String name;
  final String manufacturer;
  final double mvMin;
  final double mvMax;
  final int lifespanMonths;
  final String connector;

  const SensorInfo({
    required this.name,
    required this.manufacturer,
    required this.mvMin,
    required this.mvMax,
    required this.lifespanMonths,
    required this.connector,
  });
}

const List<SensorInfo> sensorLibrary = [
  SensorInfo(
    name: "Teledyne R-17MED",
    manufacturer: "Teledyne / AII",
    mvMin: 7.0, mvMax: 13.0,
    lifespanMonths: 24,
    connector: "Molex 3-pin",
  ),
  SensorInfo(
    name: "Teledyne R-22MED",
    manufacturer: "Teledyne / AII",
    mvMin: 8.0, mvMax: 13.0,
    lifespanMonths: 36,
    connector: "Molex 3-pin",
  ),
  SensorInfo(
    name: "AII PSR-11-39-MDSX1",
    manufacturer: "Analytical Industries",
    mvMin: 9.0, mvMax: 13.0,
    lifespanMonths: 24,
    connector: "Molex 3-pin",
  ),
  SensorInfo(
    name: "Maxtec MAX-12",
    manufacturer: "Maxtec",
    mvMin: 9.0, mvMax: 13.0,
    lifespanMonths: 24,
    connector: "Molex 3-pin",
  ),
  SensorInfo(
    name: "Vandagraph VN202",
    manufacturer: "Vandagraph",
    mvMin: 7.0, mvMax: 13.0,
    lifespanMonths: 18,
    connector: "Molex 3-pin",
  ),
  SensorInfo(
    name: "AII SF-01",
    manufacturer: "Analytical Industries",
    mvMin: 7.0, mvMax: 13.0,
    lifespanMonths: 12,
    connector: "Molex 3-pin",
  ),
];

class ConfigPage extends StatefulWidget {
  final SentryBluetoothService btService;
  const ConfigPage({super.key, required this.btService});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const String _customKey = "Custom (Manuel)";

  late String selectedSensor;
  StreamSubscription? _sub;
  late TextEditingController _customMinCtrl;
  late TextEditingController _customMaxCtrl;

  /// Noms pour le dropdown (sondes + Custom)
  List<String> get _sensorNames =>
      [...sensorLibrary.map((s) => s.name), _customKey];

  /// Retourne le SensorInfo ou null si Custom
  SensorInfo? _getSelectedInfo() {
    try {
      return sensorLibrary.firstWhere((s) => s.name == selectedSensor);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final saved = widget.btService.sensorModel;
    selectedSensor = _sensorNames.contains(saved) ? saved : _sensorNames.first;
    _customMinCtrl = TextEditingController(
      text: widget.btService.sensorMvMin.toStringAsFixed(1),
    );
    _customMaxCtrl = TextEditingController(
      text: widget.btService.sensorMvMax.toStringAsFixed(1),
    );
    _sub = widget.btService.mvStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _customMinCtrl.dispose();
    _customMaxCtrl.dispose();
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

  Widget _buildSensorInfoCard(SensorInfo info) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow("Fabricant", info.manufacturer),
          const SizedBox(height: 6),
          _infoRow("Plage mV", "${info.mvMin} – ${info.mvMax} mV"),
          const SizedBox(height: 6),
          _infoRow("Durée de vie", "${info.lifespanMonths} mois"),
          const SizedBox(height: 6),
          _infoRow("Connecteur", info.connector),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomFields() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Plages mV personnalisées",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customMinCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "mV Min",
                    labelStyle: TextStyle(color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: TextField(
                  controller: _customMaxCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "mV Max",
                    labelStyle: TextStyle(color: Colors.white38),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blueAccent),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final minVal = double.tryParse(_customMinCtrl.text);
                final maxVal = double.tryParse(_customMaxCtrl.text);

                if (minVal == null || maxVal == null) {
                  _showError("Erreur", "Valeurs invalides.");
                  return;
                }
                if (minVal < 1.0 || maxVal > 25.0) {
                  _showError(
                    "Erreur",
                    "Plage autorisée : min >= 1.0, max <= 25.0 mV.",
                  );
                  return;
                }
                if (minVal >= maxVal) {
                  _showError("Erreur", "Le min doit être inférieur au max.");
                  return;
                }

                widget.btService.saveSensorModel(_customKey, minVal, maxVal);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Plage custom appliquée : $minVal – $maxVal mV",
                    ),
                  ),
                );
              },
              child: const Text("APPLIQUER"),
            ),
          ),
        ],
      ),
    );
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
              items: _sensorNames
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) async {
                if (v == null || v == selectedSensor) return;
                final info = sensorLibrary
                    .where((s) => s.name == v)
                    .firstOrNull;
                final plage = info != null
                    ? "${info.mvMin} – ${info.mvMax} mV"
                    : "personnalisée";
                final ok = await _confirm(
                  "Changer de sonde",
                  "Passer à « $v » ?\n"
                      "Plage alarme : $plage\n\n"
                      "Les seuils d'alarme seront mis à jour.",
                );
                if (!ok) return;
                setState(() => selectedSensor = v);
                if (info != null) {
                  widget.btService.saveSensorModel(
                    v, info.mvMin, info.mvMax,
                  );
                }
              },
            ),

            // FICHE INFO SONDE ou CHAMPS CUSTOM
            if (selectedSensor != _customKey && _getSelectedInfo() != null)
              _buildSensorInfoCard(_getSelectedInfo()!),
            if (selectedSensor == _customKey) _buildCustomFields(),
            const SizedBox(height: 10),

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

                  // Vérification 1 : plage mV valide selon le modèle de sonde
                  final mvMin = widget.btService.sensorMvMin;
                  final mvMax = widget.btService.sensorMvMax;
                  if (currentMv < mvMin || currentMv > mvMax) {
                    _showError(
                      "Calibration impossible",
                      "Tension hors plage (${currentMv.toStringAsFixed(2)} mV).\n"
                          "Plage attendue pour ${widget.btService.sensorModel} : "
                          "$mvMin – $mvMax mV.",
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
                        "Sonde associée :",
                        style: TextStyle(color: Colors.white70),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.btService.isPaired)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.lock,
                                color: Colors.greenAccent,
                                size: 14,
                              ),
                            ),
                          Text(
                            widget.btService.associatedProbeName ?? "Aucune",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.btService.associatedProbeMac != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "MAC :",
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            widget.btService.associatedProbeMac!,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  StreamBuilder<int>(
                    stream: widget.btService.batteryStream,
                    builder: (context, batSnapshot) {
                      final bat = batSnapshot.data ??
                          widget.btService.batteryLevel;
                      if (bat == null) return const SizedBox.shrink();
                      IconData batIcon;
                      Color batColor;
                      if (bat > 60) {
                        batIcon = Icons.battery_full;
                        batColor = Colors.greenAccent;
                      } else if (bat > 20) {
                        batIcon = Icons.battery_3_bar;
                        batColor = Colors.orangeAccent;
                      } else {
                        batIcon = Icons.battery_alert;
                        batColor = Colors.redAccent;
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Batterie :",
                            style: TextStyle(color: Colors.white70),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(batIcon, color: batColor, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                "$bat%",
                                style: TextStyle(
                                  color: batColor,
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
