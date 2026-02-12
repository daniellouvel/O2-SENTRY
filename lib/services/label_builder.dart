import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

class LabelBuilder {
  /// Genere les bytes ESC/POS pour une etiquette Nitrox 50x80mm
  static Future<List<int>> buildNitroxLabel({
    required double fo2,
    required double ppo2Limit,
    required double mod,
    required DateTime dateTime,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];

    // En-tete
    bytes += generator.text(
      '================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'O2-SENTRY NITROX',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      '================================',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(1);

    // FO2 en gros
    bytes += generator.text(
      'FO2:     ${fo2.toStringAsFixed(1)} %',
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    bytes += generator.emptyLines(1);

    // ppO2
    bytes += generator.text(
      'ppO2:    ${ppo2Limit.toStringAsFixed(2)} bar',
      styles: const PosStyles(bold: true),
    );

    // MOD en gros
    bytes += generator.text(
      'MOD:     ${mod.toStringAsFixed(0)} m',
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
      ),
    );
    bytes += generator.emptyLines(1);

    // Date et heure
    final dateStr = '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year}';
    final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
    bytes += generator.text(
      'Date: $dateStr  $timeStr',
      styles: const PosStyles(align: PosAlign.center),
    );

    // Pied
    bytes += generator.text(
      '================================',
      styles: const PosStyles(align: PosAlign.center),
    );

    // Avance papier + coupe
    bytes += generator.feed(3);
    bytes += generator.cut();

    return bytes;
  }
}
