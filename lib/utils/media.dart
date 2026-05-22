import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/app_constants.dart';

enum _MediaKind { gif, png, jpeg }

/// Raison d'un rejet de média, à mapper sur un message utilisateur.
enum MediaError { unsupportedType, tooLarge, invalidImage }

/// Média prêt pour l'upload (octets éventuellement redimensionnés + type MIME).
class PreparedMedia {
  const PreparedMedia(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

/// Résultat de la préparation : soit un média prêt, soit une erreur.
class MediaOutcome {
  const MediaOutcome.success(PreparedMedia this.media) : error = null;
  const MediaOutcome.failure(MediaError this.error) : media = null;
  final PreparedMedia? media;
  final MediaError? error;
}

_MediaKind? _detectKind(String filename, String? mimeType) {
  final name = filename.toLowerCase();
  if (name.endsWith('.gif') || mimeType == 'image/gif') return _MediaKind.gif;
  if (name.endsWith('.png') || mimeType == 'image/png') return _MediaKind.png;
  if (name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      mimeType == 'image/jpeg' ||
      mimeType == 'image/jpg') {
    return _MediaKind.jpeg;
  }
  return null;
}

/// Valide le type, redimensionne les images fixes dépassant
/// [AppConstants.maxMediaDimension] et rejette tout média dépassant
/// [AppConstants.maxMediaBytes].
///
/// Les GIF sont transmis tels quels pour préserver l'animation (seule leur
/// taille est plafonnée).
Future<MediaOutcome> prepareMedia(
  Uint8List bytes, {
  required String filename,
  String? mimeType,
}) async {
  final kind = _detectKind(filename, mimeType);
  if (kind == null) return const MediaOutcome.failure(MediaError.unsupportedType);

  if (kind == _MediaKind.gif) {
    if (bytes.length > AppConstants.maxMediaBytes) {
      return const MediaOutcome.failure(MediaError.tooLarge);
    }
    return MediaOutcome.success(PreparedMedia(bytes, 'image/gif'));
  }

  final png = kind == _MediaKind.png;
  final processed = await compute(_resizeStatic, _ResizeRequest(bytes, png));
  if (processed == null) {
    return const MediaOutcome.failure(MediaError.invalidImage);
  }
  if (processed.length > AppConstants.maxMediaBytes) {
    return const MediaOutcome.failure(MediaError.tooLarge);
  }
  return MediaOutcome.success(
    PreparedMedia(processed, png ? 'image/png' : 'image/jpeg'),
  );
}

class _ResizeRequest {
  const _ResizeRequest(this.bytes, this.png);
  final Uint8List bytes;
  final bool png;
}

Uint8List? _resizeStatic(_ResizeRequest req) =>
    resizeStaticImage(req.bytes, png: req.png);

/// Décode une image fixe, la redimensionne si son côté le plus long dépasse
/// [AppConstants.maxMediaDimension] et la ré-encode. Renvoie les octets si elle
/// tient déjà dans la limite, ou `null` si le décodage échoue.
///
/// Synchrone et sans dépendance Flutter : exécutable dans un isolate.
@visibleForTesting
Uint8List? resizeStaticImage(Uint8List bytes, {required bool png}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final longest = math.max(decoded.width, decoded.height);
  if (longest <= AppConstants.maxMediaDimension) return bytes;
  final resized =
      decoded.width >= decoded.height
          ? img.copyResize(decoded, width: AppConstants.maxMediaDimension)
          : img.copyResize(decoded, height: AppConstants.maxMediaDimension);
  return png
      ? img.encodePng(resized)
      : img.encodeJpg(resized, quality: AppConstants.mediaJpegQuality);
}
