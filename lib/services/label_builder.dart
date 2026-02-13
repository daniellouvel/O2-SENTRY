import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

class LabelBuilder {
  /// Genere une image PNG de l'etiquette Nitrox pour partage
  static Future<Uint8List> buildNitroxLabelImage({
    required double fo2,
    required double ppo2Limit,
    required double mod,
    required DateTime dateTime,
  }) async {
    const double width = 600;
    const double height = 400;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Fond blanc
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );

    // Bordure
    canvas.drawRect(
      const Rect.fromLTWH(4, 4, width - 8, height - 8),
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Barre titre
    canvas.drawRect(
      const Rect.fromLTWH(4, 4, width - 8, 60),
      Paint()..color = const Color(0xFF1A1A2E),
    );

    double y = 18;

    // Titre
    _drawText(canvas, 'O2-SENTRY NITROX', width / 2, y,
        fontSize: 28, bold: true, color: Colors.white, center: true);

    y = 85;

    // FO2
    _drawText(canvas, 'FO2', 30, y, fontSize: 18, color: Colors.grey);
    _drawText(canvas, '${fo2.toStringAsFixed(1)} %', width - 30, y,
        fontSize: 42, bold: true, color: Colors.black, alignRight: true);

    y += 65;

    // Ligne separatrice
    canvas.drawLine(
      Offset(30, y),
      Offset(width - 30, y),
      Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 1,
    );

    y += 20;

    // ppO2
    _drawText(canvas, 'ppO2', 30, y, fontSize: 18, color: Colors.grey);
    _drawText(canvas, '${ppo2Limit.toStringAsFixed(2)} bar', width - 30, y,
        fontSize: 28, bold: true, color: Colors.black, alignRight: true);

    y += 50;

    // Ligne separatrice
    canvas.drawLine(
      Offset(30, y),
      Offset(width - 30, y),
      Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 1,
    );

    y += 20;

    // MOD
    _drawText(canvas, 'MOD', 30, y, fontSize: 18, color: Colors.grey);
    _drawText(canvas, '${mod.toStringAsFixed(0)} m', width - 30, y,
        fontSize: 42, bold: true, color: const Color(0xFFE65100), alignRight: true);

    y += 65;

    // Ligne separatrice
    canvas.drawLine(
      Offset(30, y),
      Offset(width - 30, y),
      Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 1,
    );

    y += 15;

    // Date
    final dateStr = '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year}  '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
    _drawText(canvas, dateStr, width / 2, y,
        fontSize: 16, color: Colors.grey.shade600, center: true);

    // Convertir en image PNG
    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y, {
    double fontSize = 14,
    bool bold = false,
    Color color = Colors.black,
    bool center = false,
    bool alignRight = false,
  }) {
    final textStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    double dx = x;
    if (center) {
      dx = x - textPainter.width / 2;
    } else if (alignRight) {
      dx = x - textPainter.width;
    }
    textPainter.paint(canvas, Offset(dx, y));
  }

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
