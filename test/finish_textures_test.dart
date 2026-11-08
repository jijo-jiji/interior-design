import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/scene/finish_textures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manifest =
      jsonDecode(File('assets/3d/textures/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final textures = manifest['textures'] as Map<String, dynamic>;
  final page = File('assets/3d/index.html').readAsStringSync();

  group('the texture set', () {
    test('every file the manifest names exists, as a JPEG', () {
      final names = <String>{
        for (final t in textures.values)
          for (final key in const ['albedo', 'normal', 'roughness'])
            if ((t as Map)[key] != null) t[key] as String,
        for (final v in (manifest['micro'] as Map).values)
          if (v is String && v.endsWith('.jpg')) v,
      };
      expect(names.length, greaterThan(15));
      for (final name in names) {
        final file = File('assets/3d/textures/$name');
        expect(file.existsSync(), isTrue, reason: name);
        final head = file.readAsBytesSync().sublist(0, 3);
        expect(head, [0xff, 0xd8, 0xff], reason: '$name is not a JPEG');
      }
    });

    test('every texture the page asks for is in the manifest', () {
      // STYLE_FINISHES (tex: 'oak_light') and BENCHTOP_LOOKS in the page.
      final asked = RegExp(r"tex: '([a-z_]+)'")
          .allMatches(page)
          .map((m) => m.group(1)!)
          .toSet();
      expect(asked, containsAll(['oak_light', 'walnut', 'birch', 'terrazzo']));
      for (final id in asked) {
        expect(textures.containsKey(id), isTrue,
            reason: 'the page uses "$id" but the manifest has no such texture');
      }
      expect(textures.containsKey('floor_oak'), isTrue);
    });

    test('the backsplash tiles the page names are in the manifest', () {
      final tiles = RegExp(r"'(tile_[a-z]+)'")
          .allMatches(page)
          .map((m) => m.group(1)!)
          .toSet();
      expect(tiles, {'tile_subway', 'tile_hex'});
      for (final id in tiles) {
        expect(textures.containsKey(id), isTrue, reason: id);
        expect((textures[id] as Map)['kind'], 'tile');
      }
      // The hexagon sheet is not square: the manifest says how tall it is.
      expect((textures['tile_hex'] as Map)['tile_h_m'], isNotNull);
    });

    test('the set stays small enough to send to a tablet', () {
      final bytes = Directory('assets/3d/textures')
          .listSync()
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + f.lengthSync());
      expect(bytes, lessThan(4 * 1024 * 1024));
    });

    test('wood tiles at one size and stone at one size', () {
      Set<Object?> tiles(String kind) => {
            for (final t in textures.values)
              if ((t as Map)['kind'] == kind) t['tile_m'],
          };
      expect(tiles('wood'), hasLength(1));
      expect(tiles('stone'), hasLength(1));
    });
  });

  group('handing the textures to the page', () {
    setUp(FinishTextures.forget);

    test('sends the manifest, then every file as a data URL, then "ready"',
        () async {
      final calls = <String>[];
      final ok = await FinishTextures.send((js) async => calls.add(js));

      expect(ok, isTrue);
      expect(calls.first, startsWith('registerFinishTextures('));
      expect(calls.last, 'finishTexturesReady()');
      final files = calls.where((c) => c.startsWith('registerFinishFile('));
      expect(files.length, greaterThan(15));
      expect(calls.length, files.length + 2);
      for (final call in files) {
        expect(call, contains('"data:image/jpeg;base64,/9j/'));
      }
      // The manifest travels as a JSON string the page can parse.
      final argument = calls.first
          .substring('registerFinishTextures('.length, calls.first.length - 1);
      final parsed = jsonDecode(jsonDecode(argument) as String) as Map;
      expect(parsed['textures'], isNotEmpty);
    });

    test('a failure to send is reported, not thrown', () async {
      final ok =
          await FinishTextures.send((js) async => throw StateError('no page'));
      expect(ok, isFalse);
    });
  });
}
