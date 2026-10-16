import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

class Repo extends ChangeNotifier {
  final _fs = FirebaseFirestore.instance;

  bool isAdmin = false;
  List<Moughataa> moughataas = [];
  List<Plan> plans = [];
  List<Lotissement> lotissements = [];
  List<String> kinds = [];
  List<Lot> lots = [];
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

  /// Offres en ligne (vente / location) visibles par tous.
  Future<List<MapEntry<String, LotDetail>>> loadOffers() async {
    final q = await _fs.collection('lots').where('active', isEqualTo: true).get();
    final out = <MapEntry<String, LotDetail>>[];
    for (final d in q.docs) {
      final det = LotDetail.fromMap(d.data());
      if (det.offer != null) out.add(MapEntry(d.id, det));
    }
    return out;
  }
}

final repo = Repo();
