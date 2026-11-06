import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/catalog/catalog_repository.dart';
import 'package:static_trace/features/catalog/default_catalog.g.dart';
import 'package:static_trace/features/catalog/price_catalog.dart';
import 'package:static_trace/features/layout/kitchen_catalog.dart';
import 'package:static_trace/features/layout/kitchen_layout_generator.dart';
import 'package:static_trace/features/layout/kitchen_layout_models.dart';
import 'package:static_trace/features/viewer/models/cpq_engine.dart';

Map<String, dynamic> _sample() =>
    jsonDecode(kDefaultCatalogJson) as Map<String, dynamic>;

/// What `GET /api/catalog` sends: the catalogue plus the flat maps older
/// clients read.
Map<String, dynamic> _served(void Function(Map<String, dynamic>) edit,
    {int version = 7}) {
  final doc = _sample()
    ..['version'] = version
    ..['cabinets'] = {'base_800': 999}
    ..['styles'] = {'japandi': 1.0}
    ..['style_names'] = {'japandi': 'Japandi Natural'}
    ..['benchtops'] = {'granite_black': 480}
    ..['benchtop_names'] = {'granite_black': 'Black Granite'}
    ..['gst_rate'] = 0.08
    ..['requires_admin_key'] = false;
  edit(doc);
  return doc;
}

/// A throwaway office server: answers `/api/catalog` with [reply].
Future<HttpServer> _office(int status, String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  });
  return server;
}

Uri _url(HttpServer s) => Uri.parse('http://127.0.0.1:${s.port}/api/catalog');

void main() {
  final disk = <String, String>{};

  setUp(() {
    disk.clear();
    PriceCatalog.current = PriceCatalog.builtIn();
    CatalogRepository.read = (key) async => disk[key];
    CatalogRepository.write = (key, value) async => disk[key] = value;
  });

  tearDown(() {
    PriceCatalog.current = PriceCatalog.builtIn();
  });

  group('before the office has ever been reached', () {
    test('the app prices with the sample catalogue shipped inside it',
        () async {
      expect(await CatalogRepository.loadCached(), isNull);
      expect(PriceCatalog.current.version, 1);
      expect(PriceCatalog.current.isPlaceholder, isTrue);
      expect(PriceCatalog.current.unitPrice('base_800', 800), 420);
    });

    test('a damaged saved copy is ignored, not trusted', () async {
      for (final junk in ['', '{ not json', '[]', '{"version": 3}']) {
        disk[CatalogRepository.cacheKey] = junk;
        expect(await CatalogRepository.loadCached(), isNull, reason: junk);
        expect(PriceCatalog.current.version, 1);
      }
    });
  });

  group('refreshing from the office', () {
    test('a new version is used straight away and kept for offline use',
        () async {
      final server = await _office(200, jsonEncode(_served((d) {
        (d['modules'] as List).first['price'] = 455;
        d['labour_rate_per_cabinet'] = 150;
      })));
      addTearDown(() => server.close(force: true));

      final result = await CatalogRepository.refresh(from: _url(server));

      expect(result.status, CatalogSyncStatus.updated);
      expect(PriceCatalog.current.version, 7);
      expect(PriceCatalog.current.unitPrice('base_800', 800), 455);
      // The flat maps older clients read are not part of the catalogue, so
      // they are not saved with it.
      final saved = jsonDecode(disk[CatalogRepository.cacheKey]!) as Map;
      expect(saved['version'], 7);
      expect(saved.containsKey('cabinets'), isFalse);
      expect(saved.containsKey('requires_admin_key'), isFalse);
    });

    test('a quote is priced from the version the app received', () async {
      final server = await _office(200, jsonEncode(_served((d) {
        (d['modules'] as List).first['price'] = 500; // base_800: 420 -> 500
      })));
      addTearDown(() => server.close(force: true));
      await CatalogRepository.refresh(from: _url(server));

      final summary = CPQEngine.calculate(
        placedCabinets: [
          {'cabinet_type': 'base_800', 'width_mm': 800}
        ],
        obstacles: const [],
        styleArchetype: 'japandi',
      );
      expect(summary.catalogVersion, 7);
      expect(summary.baseCabinetTotal, 500);
      expect(summary.subtotal, 500 + 120); // one unit + its installation
    });

    test('after a restart with no network, the last copy is used', () async {
      final server = await _office(
          200,
          jsonEncode(
              _served((d) => (d['modules'] as List).first['price'] = 455)));
      final url = _url(server);
      await CatalogRepository.refresh(from: url);
      await server.close(force: true);

      PriceCatalog.current = PriceCatalog.builtIn(); // app restarted
      final result = await CatalogRepository.sync(from: url);

      expect(result.status, CatalogSyncStatus.offline);
      expect(PriceCatalog.current.version, 7);
      expect(PriceCatalog.current.unitPrice('base_800', 800), 455);
    });

    test('the same version again changes nothing', () async {
      final server =
          await _office(200, jsonEncode(_served((_) {}, version: 1)));
      addTearDown(() => server.close(force: true));
      final result = await CatalogRepository.refresh(from: _url(server));
      expect(result.status, CatalogSyncStatus.unchanged);
    });

    test('an unreachable office leaves the catalogue as it was', () async {
      final server = await _office(200, '{}');
      final gone = _url(server);
      await server.close(force: true);

      final result = await CatalogRepository.refresh(from: gone);

      expect(result.status, CatalogSyncStatus.offline);
      expect(PriceCatalog.current.version, 1);
      expect(disk, isEmpty);
    });

    test('an error from the office leaves the catalogue as it was', () async {
      final server = await _office(500, '{"detail":"boom"}');
      addTearDown(() => server.close(force: true));
      final result = await CatalogRepository.refresh(from: _url(server));
      expect(result.status, CatalogSyncStatus.offline);
      expect(PriceCatalog.current.version, 1);
    });

    test('a reply that is not a catalogue is rejected and never saved',
        () async {
      for (final body in ['not json', '{"version": 9}', '[]']) {
        final server = await _office(200, body);
        final result = await CatalogRepository.refresh(from: _url(server));
        await server.close(force: true);
        expect(result.status, CatalogSyncStatus.rejected, reason: body);
        expect(PriceCatalog.current.version, 1, reason: body);
        expect(disk, isEmpty, reason: body);
      }
    });
  });

  group('the layout generator follows the catalogue', () {
    const room = KitchenRoom(mainWallMm: 3600, wallHeightMm: 2700);

    test('with the sample catalogue it matches the built-in placeholder', () {
      final fromCatalogue = KitchenCatalog.current;
      const placeholder = KitchenCatalog.placeholder;
      expect(fromCatalogue.baseDoorWidthsMm, placeholder.baseDoorWidthsMm);
      expect(fromCatalogue.sinkWidthsMm, placeholder.sinkWidthsMm);
      expect(fromCatalogue.counterHeightMm, placeholder.counterHeightMm);
      expect(fromCatalogue.isPlaceholder, isTrue);
      final rules = KitchenRules.current;
      expect(rules.minSinkToHobMm, KitchenRules.placeholder.minSinkToHobMm);
      expect(rules.maxSinkShiftFromWindowMm,
          KitchenRules.placeholder.maxSinkShiftFromWindowMm);
    });

    test('an edited sink width is the only sink width it uses', () {
      final doc = _sample();
      (doc['layout'] as Map)['sink_widths_mm'] = [900];
      PriceCatalog.current = PriceCatalog.fromJson(doc);

      final variants = const KitchenLayoutGenerator().generateAll(room);
      final sinks = [
        for (final v in variants) ...v.ofKind(ModuleKind.sink),
      ];
      expect(sinks, isNotEmpty);
      expect(sinks.map((m) => m.widthMm).toSet(), {900});
    });

    test('an edited rule changes the layout', () {
      final doc = _sample();
      (doc['layout'] as Map)['rules']['min_sink_to_hob_mm'] = 1200;
      PriceCatalog.current = PriceCatalog.fromJson(doc);

      for (final v in const KitchenLayoutGenerator().generateAll(room)) {
        final sink = v.ofKind(ModuleKind.sink);
        final hob = v.ofKind(ModuleKind.hob);
        if (sink.isEmpty || hob.isEmpty) continue;
        final gap = sink.first.startMm < hob.first.startMm
            ? hob.first.startMm - (sink.first.startMm + sink.first.widthMm)
            : sink.first.startMm - (hob.first.startMm + hob.first.widthMm);
        expect(gap, greaterThanOrEqualTo(1200 - 0.5), reason: v.name);
      }
    });

    test('a generator made for one catalogue ignores a newer current one', () {
      final older = PriceCatalog.builtIn();
      final doc = _sample();
      (doc['layout'] as Map)['sink_widths_mm'] = [900];
      PriceCatalog.current = PriceCatalog.fromJson(doc);

      final variants =
          KitchenLayoutGenerator.forCatalog(older).generateAll(room);
      final widths = {
        for (final v in variants)
          ...v.ofKind(ModuleKind.sink).map((m) => m.widthMm),
      };
      expect(widths, contains(800));
    });
  });
}
