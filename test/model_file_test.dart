import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/utils/model_file.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('models'));
  tearDown(() => dir.delete(recursive: true));

  Uint8List model(int seed) =>
      Uint8List.fromList(List.generate(5000, (i) => (i * seed + 7) & 0xff));

  List<String> files() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('the same model is saved once and reused', () async {
    final first = await saveModel('assets/models/wall_corners.onnx', model(3), dir);
    expect(first, contains('wall_corners-'));
    expect(first, endsWith('.onnx'));
    final written = await File(first).lastModified();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final again = await saveModel('assets/models/wall_corners.onnx', model(3), dir);
    expect(again, first);
    expect(await File(again).lastModified(), written);
    expect(await File(again).readAsBytes(), model(3));
  });

  test('an updated model gets a new copy; old copies go', () async {
    // The copy flutter_onnxruntime saved under the bare name, before.
    File('${dir.path}/wall_corners.onnx').writeAsBytesSync(model(3));
    final old = await saveModel('assets/models/wall_corners.onnx', model(3), dir);
    final updated = await saveModel('assets/models/wall_corners.onnx', model(5), dir);
    expect(updated, isNot(old));
    expect(await File(updated).readAsBytes(), model(5));
    expect(files(), [updated.split(Platform.pathSeparator).last]);
  });

  test("other models' copies are left alone", () async {
    final depth = await saveModel('assets/models/wall_depth.onnx', model(2), dir);
    final corners = await saveModel('assets/models/wall_corners.onnx', model(3), dir);
    expect(File(depth).existsSync(), isTrue);
    expect(File(corners).existsSync(), isTrue);
  });

  test('a half-written copy is replaced', () async {
    final path = await saveModel('assets/models/wall_corners.onnx', model(3), dir);
    File(path).writeAsBytesSync(Uint8List(10));
    await saveModel('assets/models/wall_corners.onnx', model(3), dir);
    expect(await File(path).readAsBytes(), model(3));
  });

  test('fingerprint: FNV-1a 64', () {
    expect(fingerprint(Uint8List(0)), 'cbf29ce484222325');
    expect(fingerprint(Uint8List.fromList('a'.codeUnits)), 'af63dc4c8601ec8c');
    expect(fingerprint(model(3)), isNot(fingerprint(model(5))));
  });
}
