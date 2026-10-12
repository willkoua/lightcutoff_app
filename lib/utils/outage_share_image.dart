import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/enums.dart';
import '../models/official_outage.dart';

/// Génère une **vignette de partage** (PNG) pour une coupure programmée :
/// en-tête coloré par service, quartier, opérateur, zone, date/créneau, pied
/// NJUKA. Dessinée sur un Canvas (aucun widget monté), écrite dans un fichier
/// temporaire. Renvoie le chemin, ou `null` si la génération échoue (le partage
/// retombe alors sur le texte seul).
Future<String?> buildOutageShareImageFile({
  required OfficialOutage outage,
  required String title,
  required String operator,
  required String placeLabel,
  required String whenLabel,
  required String tagline,
  required Color serviceColor,
}) async {
  try {
    const w = 1080.0;
    const h = 566.0;
    const left = 64.0;
    const maxTextW = w - left - 48;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

    // Fond blanc + barre d'accent service à gauche.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 18, h),
      Paint()..color = serviceColor,
    );

    void draw(
      String text,
      double y,
      double size,
      Color color, {
      FontWeight weight = FontWeight.w400,
      int maxLines = 1,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: weight,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: maxTextW);
      tp.paint(canvas, Offset(left, y));
    }

    final emoji = outage.serviceType == ServiceType.water ? '💧' : '⚡';

    draw('$emoji $title · $operator', 56, 40, serviceColor,
        weight: FontWeight.w700, maxLines: 2);
    draw(outage.quartier, 190, 66, const Color(0xFF1A1A1A),
        weight: FontWeight.w800, maxLines: 2);
    if (placeLabel.isNotEmpty) {
      draw(placeLabel, 330, 32, const Color(0xFF6B7280));
    }
    draw(whenLabel, 400, 40, const Color(0xFF1A1A1A), weight: FontWeight.w600);

    // Pied NJUKA.
    draw('NJUKA', h - 88, 44, serviceColor, weight: FontWeight.w800);
    draw(tagline, h - 40, 28, const Color(0xFF6B7280));

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bytes == null) return null;

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/njuka_outage_${outage.id.hashCode}.png',
    );
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
