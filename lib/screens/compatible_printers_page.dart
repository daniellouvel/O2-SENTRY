import 'package:flutter/material.dart';

class _PrinterInfo {
  final String name;
  final String brand;
  final String labelWidth;
  final String notes;
  final bool recommended;

  const _PrinterInfo({
    required this.name,
    required this.brand,
    required this.labelWidth,
    this.notes = "",
    this.recommended = false,
  });
}

const List<_PrinterInfo> _compatiblePrinters = [
  // --- NIIMBOT (imprimantes d'etiquettes BLE) ---
  _PrinterInfo(
    name: "Niimbot B1",
    brand: "Niimbot",
    labelWidth: "20-50 mm",
    notes: "Etiquettes autocollantes, rouleaux waterproof disponibles",
    recommended: true,
  ),
  _PrinterInfo(
    name: "Niimbot B21",
    brand: "Niimbot",
    labelWidth: "20-50 mm",
    notes: "Compact, ideal terrain. Etiquettes synthetiques PP waterproof",
    recommended: true,
  ),
  _PrinterInfo(
    name: "Niimbot B3S",
    brand: "Niimbot",
    labelWidth: "20-75 mm",
    notes: "Format large, haute resolution 300 dpi",
  ),
  _PrinterInfo(
    name: "Niimbot D11 / D110",
    brand: "Niimbot",
    labelWidth: "12-15 mm",
    notes: "Ultra-compact, format etiquettes etroites",
  ),

  // --- Phomemo (etiqueteuses BLE) ---
  _PrinterInfo(
    name: "Phomemo M110",
    brand: "Phomemo",
    labelWidth: "20-50 mm",
    notes: "Etiqueteuse portable, rouleaux adhesifs waterproof compatibles",
    recommended: true,
  ),
  _PrinterInfo(
    name: "Phomemo M120",
    brand: "Phomemo",
    labelWidth: "25-50 mm",
    notes: "Etiquettes autocollantes, format compact",
  ),
  _PrinterInfo(
    name: "Phomemo M220",
    brand: "Phomemo",
    labelWidth: "25-80 mm",
    notes: "Grand format, peut imprimer des etiquettes larges",
  ),

  // --- HPRT (etiqueteuses portables) ---
  _PrinterInfo(
    name: "HPRT HM-A300",
    brand: "HPRT",
    labelWidth: "25-80 mm",
    notes: "Mode etiquette + recu. Supporte rouleaux adhesifs waterproof",
    recommended: true,
  ),
  _PrinterInfo(
    name: "HPRT T20",
    brand: "HPRT",
    labelWidth: "20-50 mm",
    notes: "Etiqueteuse portable, capteur de gap integre",
  ),

  // --- MUNBYN ---
  _PrinterInfo(
    name: "MUNBYN ITPP941",
    brand: "MUNBYN",
    labelWidth: "25-58 mm",
    notes: "Portable BLE, mode etiquette adhesive, ESC/POS",
  ),
  _PrinterInfo(
    name: "MUNBYN M832",
    brand: "MUNBYN",
    labelWidth: "20-50 mm",
    notes: "Etiqueteuse thermique Bluetooth",
  ),

  // --- BIXOLON (pro) ---
  _PrinterInfo(
    name: "BIXOLON SPP-L3000",
    brand: "BIXOLON",
    labelWidth: "25-80 mm",
    notes: "Pro, certifie IP54, etiquettes adhesives, ideal milieu humide",
    recommended: true,
  ),

  // --- Rongta ---
  _PrinterInfo(
    name: "Rongta RPP320",
    brand: "Rongta",
    labelWidth: "25-80 mm",
    notes: "Mode etiquette + recu, supporte rouleaux adhesifs",
  ),
];

class CompatiblePrintersPage extends StatelessWidget {
  const CompatiblePrintersPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Grouper par marque
    final Map<String, List<_PrinterInfo>> grouped = {};
    for (var p in _compatiblePrinters) {
      grouped.putIfAbsent(p.brand, () => []).add(p);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text("IMPRIMANTES COMPATIBLES"),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info box
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "O2-Sentry necessite une imprimante d'etiquettes Bluetooth BLE "
                      "compatible avec des rouleaux autocollants waterproof (synthetiques PP/PET). "
                      "Ces etiquettes resistent a l'eau et peuvent etre collees sur les bouteilles de plongee.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Liste par marque
            ...grouped.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 10),
                    child: Text(
                      entry.key.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.blueAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ...entry.value.map((printer) => _buildPrinterCard(printer)),
                ],
              );
            }),

            const SizedBox(height: 30),

            // Section consommables waterproof
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.water_drop, color: Colors.cyan, size: 18),
                      SizedBox(width: 8),
                      Text(
                        "ETIQUETTES WATERPROOF",
                        style: TextStyle(
                          color: Colors.cyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Pour une tenue en milieu humide/marin, utilisez des rouleaux d'etiquettes autocollantes "
                    "en materiau synthetique :\n\n"
                    "• PP (Polypropylene) : Resistant a l'eau, huile, dechirure\n"
                    "• PET (Polyester) : Tres resistant, tenue longue duree\n"
                    "• Vinyle : Souple, ideal surfaces courbes (bouteilles)\n\n"
                    "Recherchez \"etiquettes thermiques waterproof\" ou \"synthetic thermal labels\" "
                    "dans le format compatible avec votre imprimante.",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Criteres de compatibilite
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "CRITERES DE COMPATIBILITE",
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "• Connexion Bluetooth Low Energy (BLE)\n"
                    "• Protocole ESC/POS\n"
                    "• Support rouleaux etiquettes autocollantes\n"
                    "• Etiquettes synthetiques (PP/PET) pour waterproof\n"
                    "• Largeur etiquette 50-80 mm recommandee",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterCard(_PrinterInfo printer) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: printer.recommended
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.print, color: Colors.cyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  printer.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (printer.recommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    "RECOMMANDE",
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  printer.labelWidth,
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (printer.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              printer.notes,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
