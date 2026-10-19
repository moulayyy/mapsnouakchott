import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsnouakchott/est_models.dart';

// Valide l'analyse des parcelles / îlots estimés (sortie de `import.mjs --dry`).
void main() {
  final dir = Directory('/tmp/dry2/out');
  test('îlots et parcelles estimés se lisent', () {
    final meta = EstMeta.fromJson(jsonDecode(
        (jsonDecode(File('${dir.path}/meta_est.json').readAsStringSync()) as Map)['j'] as String)
        as Map<String, dynamic>);
    expect(meta.tiles.length, greaterThan(700));
    expect(meta.streetNames.length, greaterThan(100));

    var blocks = 0;
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.contains('est_blocks_'))) {
      for (final row in jsonDecode((jsonDecode(f.readAsStringSync()) as Map)['j'] as String) as List) {
        final b = EstBlock.fromRow(row as List);
        blocks++;
        expect(b.ring.length, greaterThanOrEqualTo(3));
        expect(b.minLat, inInclusiveRange(17.85, 18.3));
        expect(b.minLon, inInclusiveRange(-16.2, -15.7));
      }
    }
    expect(blocks, 26853);

    var lots = 0;
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.contains('est_lots_'))) {
      final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final ox = (d['ox'] as num).toDouble(), oy = (d['oy'] as num).toDouble();
      for (final row in jsonDecode(d['j'] as String) as List) {
        final l = EstLot.fromRow(row as List, ox, oy);
        lots++;
        expect(l.ring.length, greaterThanOrEqualTo(3));
        expect(l.minLat, inInclusiveRange(17.85, 18.3));
        expect(l.minLon, inInclusiveRange(-16.2, -15.7));
        expect(l.area, greaterThan(0));
        expect(l.contains(l.centroid) || l.ring.length < 4, isTrue);
        // la tuile de la parcelle doit être connue de l'index
        expect(meta.tiles.contains(meta.tileKey(l.centroid.latitude, l.centroid.longitude)), isTrue);
      }
    }
    // ignore: avoid_print
    print('îlots=$blocks parcelles échantillon=$lots tuiles=${meta.tiles.length}');
    expect(lots, greaterThan(500));
  }, skip: !dir.existsSync());
}
