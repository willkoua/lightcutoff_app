import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lightcutoff_app/utils/media.dart';

Uint8List _jpg(int w, int h) =>
    img.encodeJpg(img.Image(width: w, height: h), quality: 90);

Uint8List _png(int w, int h) => img.encodePng(img.Image(width: w, height: h));

void main() {
  group('prepareMedia — détection de type', () {
    test('format non supporté rejeté', () async {
      final r = await prepareMedia(
        Uint8List.fromList([1, 2, 3]),
        filename: 'note.txt',
      );
      expect(r.media, isNull);
      expect(r.error, MediaError.unsupportedType);
    });

    test('GIF transmis tel quel', () async {
      final bytes = Uint8List.fromList(List.filled(1024, 7));
      final r = await prepareMedia(bytes, filename: 'anim.gif');
      expect(r.error, isNull);
      expect(r.media!.contentType, 'image/gif');
      expect(r.media!.bytes, same(bytes));
    });

    test('GIF trop volumineux rejeté', () async {
      final bytes = Uint8List(kMaxMediaBytes + 1);
      final r = await prepareMedia(bytes, filename: 'huge.gif');
      expect(r.media, isNull);
      expect(r.error, MediaError.tooLarge);
    });

    test('type déduit du mimeType si extension absente', () async {
      final r = await prepareMedia(
        _png(50, 50),
        filename: 'capture',
        mimeType: 'image/png',
      );
      expect(r.error, isNull);
      expect(r.media!.contentType, 'image/png');
    });
  });

  group('resizeStaticImage', () {
    test('image dans la limite : octets inchangés', () {
      final bytes = _png(100, 100);
      expect(resizeStaticImage(bytes, png: true), same(bytes));
    });

    test('paysage redimensionné sur la largeur', () {
      final out = resizeStaticImage(_jpg(2000, 1000), png: false)!;
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, kMaxMediaDimension);
      expect(decoded.height, 640);
    });

    test('portrait redimensionné sur la hauteur', () {
      final out = resizeStaticImage(_jpg(1000, 2000), png: false)!;
      final decoded = img.decodeImage(out)!;
      expect(decoded.height, kMaxMediaDimension);
      expect(decoded.width, 640);
    });

    test('octets invalides : null', () {
      expect(resizeStaticImage(Uint8List.fromList([0, 1, 2]), png: false),
          isNull);
    });
  });
}
