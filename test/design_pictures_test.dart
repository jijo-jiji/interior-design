import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/utils/design_pictures.dart';
import 'package:static_trace/features/viewer/utils/proposal_delivery.dart';

// A real 1x1 PNG, so decoding it is a real decode.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  group('asking the page for a render', () {
    test('the sky-averaged render takes the frames it is given', () {
      const request = RenderRequest(RenderEngine.sky);
      expect(request.javaScript(skySamples: 40),
          "renderPictures('render', {samples: 40})");
    });

    test('true lighting asks for the path tracer, with a time limit', () {
      const request = RenderRequest(RenderEngine.path);
      final call = request.javaScript(skySamples: 40);
      expect(call, contains("engine: 'path'"));
      expect(call, contains('samples: 300'));
      expect(call, contains('seconds: 120'));
      // A call the page can read: balanced, one object.
      expect(call, startsWith("renderPictures('render', {"));
      expect(call, endsWith('})'));
    });

    test('fine detail asks for more samples and more time', () {
      const fine = RenderRequest(RenderEngine.path, RenderQuality.fine);
      const standard = RenderRequest(RenderEngine.path);
      expect(fine.javaScript(skySamples: 40), contains('samples: 1000'));
      expect(fine.timeout, greaterThan(standard.timeout));
      expect(standard.timeout, greaterThan(
          const RenderRequest(RenderEngine.sky).timeout));
    });

    test('the app waits longer than the page will (both pictures)', () {
      // The page stops each picture at its seconds (plus building the
      // shader and tone mapping): two pictures must fit in the wait.
      expect(const RenderRequest(RenderEngine.path).timeout.inSeconds,
          greaterThan(2 * 120 + 60));
      expect(
          const RenderRequest(RenderEngine.path, RenderQuality.fine)
              .timeout
              .inSeconds,
          greaterThan(2 * 300 + 60));
    });
  });

  group('what a true-lighting render reached', () {
    test('is read from what the page sends', () {
      final stats = RenderStats.fromJson({
        'samples': [143, 151.0],
        'seconds': [98.2, 101],
        'gpu': ' Adreno (TM) 650 ',
      })!;
      expect(stats.samples, [143, 151]);
      expect(stats.seconds, [98.2, 101.0]);
      expect(stats.gpu, 'Adreno (TM) 650');
    });

    test('says it in words, with the chip when known', () {
      expect(
        const RenderStats(samples: [143, 151], seconds: [98, 101.5], gpu: 'X')
            .summary,
        'Light paths traced: 143 and 151 samples, in 98 and 101.5 s.\n'
        'Graphics: X',
      );
      expect(const RenderStats(samples: [64]).summary,
          'Light paths traced: 64 samples.');
    });

    test('is nothing when the page sent nothing usable', () {
      expect(RenderStats.fromJson(null), isNull);
      expect(RenderStats.fromJson('x'), isNull);
      expect(RenderStats.fromJson({'samples': []}), isNull);
      expect(RenderStats.fromJson({'samples': ['a']}), isNull);
    });
  });

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
