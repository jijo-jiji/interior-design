import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/utils/design_pictures.dart';
import 'package:static_trace/features/viewer/utils/proposal_delivery.dart';

// A real 1x1 PNG, so decoding it is a real decode.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  group('reading a picture', () {
    test('gives the bytes of an image data URL', () {
      final bytes = DesignPictures.decode('data:image/png;base64,$_png');
      expect(bytes, base64Decode(_png));
      expect(DesignPictures.decode('data:image/jpeg;base64,$_png'), isNotNull);
    });

    test('gives nothing for anything else', () {
      expect(DesignPictures.decode(''), isNull);
      expect(DesignPictures.decode('not a data url'), isNull);
      expect(DesignPictures.decode('data:text/html;base64,$_png'), isNull);
      expect(DesignPictures.decode('data:image/png;base64,@@@'), isNull);
      expect(DesignPictures.decode('data:image/png;base64'), isNull);
    });
  });

  group('keeping pictures beside an unsent quote', () {
    test('small ones are kept; big ones are not', () {
      expect(DesignPictures.fitsOffline(const []), isTrue);
      expect(DesignPictures.fitsOffline([List.filled(700000, 'a').join()]),
          isTrue);
      expect(
          DesignPictures.fitsOffline([
            List.filled(800000, 'a').join(),
            List.filled(800000, 'a').join(),
          ]),
          isFalse);
    });
  });

  group('giving the office the pictures', () {
    late HttpServer server;
    late Map<String, dynamic>? received;
    var status = 200;

    setUp(() async {
      received = null;
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        received = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write('{}')
          ..close();
      });
    });
    tearDown(() => server.close(force: true));

    Uri url() => Uri.parse('http://127.0.0.1:${server.port}/pictures');

    test('posts them and returns the page the client opens', () async {
      final page = await DesignPictures.upload(
        'QT-ABC',
        ['data:image/jpeg;base64,$_png', 'data:image/jpeg;base64,$_png'],
        endpoint: url(),
      );
      expect(page, endsWith('/pictures/QT-ABC'));
      expect((received!['images'] as List), hasLength(2));
    });

    test('says so (null) when the office refuses them', () async {
      status = 422;
      expect(
        await DesignPictures.upload('QT-ABC', ['x'], endpoint: url()),
        isNull,
      );
    });

    test('says so (null) when the office cannot be reached', () async {
      final gone = url();
      await server.close(force: true);
      expect(
        await DesignPictures.upload('QT-ABC', ['x'], endpoint: gone),
        isNull,
      );
    });
  });

  group('the message to the client', () {
    String message({String? picturesUrl, bool offline = false}) =>
        ProposalDelivery.buildMessage(
          clientName: 'Aminah',
          quoteId: 'QT-ABC',
          total: '5,724',
          styleName: 'Japandi Natural',
          depositLocked: false,
          isOfflineQueued: offline,
          picturesUrl: picturesUrl,
        );

    test('links the pictures when the office has them', () {
      final text = message(picturesUrl: 'http://office/pictures/QT-ABC');
      expect(
          text, contains('See pictures of it: http://office/pictures/QT-ABC'));
      expect(text, contains('View it in 3D:'));
    });

    test('has no pictures line without them', () {
      expect(message(), isNot(contains('pictures')));
    });

    test('has no pictures link while the quote is still on the phone', () {
      // A link to a page the office does not have yet would 404.
      expect(
        message(picturesUrl: 'http://office/pictures/QT-ABC', offline: true),
        isNot(contains('pictures')),
      );
    });
  });
}
