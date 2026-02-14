import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class LabelBuilder {
  /// Genere une image PNG de l'etiquette Nitrox.
  /// [widthPx] et [heightPx] definissent la taille en pixels (defaut 400x240 = 50x30mm a 203 DPI).
  static Future<Uint8List> buildNitroxLabelImage({
    required double fo2,
    required double ppo2Limit,
    required double mod,
    required DateTime dateTime,
    int widthPx = 400,
    int heightPx = 240,
  }) async {
    final double width = widthPx.toDouble();
    final double height = heightPx.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Fond blanc
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.white,
    );

    // Bordure noire
    canvas.drawRect(
      Rect.fromLTWH(1, 1, width - 2, height - 2),
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final cx = width / 2;
    final linePaint = Paint()..color = Colors.grey.shade400..strokeWidth = 1;

    // --- Textes a placer : on mesure puis on repartit ---
    final dateStr = '${dateTime.day.toString().padLeft(2, '0')}/'
        '${dateTime.month.toString().padLeft(2, '0')}/'
        '${dateTime.year}  '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';

    // Tailles de police proportionnelles a la hauteur
    final dateFontSize = height * 0.07;     // ~17px sur 240
    final fo2FontSize = height * 0.22;      // ~53px sur 240
    final ppo2FontSize = height * 0.09;     // ~22px sur 240
    final modFontSize = height * 0.30;      // ~72px sur 240

    // Mesurer chaque texte
    final dateSize = _measureText(dateStr, dateFontSize, false);
    final fo2Size = _measureText('FO2 ${fo2.toStringAsFixed(1)}%', fo2FontSize, true);
    final ppo2Size = _measureText('ppO2 ${ppo2Limit.toStringAsFixed(2)} bar', ppo2FontSize, true);
    final modSize = _measureText('MOD ${mod.toStringAsFixed(0)}m', modFontSize, true);

    // Hauteur totale des textes + 3 lignes separatrices (1px chacune) + padding minimal
    final pad = height * 0.02; // petit padding entre ligne et texte
    final totalContent = dateSize.height + fo2Size.height + ppo2Size.height + modSize.height + pad * 8 + 3;

    // Distribuer l'espace restant uniformement
    final extra = (height - 4 - totalContent) / 4; // 4 zones, 4px bordure
    final gap = extra > 0 ? extra : 0.0;

    double y = 2 + gap / 2;

    // 1. Date (petit, centre)
    _drawText(canvas, dateStr, cx, y + (dateSize.height + pad * 2 - dateSize.height) / 2,
        fontSize: dateFontSize, color: Colors.grey.shade700, center: true);
    y += dateSize.height + pad * 2 + gap;

    // Ligne
    canvas.drawLine(Offset(3, y), Offset(width - 3, y), linePaint);
    y += 1;

    // 2. FO2 (gros, centre)
    _drawText(canvas, 'FO2 ${fo2.toStringAsFixed(1)}%', cx, y + pad + gap / 2,
        fontSize: fo2FontSize, bold: true, color: Colors.black, center: true);
    y += fo2Size.height + pad * 2 + gap;

    // Ligne
    canvas.drawLine(Offset(3, y), Offset(width - 3, y), linePaint);
    y += 1;

    // 3. ppO2 (moyen, centre)
    _drawText(canvas, 'ppO2 ${ppo2Limit.toStringAsFixed(2)} bar', cx, y + pad + gap / 2,
        fontSize: ppo2FontSize, bold: true, color: Colors.black, center: true);
    y += ppo2Size.height + pad * 2 + gap;

    // Ligne
    canvas.drawLine(Offset(3, y), Offset(width - 3, y), linePaint);
    y += 1;

    // 4. MOD (tres gros, centre) - prend tout le reste
    final modZone = height - 2 - y;
    _drawText(canvas, 'MOD ${mod.toStringAsFixed(0)}m', cx, y + (modZone - modSize.height) / 2,
        fontSize: modFontSize, bold: true, color: Colors.black, center: true);

    // Convertir en image PNG
    final picture = recorder.endRecording();
    final img = await picture.toImage(widthPx, heightPx);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Mesure la taille d'un texte sans le dessiner
  static Size _measureText(String text, double fontSize, bool bold) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return Size(tp.width, tp.height);
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

}
