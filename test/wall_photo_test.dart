// The wall photo sent with a quote: a phone photo as it is, a huge one
// scaled down, nothing at all when the photo can't be read.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:static_trace/features/trace/utils/wall_photo.dart';

void main() {
  testWidgets('a phone-sized JPEG is sent as it is', (tester) async {
    const path = 'test/fixtures/walls/from-left-25.jpg';
    final url = await tester.runAsync(() => wallPhotoDataUrl(path));
    expect(url, startsWith('data:image/jpeg;base64,'));
    final sent = base64Decode(url!.split(',').last);
    expect(sent, File(path).readAsBytesSync());
  });

  testWidgets('a huge photo is scaled down to the size the office keeps',
      (tester) async {
    // Noise, so it can't compress below the as-is limit.
    final rnd = math.Random(1);
    final big = img.Image(width: 3000, height: 2000);
    for (final p in big) {
      p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
    final dir = Directory.systemTemp.createTempSync('wall-photo-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/big.png')..writeAsBytesSync(img.encodePng(big));
    expect(file.lengthSync(), greaterThan(kSendPhotoAsIsBytes));

    final url = await tester.runAsync(() => wallPhotoDataUrl(file.path));
    expect(url, startsWith('data:image/jpeg;base64,'));
    final sent = img.decodeJpg(base64Decode(url!.split(',').last))!;
    expect(math.max(sent.width, sent.height), kSentPhotoLongSide);
    expect(sent.width / sent.height, closeTo(1.5, 0.01));
  });

  testWidgets('a photo that is gone sends nothing', (tester) async {
    final url = await tester.runAsync(
        () => wallPhotoDataUrl('test/fixtures/walls/not-there.jpg'));
    expect(url, isNull);
  });
}
