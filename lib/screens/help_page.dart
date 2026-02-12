import 'package:flutter/material.dart';
import 'compatible_printers_page.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text("AIDE & UTILISATION"),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              "1. CALIBRAGE",
              "Pour une mesure précise, sortez la sonde à l'air libre (20.9% O2). Attendez que la tension (mV) se stabilise, puis appuyez sur 'CALIBRER' dans les réglages. Confirmez pour enregistrer la référence.",
              Icons.tune,
            ),
            _buildSection(
              "2. LIMITE PPO2 & MOD",
              "La MOD (Maximum Operating Depth) est calculée selon votre limite de ppO2 choisie (ex: 1.4). Elle indique la profondeur maximale à ne pas dépasser pour éviter l'hyperoxie.",
              Icons.shutter_speed,
            ),
            _buildSection(
              "3. ALARMES",
              "• ROUGE (Haut) : Tension sonde hors plage (sonde fatiguée ou défectueuse).\n• ORANGE (MOD) : Attention, vous approchez de la limite de toxicité de l'oxygène.",
              Icons.warning_amber_rounded,
            ),
            _buildSection(
              "4. MAINTENANCE",
              "Une sonde galvanique a une durée de vie limitée (environ 12-18 mois). Surveillez la date d'installation dans l'onglet configuration. Si la tension à l'air tombe en dessous de 8-9 mV, prévoyez son remplacement.",
              Icons.build_circle_outlined,
            ),
            _buildSection(
              "5. IMPRESSION ETIQUETTE",
              "Appuyez sur l'icône imprimante dans la barre du haut pour imprimer une étiquette autocollante waterproof avec :\n"
              "• FO2 (pourcentage d'oxygène)\n"
              "• ppO2 (limite de pression partielle)\n"
              "• MOD (profondeur maximale)\n"
              "• Date et heure de l'analyse\n\n"
              "L'étiquette se colle directement sur la bouteille.\n\n"
              "Avant la première impression, associez votre imprimante d'étiquettes Bluetooth dans Configuration > Imprimante. "
              "Utilisez des rouleaux d'étiquettes synthétiques (PP ou PET) pour une tenue waterproof en milieu marin.",
              Icons.print_outlined,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 25),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: const Text("VOIR LES IMPRIMANTES COMPATIBLES"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blueAccent,
                    side: const BorderSide(color: Colors.blueAccent),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CompatiblePrintersPage(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Center(
              child: Text(
                "O2-SENTRY - Sécurité Plongée\nConçu pour les plongeurs exigeants.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4, // Correction ici : 'height' au lieu de 'lineHeight'
            ),
          ),
        ],
      ),
    );
  }
}
