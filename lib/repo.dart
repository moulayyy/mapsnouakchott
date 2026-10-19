import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'est_models.dart';
import 'models.dart';

class Repo extends ChangeNotifier {
  final _fs = FirebaseFirestore.instance;

  bool isAdmin = false;

  // Compte employé créé par l'admin (null = client ou admin)
  bool isStaff = false;
  Set<String> perms = {};

  void setStaff(Map<String, dynamic>? d) {
    isStaff = d != null;
    perms = d == null ? {} : ((d['permissions'] as List?) ?? const []).cast<String>().toSet();
  }

  bool get canChat => isAdmin || (isStaff && perms.contains('chat'));
  bool get canRequests => isAdmin || (isStaff && perms.contains('demandes'));
  List<Moughataa> moughataas = [];
  List<Plan> plans = [];
  List<Lotissement> lotissements = [];
  List<String> kinds = [];
  List<Lot> lots = [];
  List<Block> blocks = [];
  final Map<String, Lot> byKey = {};

  // Admin uniquement
  final Map<String, LotDetail> adminDetails = {};
  final Map<String, String> owners = {}; // key -> propriétaire
  final Map<String, String> ownerNotes = {};

  // Cache des détails (client et admin)
  final Map<String, LotDetail> _details = {};

  Future<void> load({required bool admin}) async {
    isAdmin = admin;
    lots = [];
    byKey.clear();
    adminDetails.clear();
    owners.clear();
    ownerNotes.clear();
    _details.clear();

    final meta = await _fs.collection('meta').get();
    final m = {for (final d in meta.docs) d.id: d.data()};
    if (m['moughataas'] == null || m['plans'] == null || m['lotissements'] == null) {
      throw Exception(
          'Données absentes : lancer le script d\'import (tools/import) avant d\'ouvrir l\'app.');
    }
    moughataas = (jsonDecode(m['moughataas']!['j'] as String) as List)
        .map((e) => Moughataa(e['code'] as int, e['fr'] as String, (e['ar'] ?? '') as String))
        .toList();
    plans = (jsonDecode(m['plans']!['j'] as String) as List)
        .map((e) => Plan.fromJson(e as Map<String, dynamic>))
        .toList();
    kinds = ((m['plans']!['kinds'] as List?) ?? const []).cast<String>().toList();
    lotissements = (jsonDecode(m['lotissements']!['j'] as String) as List)
        .map((e) => Lotissement.fromRow(e as List))
        .toList();
    blocks = m['blocks'] == null
        ? []
        : (jsonDecode(m['blocks']!['j'] as String) as List)
            .map((e) => Block.fromRow(e as List))
            .toList();

    final geo = await _fs.collection(admin ? 'geo_all' : 'geo_public').get();
    final all = <Lot>[];
    for (final d in geo.docs) {
      final data = d.data();
      final plan = data['plan'] as int;
      for (final row in jsonDecode(data['j'] as String) as List) {
        try {
          all.add(Lot.fromRow(row as List, plan, d.id));
        } catch (_) {/* ligne invalide ignorée */}
      }
    }
    lots = all;
    for (final l in lots) {
      byKey[l.key] = l;
    }

    if (admin) {
      final ds = await _fs.collection('lots').get();
      for (final d in ds.docs) {
        adminDetails[d.id] = LotDetail.fromMap(d.data());
      }
      final ps = await _fs.collection('lots_private').get();
      for (final d in ps.docs) {
        final o = d.data()['owner'] as String?;
        if (o != null && o.isNotEmpty) owners[d.id] = o;
        final n = d.data()['note'] as String?;
        if (n != null && n.isNotEmpty) ownerNotes[d.id] = n;
      }
    }
    notifyListeners();
  }

  // ---------- helpers
  Plan? planOf(Lot l) => (l.plan >= 0 && l.plan < plans.length) ? plans[l.plan] : null;
  List<Block> blocksOfPlan(int plan) => blocks.where((b) => b.plan == plan).toList();
  Block? blockOf(int plan, int n) {
    for (final b in blocks) {
      if (b.plan == plan && b.n == n) return b;
    }
    return null;
  }
  Moughataa? moughataa(int code) {
    for (final m in moughataas) {
      if (m.code == code) return m;
    }
    return null;
  }

  String moughataaName(Lot l) {
    final p = planOf(l);
    return p == null ? '—' : (moughataa(p.m)?.fr ?? '—');
  }

  String lotissementName(Lot l) => planOf(l)?.title ?? '—';
  String kindLabel(Lot l) => (l.kind >= 0 && l.kind < kinds.length) ? kinds[l.kind] : '';
  bool isActive(Lot l) => !isAdmin || (adminDetails[l.key]?.active ?? true);

  List<String> get distinctOwners {
    final s = owners.values.toSet().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return s;
  }

  // ---------- détails d'un lot
  Future<LotDetail> getDetail(String key) async {
    final c = _details[key] ?? adminDetails[key];
    if (c != null) return c;
    final snap = await _fs.collection('lots').doc(key).get();
    final d = LotDetail.fromMap(snap.data());
    _details[key] = d;
    return d;
  }

  Future<void> saveLot(Lot lot, LotDetail d, {required String owner, required String note}) async {
    final was = adminDetails[lot.key]?.active ?? true;
    await _fs.collection('lots').doc(lot.key).set({
      ...d.toMap(),
      'updatedAt': Timestamp.now(),
    });
    final priv = _fs.collection('lots_private').doc(lot.key);
    if (owner.trim().isEmpty && note.trim().isEmpty) {
      await priv.delete();
      owners.remove(lot.key);
      ownerNotes.remove(lot.key);
    } else {
      await priv.set({
        'owner': owner.trim(),
        'ownerLower': owner.trim().toLowerCase(),
        'note': note.trim(),
      });
      if (owner.trim().isEmpty) {
        owners.remove(lot.key);
      } else {
        owners[lot.key] = owner.trim();
      }
      if (note.trim().isEmpty) {
        ownerNotes.remove(lot.key);
      } else {
        ownerNotes[lot.key] = note.trim();
      }
    }
    if (was != d.active) await _syncPublic(lot, d.active);
    adminDetails[lot.key] = d;
    _details[lot.key] = d;
    notifyListeners();
  }

  /// Ajoute / retire le lot du document public du lotissement.
  Future<void> _syncPublic(Lot lot, bool active) async {
    final ref = _fs.collection('geo_public').doc(lot.chunk);
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final rows = snap.exists
          ? (jsonDecode(snap.data()!['j'] as String) as List)
          : <dynamic>[];
      rows.removeWhere((r) => (r as List)[0] == lot.key);
      if (active) rows.add(lot.raw);
      tx.set(ref, {'plan': lot.plan, 'j': jsonEncode(rows)}, SetOptions(merge: true));
    });
  }

  // ---------- parcelles et îlots ESTIMÉS (sans valeur juridique)
  EstMeta? est;
  List<EstBlock> estBlocks = [];
  final Map<int, EstBlock> estBlockById = {};
  bool estBlocksLoaded = false;
  bool _estBlocksLoading = false;
  String? estError;
  final Map<String, List<EstLot>> _estTiles = {};
  final Map<String, int> _estUsed = {};
  final Set<String> _estLoading = {};
  static const _estTileMax = 140;

  /// Charge l'index et les îlots estimés (une fois, en arrière-plan).
  Future<void> loadEstBlocks() async {
    if (estBlocksLoaded || _estBlocksLoading) return;
    _estBlocksLoading = true;
    try {
      final meta = await _fs.collection('meta').doc('est').get();
      if (!meta.exists) {
        estError = 'Données estimées absentes : relancer l\'import.';
        return;
      }
      est = EstMeta.fromJson(jsonDecode(meta.data()!['j'] as String) as Map<String, dynamic>);
      final snap = await _fs.collection('est_blocks').get();
      final out = <EstBlock>[];
      for (final d in snap.docs) {
        for (final row in jsonDecode(d.data()['j'] as String) as List) {
          try {
            out.add(EstBlock.fromRow(row as List));
          } catch (_) {}
        }
      }
      estBlocks = out;
      estBlockById
        ..clear()
        ..addEntries(out.map((b) => MapEntry(b.id, b)));
      estBlocksLoaded = true;
      estError = null;
    } catch (e) {
      estError = '$e';
    } finally {
      _estBlocksLoading = false;
      notifyListeners();
    }
  }

  /// Charge les tuiles de parcelles manquantes (en parallèle, avec éviction des plus anciennes).
  Future<void> ensureEstTiles(Iterable<String> keys) async {
    final m = est;
    if (m == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final want = <String>[];
    for (final k in keys) {
      _estUsed[k] = now;
      if (!_estTiles.containsKey(k) && !_estLoading.contains(k)) want.add(k);
    }
    if (want.isEmpty) return;
    _estLoading.addAll(want);
    await Future.wait(want.take(16).map((k) async {
      try {
        final s = await _fs.collection('est_lots').doc(k).get();
        final d = s.data();
        if (d == null) {
          _estTiles[k] = const [];
          return;
        }
        final ox = (d['ox'] as num).toDouble(), oy = (d['oy'] as num).toDouble();
        final lots = <EstLot>[];
        for (final row in jsonDecode(d['j'] as String) as List) {
          try {
            lots.add(EstLot.fromRow(row as List, ox, oy));
          } catch (_) {}
        }
        _estTiles[k] = lots;
      } catch (_) {
        // sera retentée au prochain déplacement
      } finally {
        _estLoading.remove(k);
      }
    }));
    for (final k in want.skip(16)) {
      _estLoading.remove(k);
    }
    if (_estTiles.length > _estTileMax) {
      final old = _estTiles.keys.toList()
        ..sort((a, b) => (_estUsed[a] ?? 0).compareTo(_estUsed[b] ?? 0));
      for (final k in old.take(_estTiles.length - _estTileMax)) {
        if ((_estUsed[k] ?? 0) < now) _estTiles.remove(k);
      }
    }
    notifyListeners();
  }

  List<EstLot> estLotsIn(double south, double west, double north, double east, {int cap = 4000}) {
    final m = est;
    if (m == null) return const [];
    final out = <EstLot>[];
    for (final k in m.tilesIn(south, west, north, east)) {
      final lots = _estTiles[k];
      if (lots == null) continue;
      for (final l in lots) {
        if (l.maxLat < south || l.minLat > north || l.maxLon < west || l.minLon > east) continue;
        out.add(l);
        if (out.length >= cap) return out;
      }
    }
    return out;
  }

  List<EstBlock> estBlocksIn(double south, double west, double north, double east, {int cap = 3000}) {
    final out = <EstBlock>[];
    for (final b in estBlocks) {
      if (b.inCert) continue;
      if (b.maxLat < south || b.minLat > north || b.maxLon < west || b.minLon > east) continue;
      out.add(b);
      if (out.length >= cap) break;
    }
    return out;
  }

  EstLot? estLotById(int id) {
    for (final lots in _estTiles.values) {
      for (final l in lots) {
        if (l.id == id) return l;
      }
    }
    return null;
  }

  /// Îlot estimé qui contient la parcelle n° [id] (d'après les plages de numéros).
  EstBlock? estBlockForLot(int id) {
    for (final b in estBlocks) {
      if (b.first > 0 && id >= b.first && id <= b.last) return b;
    }
    return null;
  }

  String estQuartier(int? i) {
    final q = est?.quartiers;
    if (i == null || q == null || i < 0 || i >= q.length) return '';
    return q[i].isNotEmpty ? q[i][0] : '';
  }

  String estStreet(EstLot l) {
    final m = est;
    if (m == null || l.streetName == null) return '';
    final i = l.streetName!;
    return (i >= 0 && i < m.streetNames.length) ? m.streetNames[i] : '';
  }

  /// Offres en ligne (vente / location) visibles par tous.
  Future<List<MapEntry<String, LotDetail>>> loadOffers() async {
    final q = await _fs.collection('lots').where('active', isEqualTo: true).get();
    final tmp = <(String, LotDetail, int)>[];
    for (final d in q.docs) {
      final data = d.data();
      final det = LotDetail.fromMap(data);
      final ts = data['updatedAt'];
      if (det.offer != null) {
        tmp.add((d.id, det, ts is Timestamp ? ts.millisecondsSinceEpoch : 0));
      }
    }
    tmp.sort((a, b) => b.$3.compareTo(a.$3)); // plus récentes d'abord
    return [for (final t in tmp) MapEntry(t.$1, t.$2)];
  }
}

final repo = Repo();
