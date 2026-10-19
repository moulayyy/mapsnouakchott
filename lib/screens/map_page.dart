import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../est_models.dart';
import '../models.dart';
import '../repo.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/est_lot_card.dart';
import '../widgets/lot_card.dart';
import 'lot_edit_page.dart';
import 'search_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  bool _ready = false;
  double _zoom = 12.5;
  LatLngBounds? _bounds;
  bool _satellite = true;
  Lot? _selected;
  EstLot? _selectedEst; // parcelle estimée sélectionnée
  int? _focusEstBlock; // îlot estimé mis en évidence
  int? _pendingEstLot; // parcelle P… à sélectionner dès que sa tuile est chargée
  bool _estAsked = false;
  bool _showLts = true; // centres de lotissements (cercles jaunes)
  FocusRequest? _focus;
  LatLng? _me;
  RouteResult? _route;
  bool _routing = false;
  Timer? _debounce;

  // Règle : appui long sur la carte pour démarrer, puis un appui par point.
  bool _measuring = false;
  final List<LatLng> _mpts = [];
  static const _distance = Distance();

  double get _measureTotal {
    var t = 0.0;
    for (var i = 1; i < _mpts.length; i++) {
      t += _distance.as(LengthUnit.Meter, _mpts[i - 1], _mpts[i]);
    }
    return t;
  }

  static String _fmtDist(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';
    return '${m.toStringAsFixed(1).replaceAll('.', ',')} m';
  }

  /// Accroche le point au coin de lot le plus proche (≈ 10 px) s'il y en a un.
  LatLng _snap(LatLng p) {
    if (_zoom < AppConfig.lotMinZoom) return p;
    final mpp = 156543.03 * math.cos(p.latitude * math.pi / 180) / math.pow(2, _zoom);
    final radius = 10 * mpp;
    LatLng best = p;
    var bestD = radius;
    for (final l in _visibleLots()) {
      if (p.latitude < l.minLat - 0.0005 || p.latitude > l.maxLat + 0.0005 ||
          p.longitude < l.minLon - 0.0005 || p.longitude > l.maxLon + 0.0005) {
        continue;
      }
      for (final v in l.ring) {
        final d = _distance.as(LengthUnit.Meter, p, v);
        if (d < bestD) {
          bestD = d;
          best = v;
        }
      }
    }
    for (final l in _visibleEst()) {
      if (p.latitude < l.minLat - 0.0005 || p.latitude > l.maxLat + 0.0005 ||
          p.longitude < l.minLon - 0.0005 || p.longitude > l.maxLon + 0.0005) {
        continue;
      }
      for (final v in l.ring) {
        final d = _distance.as(LengthUnit.Meter, p, v);
        if (d < bestD) {
          bestD = d;
          best = v;
        }
      }
    }
    return best;
  }

  void _startMeasure(LatLng p) {
    setState(() {
      _measuring = true;
      _selected = null;
      _selectedEst = null;
      _mpts
        ..clear()
        ..add(_snap(p));
    });
  }

  void _addMeasure(LatLng p) => setState(() => _mpts.add(_snap(p)));

  void _undoMeasure() {
    setState(() {
      if (_mpts.isNotEmpty) _mpts.removeLast();
      if (_mpts.isEmpty) _measuring = false;
    });
  }

  void _endMeasure() => setState(() {
        _measuring = false;
        _mpts.clear();
      });

  void _showRulerInfo() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.straighten),
        title: const Text('Mesurer une distance'),
        content: const Text(
            'Faites un appui long sur la carte pour poser le premier point, '
            'puis touchez les points suivants. La distance s\'affiche en mètres. '
            'Les points s\'accrochent au coin de lot le plus proche.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    appState.addListener(_onApp);
    repo.addListener(_onRepo);
  }

  @override
  void dispose() {
    appState.removeListener(_onApp);
    repo.removeListener(_onRepo);
    _debounce?.cancel();
    super.dispose();
  }

  void _onRepo() {
    if (!mounted) return;
    if (!_estAsked && repo.est != null) {
      _estAsked = true;
      _requestTiles();
    }
    final pid = _pendingEstLot;
    if (pid != null) {
      final l = repo.estLotById(pid);
      if (l != null) {
        _pendingEstLot = null;
        setState(() {
          _selectedEst = l;
          _selected = null;
        });
        _fitBox(l.bbox, maxZoom: 19);
        return;
      }
    }
    setState(() {});
  }

  /// Charge les tuiles de parcelles estimées visibles.
  void _requestTiles() {
    final b = _bounds;
    final m = repo.est;
    if (b == null || m == null || _zoom < AppConfig.lotMinZoom) return;
    final keys = m.tilesIn(b.south - 0.002, b.west - 0.002, b.north + 0.002, b.east + 0.002);
    if (keys.isNotEmpty) repo.ensureEstTiles(keys);
  }

  List<EstLot> _visibleEst() {
    final b = _bounds;
    if (b == null || _zoom < AppConfig.lotMinZoom) return const [];
    return repo.estLotsIn(b.south, b.west, b.north, b.east);
  }

  void _onApp() {
    if (_ready && appState.pendingFocus != null) {
      _apply(appState.takeFocus()!);
    }
  }

  // ---------- focus
  void _apply(FocusRequest f) {
    // îlot ou parcelle ESTIMÉS (recherche B… / P… / lotissement sans plan)
    if (f.estBlock != null || f.estLot != null) {
      final b = f.estBlock != null
          ? repo.estBlockById[f.estBlock!]
          : repo.estBlockForLot(f.estLot!);
      setState(() {
        _focus = f;
        _focusEstBlock = b?.id;
        _selected = null;
        _selectedEst = null;
        _route = null;
      });
      if (f.estLot != null) {
        if (b == null) {
          _snack('Parcelle introuvable : P${f.estLot}');
        } else {
          _pendingEstLot = f.estLot;
          _fitBox(b.bbox, maxZoom: 19);
        }
      } else if (b != null) {
        _fitBox(b.bbox, maxZoom: 18);
      }
      return;
    }
    Lot? sel;
    if (f.selectKey != null) sel = repo.byKey[f.selectKey!];
    _computeFocusBlocks(f);
    setState(() {
      _focus = (f.selectKey != null) ? null : f;
      _focusEstBlock = null;
      _selected = sel;
      _selectedEst = null;
      _route = null;
    });
    if (sel != null) {
      _fitBox([sel.minLat, sel.minLon, sel.maxLat, sel.maxLon], maxZoom: 19);
    } else if (f.bbox != null) {
      _fitBox(f.bbox!);
    } else if (f.moughataa != null) {
      final ps = repo.plans.where((p) => p.m == f.moughataa).toList();
      if (ps.isNotEmpty) {
        _fitBox([
          ps.map((p) => p.minLat).reduce((a, b) => a < b ? a : b),
          ps.map((p) => p.minLon).reduce((a, b) => a < b ? a : b),
          ps.map((p) => p.maxLat).reduce((a, b) => a > b ? a : b),
          ps.map((p) => p.maxLon).reduce((a, b) => a > b ? a : b),
        ]);
      } else {
        final ls = repo.lotissements.where((l) => l.m == f.moughataa).toList();
        if (ls.isNotEmpty) {
          _fitBox([
            ls.map((l) => l.lat).reduce((a, b) => a < b ? a : b),
            ls.map((l) => l.lon).reduce((a, b) => a < b ? a : b),
            ls.map((l) => l.lat).reduce((a, b) => a > b ? a : b),
            ls.map((l) => l.lon).reduce((a, b) => a > b ? a : b),
          ]);
        }
      }
    } else if (f.point != null) {
      _map.move(f.point!, 16.5);
    }
  }

  void _fitBox(List<double> b, {double maxZoom = 18}) {
    final lat = (b[2] - b[0]).abs(), lon = (b[3] - b[1]).abs();
    if (lat < 1e-7 && lon < 1e-7) {
      _map.move(LatLng(b[0], b[1]), maxZoom);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(LatLng(b[0], b[1]), LatLng(b[2], b[3])),
      padding: const EdgeInsets.fromLTRB(40, 90, 40, 260),
      maxZoom: maxZoom,
    ));
  }

  Set<String> _focusBlockKeys = {};

  bool _focused(Lot l) {
    final f = _focus;
    if (f == null) return false;
    if (f.lotKeys != null) return f.lotKeys!.contains(l.key);
    if (f.plan != null) return l.plan == f.plan && (f.block == null || l.block == f.block);
    if (f.moughataa != null) return repo.planOf(l)?.m == f.moughataa;
    return false;
  }

  bool _blockFocused(Block b) {
    final f = _focus;
    if (f == null) return false;
    if (f.lotKeys != null) return _focusBlockKeys.contains('${b.plan}_${b.n}');
    if (f.plan != null) return b.plan == f.plan && (f.block == null || b.n == f.block);
    if (f.moughataa != null) return repo.plans[b.plan].m == f.moughataa;
    return false;
  }

  void _computeFocusBlocks(FocusRequest? f) {
    _focusBlockKeys = {};
    if (f?.lotKeys == null) return;
    for (final k in f!.lotKeys!) {
      final l = repo.byKey[k];
      if (l != null && l.block != null) _focusBlockKeys.add('${l.plan}_${l.block}');
    }
  }

  // ---------- interactions
  void _onPosition(MapCamera cam, bool gesture) {
    _zoom = cam.zoom;
    _bounds = cam.visibleBounds;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {});
      _requestTiles();
    });
  }

  List<Lot> _visibleLots() {
    final b = _bounds;
    if (b == null || _zoom < AppConfig.lotMinZoom) return const [];
    final out = <Lot>[];
    for (final l in repo.lots) {
      if (l.maxLat < b.south || l.minLat > b.north || l.maxLon < b.west || l.minLon > b.east) {
        continue;
      }
      out.add(l);
      if (out.length >= 4000) break;
    }
    return out;
  }

  void _onTap(TapPosition tp, LatLng p) {
    if (_measuring) {
      _addMeasure(p);
      return;
    }
    final lts = _ltsAt(p);
    if (lts != null) {
      _showLtsSheet(lts);
      return;
    }
    if (_zoom >= AppConfig.lotMinZoom) {
      for (final l in _visibleLots()) {
        if (l.contains(p)) {
          setState(() {
            _selected = l;
            _selectedEst = null;
          });
          return;
        }
      }
      for (final l in _visibleEst()) {
        if (l.contains(p)) {
          setState(() {
            _selectedEst = l;
            _selected = null;
          });
          return;
        }
      }
      setState(() {
        _selected = null;
        _selectedEst = null;
      });
      return;
    }
    for (final b in repo.blocks) {
      if (b.contains(p)) {
        _fitBox(b.bbox, maxZoom: 18);
        return;
      }
    }
    for (final b in repo.estBlocks) {
      if (!b.inCert && _zoom >= 12 && b.contains(p)) {
        _fitBox(b.bbox, maxZoom: 17);
        return;
      }
    }
  }

  // ---------- centres de lotissements (cercles jaunes, comme le site du client)
  double _ltsRadius(Lotissement l) => (4 + math.sqrt(l.planLots) * 0.35).clamp(4.0, 11.0);

  Lotissement? _ltsAt(LatLng p) {
    if (!_showLts || _zoom < 12) return null;
    final mpp = 156543.03 * math.cos(p.latitude * math.pi / 180) / math.pow(2, _zoom);
    Lotissement? best;
    var bestD = double.infinity;
    for (final l in repo.lotissements) {
      final d = _distance.as(LengthUnit.Meter, p, LatLng(l.lat, l.lon));
      final tol = (_ltsRadius(l) + 8) * mpp;
      if (d <= tol && d < bestD) {
        bestD = d;
        best = l;
      }
    }
    return best;
  }

  void _showLtsSheet(Lotissement l) {
    final m = repo.moughataa(l.m);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${m?.fr ?? ''} · ${fmtNum(l.planLots)} lots'),
              const SizedBox(height: 4),
              Text(
                l.hasPlan
                    ? 'Plan officiel disponible : lots numérotés sur la carte.'
                    : 'Plan officiel indisponible : parcelles estimées seulement.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 2),
              Text('Le cercle marque le centre du lotissement, pas son contour.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.map),
                    label: Text(l.hasPlan ? 'Voir le plan' : 'Voir la zone'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (l.hasPlan) {
                        final pl = repo.plans[l.planIdx];
                        _apply(FocusRequest(
                          title: l.title,
                          plan: pl.idx,
                          bbox: [pl.minLat, pl.minLon, pl.maxLat, pl.maxLon],
                        ));
                      } else {
                        _apply(FocusRequest(title: l.title, point: LatLng(l.lat, l.lon)));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _search() async {
    final r = await Navigator.push<FocusRequest>(
        context, MaterialPageRoute(builder: (_) => const SearchPage()));
    if (r != null) _apply(r);
  }

  Future<void> _locate() async {
    try {
      final me = await LocationService.current();
      setState(() => _me = me);
      _map.move(me, 17);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _goRouteTo(LatLng dest) async {
    setState(() => _routing = true);
    try {
      final me = await LocationService.current();
      final r = await Routing.fetch(me, dest);
      setState(() {
        _me = me;
        _route = r;
      });
      final lats = r.points.map((p) => p.latitude), lons = r.points.map((p) => p.longitude);
      _fitBox([
        lats.reduce((a, b) => a < b ? a : b),
        lons.reduce((a, b) => a < b ? a : b),
        lats.reduce((a, b) => a > b ? a : b),
        lons.reduce((a, b) => a > b ? a : b),
      ]);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _edit(Lot lot) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => LotEditPage(lot: lot)));
    if (mounted) setState(() {});
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- rendu
  @override
  Widget build(BuildContext context) {
    final lots = _visibleLots();
    final polygons = <Polygon>[];

    // Parcelles et îlots ESTIMÉS (orange), dessinés sous les lots certifiés.
    final estPolys = <Polygon>[];
    final vb = _bounds;
    if (vb != null && repo.estBlocksLoaded && _zoom >= 12 && _zoom < AppConfig.lotMinZoom) {
      for (final b in repo.estBlocksIn(vb.south, vb.west, vb.north, vb.east)) {
        final foc = _focusEstBlock == b.id;
        estPolys.add(Polygon(
          points: b.ring,
          color: (foc ? Colors.amber : Colors.orange).withValues(alpha: foc ? 0.5 : 0.18),
          borderColor: foc ? Colors.deepOrange : Colors.orange.withValues(alpha: 0.9),
          borderStrokeWidth: foc ? 2.5 : 1,
        ));
      }
    }
    if (_zoom >= AppConfig.lotMinZoom) {
      for (final l in _visibleEst()) {
        final sel = _selectedEst?.id == l.id;
        final foc = _focusEstBlock != null && l.block == _focusEstBlock;
        estPolys.add(Polygon(
          points: l.ring,
          color: sel
              ? Colors.red.withValues(alpha: 0.45)
              : (foc ? Colors.amber.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.08)),
          borderColor: sel ? Colors.red : Colors.orange.withValues(alpha: 0.85),
          borderStrokeWidth: sel ? 3 : 1,
        ));
      }
    }

    if (_zoom < AppConfig.lotMinZoom) {
      for (final b in repo.blocks) {
        if (vb != null &&
            (b.maxLat < vb.south || b.minLat > vb.north || b.maxLon < vb.west || b.minLon > vb.east)) {
          continue;
        }
        final foc = _blockFocused(b);
        polygons.add(Polygon(
          points: b.ring,
          color: (foc ? Colors.amber : Colors.green).withValues(alpha: foc ? 0.5 : 0.28),
          borderColor: foc ? Colors.orange.shade800 : Colors.greenAccent.shade700,
          borderStrokeWidth: foc ? 2 : 1.2,
          label: _zoom >= 14 ? '${b.n}' : null,
          labelStyle: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ));
      }
    } else {
      for (final l in lots) {
        final sel = l.key == _selected?.key;
        final foc = _focused(l);
        final inactive = repo.isAdmin && !repo.isActive(l);
        Color fill, border;
        double w;
        if (sel) {
          fill = Colors.red.withValues(alpha: 0.45);
          border = Colors.red;
          w = 3;
        } else if (inactive) {
          fill = Colors.grey.withValues(alpha: 0.35);
          border = Colors.grey;
          w = 1;
        } else if (!l.isLot) {
          fill = Colors.blueGrey.withValues(alpha: 0.25);
          border = Colors.blueGrey;
          w = 1;
        } else if (foc) {
          fill = Colors.amber.withValues(alpha: 0.5);
          border = Colors.orange.shade800;
          w = 2;
        } else {
          fill = Colors.green.withValues(alpha: 0.12);
          border = Colors.greenAccent.shade700;
          w = 1.2;
        }
        polygons.add(Polygon(
          points: l.ring,
          color: fill,
          borderColor: border,
          borderStrokeWidth: w,
        ));
      }
    }

    // Centres de lotissements : cercles jaunes (taille selon le nombre de lots), nom dès le zoom 15.
    final ltsCircles = <CircleMarker>[];
    final ltsLabels = <Marker>[];
    if (_showLts && _zoom >= 12) {
      const pad = 0.01;
      final labelStyle = const TextStyle(
        color: Colors.black,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1,
        shadows: [
          Shadow(color: Colors.white, offset: Offset(1, 0), blurRadius: 0),
          Shadow(color: Colors.white, offset: Offset(-1, 0), blurRadius: 0),
          Shadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 0),
          Shadow(color: Colors.white, offset: Offset(0, -1), blurRadius: 0),
        ],
      );
      for (final l in repo.lotissements) {
        if (vb != null &&
            (l.lat < vb.south - pad || l.lat > vb.north + pad || l.lon < vb.west - pad || l.lon > vb.east + pad)) {
          continue;
        }
        final r = _ltsRadius(l);
        ltsCircles.add(CircleMarker(
          point: LatLng(l.lat, l.lon),
          radius: r,
          color: const Color(0xFFFFD166).withValues(alpha: 0.85),
          borderColor: const Color(0xFF3B2B00),
          borderStrokeWidth: 1.5,
        ));
        if (_zoom >= 15 && ltsLabels.length < 80) {
          ltsLabels.add(Marker(
            point: LatLng(l.lat, l.lon),
            width: 280,
            height: 16,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 140 + r + 3),
                  child: Text(l.title, style: labelStyle, maxLines: 1, softWrap: false),
                ),
              ),
            ),
          ));
        }
      }
    }

    // Numéros de lot : dessinés ici (sans règle de taille), sur chaque lot visible.
    final labels = <Marker>[];
    if (_zoom >= AppConfig.labelMinZoom) {
      final fs = (8 + (_zoom - 17) * 2.5).clamp(8.0, 15.0);
      final style = TextStyle(
        color: Colors.black,
        fontSize: fs,
        fontWeight: FontWeight.w700,
        height: 1,
        shadows: const [
          Shadow(color: Colors.white, offset: Offset(1, 0), blurRadius: 0),
          Shadow(color: Colors.white, offset: Offset(-1, 0), blurRadius: 0),
          Shadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 0),
          Shadow(color: Colors.white, offset: Offset(0, -1), blurRadius: 0),
        ],
      );
      for (final l in lots) {
        if (!l.isLot || l.label == null) continue;
        labels.add(Marker(
          point: l.labelPoint,
          width: 56,
          height: fs + 4,
          child: IgnorePointer(
            child: Center(child: Text(l.label!, style: style, maxLines: 1, softWrap: false)),
          ),
        ));
        if (labels.length >= 1500) break;
      }
    }

    // Règle : étiquette de longueur au milieu de chaque segment.
    final measureMarkers = <Marker>[];
    for (var i = 1; i < _mpts.length; i++) {
      final a = _mpts[i - 1], b = _mpts[i];
      measureMarkers.add(Marker(
        point: LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2),
        width: 84,
        height: 26,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.deepOrange),
              ),
              child: Text(
                _fmtDist(_distance.as(LengthUnit.Meter, a, b)),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black),
              ),
            ),
          ),
        ),
      ));
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: AppConfig.center,
              initialZoom: 12.5,
              minZoom: 9,
              maxZoom: 20,
              onTap: _onTap,
              onLongPress: (tp, p) => _measuring ? _addMeasure(p) : _startMeasure(p),
              onPositionChanged: _onPosition,
              onMapReady: () {
                _ready = true;
                _bounds = _map.camera.visibleBounds;
                _zoom = _map.camera.zoom;
                final f = appState.takeFocus();
                if (f != null) _apply(f);
                setState(() {});
                _requestTiles();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _satellite ? AppConfig.satelliteTiles : AppConfig.osmTiles,
                userAgentPackageName: AppConfig.userAgent,
                maxNativeZoom: _satellite ? 18 : 19,
                maxZoom: 20,
              ),
              if (estPolys.isNotEmpty) PolygonLayer(polygons: estPolys),
              PolygonLayer(polygons: polygons),
              if (labels.isNotEmpty) MarkerLayer(markers: labels),
              if (ltsCircles.isNotEmpty) CircleLayer(circles: ltsCircles),
              if (ltsLabels.isNotEmpty) MarkerLayer(markers: ltsLabels),
              if (_route != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _route!.points,
                    strokeWidth: 5,
                    color: Colors.blue,
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.white,
                  ),
                ]),
              if (_mpts.length > 1)
                PolylineLayer(polylines: [
                  Polyline(
                    points: List<LatLng>.of(_mpts),
                    strokeWidth: 3,
                    color: Colors.deepOrange,
                    borderStrokeWidth: 1.5,
                    borderColor: Colors.white,
                  ),
                ]),
              if (_mpts.isNotEmpty)
                CircleLayer(circles: [
                  for (final q in _mpts)
                    CircleMarker(
                      point: q,
                      radius: 6,
                      color: Colors.deepOrange,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2,
                    ),
                ]),
              if (measureMarkers.isNotEmpty) MarkerLayer(markers: measureMarkers),
              if (_me != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _me!,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ]),
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution(_satellite ? 'Imagery © Esri' : '© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          // barre du haut : recherche + boutons flottants
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _searchPill(),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (_focus != null) _focusChip(),
                            if (repo.isAdmin) _adminChip(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _controls(),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_zoom < AppConfig.lotMinZoom && repo.lots.isNotEmpty && !_measuring)
            Positioned(left: 14, right: 74, bottom: 16, child: _legend()),
          if (_measuring)
            Positioned(left: 12, right: 12, bottom: 16, child: _measureBar()),
          if (_route != null && _selected == null && _selectedEst == null && !_measuring)
            Positioned(left: 12, right: 12, bottom: 16, child: _routeBar()),
          if (_selectedEst != null && !_measuring)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_route != null) _routeBar(),
                    if (_route != null) const SizedBox(height: 6),
                    EstLotCard(
                      lot: _selectedEst!,
                      routing: _routing,
                      onClose: () => setState(() => _selectedEst = null),
                      onRoute: () => _goRouteTo(_selectedEst!.centroid),
                    ),
                  ],
                ),
              ),
            ),
          if (_selected != null && !_measuring)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_route != null) _routeBar(),
                    if (_route != null) const SizedBox(height: 6),
                    LotCard(
                      lot: _selected!,
                      routing: _routing,
                      onClose: () => setState(() => _selected = null),
                      onRoute: () => _goRouteTo(_selected!.centroid),
                      onEdit: () => _edit(_selected!),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _measureBar() {
    final n = _mpts.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.text,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten, color: AppColors.sand, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              n < 2 ? 'Touchez le point suivant' : 'Distance : ${_fmtDist(_measureTotal)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: 'Annuler le dernier point',
            onPressed: _undoMeasure,
            icon: const Icon(Icons.undo, color: Colors.white),
          ),
          TextButton(
            onPressed: _endMeasure,
            style: TextButton.styleFrom(foregroundColor: AppColors.sand),
            child: const Text('Terminer'),
          ),
        ],
      ),
    );
  }

  Widget _routeBar() {
    final r = _route!;
    final km = r.meters / 1000;
    final min = (r.seconds / 60).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${km.toStringAsFixed(1).replaceAll('.', ',')} km · $min min',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _route = null),
            style: TextButton.styleFrom(foregroundColor: AppColors.sand),
            child: const Text('Terminer'),
          ),
        ],
      ),
    );
  }

  // ---------- éléments d'interface flottants (style calme, verre clair)
  BoxDecoration get _glass => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppShadows.tiny,
      );

  Widget _searchPill() => GestureDetector(
        onTap: _search,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: _glass,
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rechercher un lieu, un lot…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.muted, fontSize: 15.5),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _focusChip() => Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: AppColors.primarySoft.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.tiny,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(_focus!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: AppColors.primaryDark,
              onPressed: () => setState(() {
                _focus = null;
                _focusEstBlock = null;
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );

  Widget _adminChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.sand.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.tiny,
        ),
        child: const Text('Admin',
            style: TextStyle(color: AppColors.sandDark, fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _ctl(IconData icon, VoidCallback onTap, {bool active = false, String? tip}) => Tooltip(
        message: tip ?? '',
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 22, color: active ? AppColors.primary : AppColors.muted),
          ),
        ),
      );

  Widget _controls() => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.tiny,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ctl(_satellite ? Icons.map_outlined : Icons.satellite_alt_rounded,
                () => setState(() => _satellite = !_satellite),
                tip: _satellite ? 'Plan' : 'Satellite'),
            const Divider(height: 1, indent: 12, endIndent: 12),
            _ctl(Icons.my_location_rounded, _locate, tip: 'Ma position'),
            const Divider(height: 1, indent: 12, endIndent: 12),
            _ctl(_showLts ? Icons.location_on_rounded : Icons.location_off_outlined,
                () => setState(() => _showLts = !_showLts),
                active: _showLts, tip: 'Lotissements'),
            const Divider(height: 1, indent: 12, endIndent: 12),
            _ctl(Icons.straighten_rounded, _showRulerInfo, tip: 'Mesurer'),
          ],
        ),
      );

  Widget _legend() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.tiny,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Zoomez pour voir les terrains',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: AppColors.text)),
            const SizedBox(height: 6),
            Row(
              children: [
                _dot(Colors.green.shade600),
                const SizedBox(width: 6),
                const Text('Plan officiel', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(width: 14),
                _dot(AppColors.warm),
                const SizedBox(width: 6),
                const Text('Estimation', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ],
        ),
      );

  Widget _dot(Color c) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}
