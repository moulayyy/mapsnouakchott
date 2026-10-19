import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapsnouakchott/models.dart';

// Valide l'analyse des données importées (sortie de `import.mjs --dry`).
// Lancer : flutter test (dossier /tmp/dry/out requis, sinon le test est ignoré).
void main() {
  final dir = Directory('/tmp/dry/out');
  test('lots, blocs et lotissements se lisent', () {
    var lots = 0, inBlock = 0;
    final blocksSeen = <String>{};
    for (final f in dir.listSync().whereType<File>().where((f) => f.path.contains('geo_'))) {
      final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final row in jsonDecode(d['j'] as String) as List) {
        final l = Lot.fromRow(row as List, d['plan'] as int, 'x');
        lots++;
        if (l.isLot && l.block != null) {
          inBlock++;
          blocksSeen.add('${l.plan}_${l.block}');
        }
        expect(l.ring.length, greaterThanOrEqualTo(3));
      }
    }
    final b = (jsonDecode((jsonDecode(File('${dir.path}/meta_blocks.json').readAsStringSync()) as Map)['j'] as String) as List)
        .map((e) => Block.fromRow(e as List))
        .toList();
    final l = (jsonDecode((jsonDecode(File('${dir.path}/meta_lotissements.json').readAsStringSync()) as Map)['j'] as String) as List)
        .map((e) => Lotissement.fromRow(e as List))
        .toList();
    // ignore: avoid_print
    print('lots=$lots dansBloc=$inBlock blocs=${b.length} (vus ${blocksSeen.length}) lotissements=${l.length}');
    expect(lots, 11714);
    expect(b.length, blocksSeen.length);
    expect(b.first.ring.length, greaterThanOrEqualTo(3));
  }, skip: !dir.existsSync());
}
