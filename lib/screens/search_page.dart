import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';
import '../repo.dart';
import '../services.dart';

List<double>? bboxOf(Iterable<Lot> lots) {
  double? a, b, c, d;
  for (final l in lots) {
    a = a == null ? l.minLat : math.min(a, l.minLat);
    b = b == null ? l.minLon : math.min(b, l.minLon);
    c = c == null ? l.maxLat : math.max(c, l.maxLat);
    d = d == null ? l.maxLon : math.max(d, l.maxLon);
  }
  if (a == null) return null;
  return [a, b!, c!, d!];
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  Moughataa? _m;
  Lotissement? _l;
  String _q = '';

  void _back() {
    if (_l != null) {
      setState(() {
        _l = null;
        _ctrl.clear();
        _q = '';
      });
    } else if (_m != null) {
      setState(() {
        _m = null;
        _ctrl.clear();
        _q = '';
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _pick(Moughataa m) => setState(() {
        _m = m;
        _l = null;
        _ctrl.clear();
        _q = '';
      });

  void _pickLts(Lotissement l) => setState(() {
        _l = l;
        _m ??= repo.moughataa(l.m);
        _ctrl.clear();
        _q = '';
      });

  void _done(FocusRequest r) => Navigator.pop(context, r);

  String get _hint {
    if (_l != null) return 'N° de lot';
    if (_m != null) return 'Lotissement de ${_m!.fr}';
    return 'Moughataa, lotissement, n° de lot';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _m == null && _l == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          title: Text(_l?.title ?? _m?.fr ?? 'Recherche'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _ctrl,
                autofocus: _m == null && _l == null,
                keyboardType: _l != null ? TextInputType.text : TextInputType.text,
                decoration: InputDecoration(
                  hintText: _hint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_l != null) return _lotList(_l!);
    if (_m != null) return _lotissementList(_m!);
    if (_q.trim().isNotEmpty) return _globalResults();
    return _home();
  }

  // ---------- accueil : moughataas (+ propriétaires pour l'admin)
  Widget _home() {
    return ListView(
      children: [
        for (final m in repo.moughataas)
          ListTile(
            leading: const Icon(Icons.location_city),
            title: Text(m.fr),
            subtitle: m.ar.isEmpty ? null : Text(m.ar),
            trailing: Text(
                '${repo.lotissements.where((l) => l.m == m.code).length} lotissements'),
            onTap: () => _pick(m),
          ),
        if (repo.isAdmin && repo.distinctOwners.isNotEmpty) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Propriétaires (admin)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final o in repo.distinctOwners) _ownerTile(o),
        ],
      ],
    );
  }

  Widget _ownerTile(String o) {
    final keys = repo.owners.entries.where((e) => e.value == o).map((e) => e.key).toSet();
    return ListTile(
      leading: const Icon(Icons.person_pin_circle_outlined),
      title: Text(o),
      subtitle: Text('${keys.length} terrain(s)'),
      onTap: () {
        final lots = keys.map((k) => repo.byKey[k]).whereType<Lot>();
        _done(FocusRequest(title: 'Propriétaire : $o', lotKeys: keys, bbox: bboxOf(lots)));
      },
    );
  }

  // ---------- lotissements d'une moughataa
  Widget _lotissementList(Moughataa m) {
    final nq = norm(_q);
    final items = repo.lotissements
        .where((l) => l.m == m.code && (nq.isEmpty || norm(l.name).contains(nq)))
        .toList()
      ..sort((a, b) {
        if (a.hasPlan != b.hasPlan) return a.hasPlan ? -1 : 1;
        return b.planLots.compareTo(a.planLots);
      });
    return ListView(
      children: [
        ListTile(
          tileColor: Theme.of(context).colorScheme.primaryContainer,
          leading: const Icon(Icons.map),
          title: Text('Voir tous les terrains de ${m.fr}'),
          onTap: () => _done(FocusRequest(title: m.fr, moughataa: m.code)),
        ),
        for (final l in items)
          ListTile(
            title: Text(l.title),
            subtitle: Text(
                '${l.planLots} lots · ${l.hasPlan ? 'plan disponible' : 'plan non disponible'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLts(l),
          ),
      ],
    );
  }

  // ---------- lots d'un lotissement
  Widget _lotList(Lotissement l) {
    if (!l.hasPlan) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${l.planLots} lots dans l\'index, mais le plan détaillé des lots '
              'n\'est pas disponible pour ce lotissement.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.map),
            label: const Text('Voir la zone sur la carte'),
            onPressed: () => _done(FocusRequest(title: l.title, point: LatLng(l.lat, l.lon))),
          ),
        ],
      );
    }
    final plan = repo.plans[l.planIdx];
    final nq = norm(_q);
    final lots = repo.lots
        .where((x) =>
            x.plan == plan.idx &&
            x.isLot &&
            x.label != null &&
            (nq.isEmpty || norm(x.label!).contains(nq)))
        .toList()
      ..sort((a, b) {
        final na = int.tryParse(a.label!), nb = int.tryParse(b.label!);
        if (na != null && nb != null) return na.compareTo(nb);
        return a.label!.compareTo(b.label!);
      });
    return Column(
      children: [
        ListTile(
          tileColor: Theme.of(context).colorScheme.primaryContainer,
          leading: const Icon(Icons.map),
          title: const Text('Voir tout le lotissement'),
          subtitle: Text('${lots.length} lot(s) listés'),
          onTap: () => _done(FocusRequest(
            title: l.title,
            plan: plan.idx,
            bbox: [plan.minLat, plan.minLon, plan.maxLat, plan.maxLon],
          )),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: lots.length,
            itemBuilder: (context, i) {
              final x = lots[i];
              return ListTile(
                dense: true,
                title: Text('Lot ${x.label}'),
                subtitle: Text('${fmtNum(x.area)} m²'),
                onTap: () => _done(FocusRequest(title: 'Lot ${x.label}', selectKey: x.key)),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- recherche globale
  Widget _globalResults() {
    final nq = norm(_q);
    final ms = repo.moughataas
        .where((m) => norm(m.fr).contains(nq) || m.ar.contains(_q.trim()))
        .toList();
    final ls = repo.lotissements.where((l) => norm(l.name).contains(nq)).take(40).toList();

    // "nom du lotissement + n° de lot"
    final lotHits = <Lot>[];
    for (final p in repo.plans) {
      final pn = norm(p.name);
      if (pn.isNotEmpty && nq.startsWith(pn) && nq.length > pn.length) {
        final rest = nq.substring(pn.length).trim();
        if (rest.isEmpty) continue;
        for (final x in repo.lots) {
          if (x.plan == p.idx && x.label != null && norm(x.label!) == rest) {
            lotHits.add(x);
          }
        }
      }
    }
    final owners = repo.isAdmin
        ? repo.distinctOwners.where((o) => norm(o).contains(nq)).toList()
        : <String>[];

    final tiles = <Widget>[];
    if (lotHits.isNotEmpty) {
      tiles.add(const _Header('Lots'));
      for (final x in lotHits) {
        tiles.add(ListTile(
          leading: const Icon(Icons.crop_square),
          title: Text('Lot ${x.label} — ${repo.lotissementName(x)}'),
          subtitle: Text('${fmtNum(x.area)} m²'),
          onTap: () => _done(FocusRequest(title: 'Lot ${x.label}', selectKey: x.key)),
        ));
      }
    }
    if (ms.isNotEmpty) {
      tiles.add(const _Header('Moughataas'));
      for (final m in ms) {
        tiles.add(ListTile(
          leading: const Icon(Icons.location_city),
          title: Text(m.fr),
          onTap: () => _pick(m),
        ));
      }
    }
    if (ls.isNotEmpty) {
      tiles.add(const _Header('Lotissements'));
      for (final l in ls) {
        tiles.add(ListTile(
          title: Text(l.title),
          subtitle: Text(
              '${repo.moughataa(l.m)?.fr ?? ''} · ${l.planLots} lots${l.hasPlan ? '' : ' · plan non disponible'}'),
          onTap: () => _pickLts(l),
        ));
      }
    }
    if (owners.isNotEmpty) {
      tiles.add(const _Header('Propriétaires'));
      for (final o in owners) {
        tiles.add(_ownerTile(o));
      }
    }
    if (tiles.isEmpty) {
      return const Center(child: Text('Aucun résultat.'));
    }
    return ListView(children: tiles);
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}
