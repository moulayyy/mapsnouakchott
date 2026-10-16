import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models.dart';
import '../repo.dart';
import '../services.dart';
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
  FocusRequest? _focus;
  LatLng? _me;
  RouteResult? _route;
  bool _routing = false;
  Timer? _debounce;

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
    if (mounted) setState(() {});
  }

  void _onApp() {
    if (_ready && appState.pendingFocus != null) {
      _apply(appState.takeFocus()!);
    }
  }

  // ---------- focus
  void _apply(FocusRequest f) {
    Lot? sel;
    if (f.selectKey != null) sel = repo.byKey[f.selectKey!];
    setState(() {
      _focus = (f.selectKey != null) ? null : f;
      _selected = sel;
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

  bool _focused(Lot l) {
    final f = _focus;
    if (f == null) return false;
    if (f.lotKeys != null) return f.lotKeys!.contains(l.key);
    if (f.plan != null) return l.plan == f.plan;
    if (f.moughataa != null) return repo.planOf(l)?.m == f.moughataa;
    return false;
  }

  bool _planFocused(Plan p) {
    final f = _focus;
    if (f == null) return false;
    if (f.plan != null) return p.idx == f.plan;
    if (f.moughataa != null) return p.m == f.moughataa;
    if (f.lotKeys != null) {
      return repo.lots.any((l) => l.plan == p.idx && f.lotKeys!.contains(l.key));
    }
    return false;
  }

  // ---------- interactions
  void _onPosition(MapCamera cam, bool gesture) {
    _zoom = cam.zoom;
    _bounds = cam.visibleBounds;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
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
    if (_zoom >= AppConfig.lotMinZoom) {
      for (final l in _visibleLots()) {
        if (l.contains(p)) {
          setState(() => _selected = l);
          return;
        }
      }
      setState(() => _selected = null);
      return;
    }
    for (final pl in repo.plans) {
      if (pl.containsPoint(p)) {
        _fitBox([pl.minLat, pl.minLon, pl.maxLat, pl.maxLon]);
        return;
      }
    }
    // lotissement le plus proche (index sans plan)
    Lotissement? best;
    var bestD = double.infinity;
    for (final l in repo.lotissements) {
      final d = (l.lat - p.latitude) * (l.lat - p.latitude) +
          (l.lon - p.longitude) * (l.lon - p.longitude);
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    final tol = 0.02 / (1 << (_zoom.floor() - 10).clamp(0, 10));
    if (best != null && bestD < tol * tol) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${best.title} — ${best.planLots} lots'
            '${best.hasPlan ? '' : ' (plan détaillé non disponible)'}'),
      ));
    }
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

  Future<void> _goRoute(Lot lot) async {
    setState(() => _routing = true);
    try {
      final me = await LocationService.current();
      final r = await Routing.fetch(me, lot.centroid);
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

    if (_zoom < AppConfig.lotMinZoom) {
      for (final p in repo.plans) {
        final foc = _planFocused(p);
        polygons.add(Polygon(
          points: p.rect,
          color: (foc ? Colors.amber : Colors.green).withValues(alpha: foc ? 0.45 : 0.25),
          borderColor: foc ? Colors.orange.shade800 : Colors.greenAccent.shade700,
          borderStrokeWidth: 2,
          label: _zoom >= 12.5 ? p.title : null,
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
          label: (_zoom >= 18 && l.isLot) ? l.label : null,
          labelStyle: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
        ));
      }
    }

    final dots = <CircleMarker>[];
    if (_zoom >= 11 && _zoom < AppConfig.lotMinZoom) {
      for (final l in repo.lotissements) {
        if (l.hasPlan) continue;
        dots.add(CircleMarker(
          point: LatLng(l.lat, l.lon),
          radius: 4,
          color: Colors.blue.withValues(alpha: 0.7),
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ));
      }
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
              onPositionChanged: _onPosition,
              onMapReady: () {
                _ready = true;
                _bounds = _map.camera.visibleBounds;
                _zoom = _map.camera.zoom;
                final f = appState.takeFocus();
                if (f != null) _apply(f);
                setState(() {});
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _satellite ? AppConfig.satelliteTiles : AppConfig.osmTiles,
                userAgentPackageName: AppConfig.userAgent,
                maxNativeZoom: _satellite ? 18 : 19,
                maxZoom: 20,
              ),
              CircleLayer(circles: dots),
              PolygonLayer(polygons: polygons),
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
          // barre du haut
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (_focus != null)
                          InputChip(
                            label: Text(_focus!.title),
                            onDeleted: () => setState(() => _focus = null),
                            backgroundColor: Colors.white,
                          ),
                        if (repo.isAdmin)
                          const Chip(label: Text('Admin'), backgroundColor: Colors.white),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      _fab(Icons.search, _search),
                      const SizedBox(height: 8),
                      _fab(_satellite ? Icons.map_outlined : Icons.satellite_alt,
                          () => setState(() => _satellite = !_satellite)),
                      const SizedBox(height: 8),
                      _fab(Icons.my_location, _locate),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_zoom < AppConfig.lotMinZoom && repo.lots.isNotEmpty)
            const Positioned(
              left: 12,
              right: 70,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Zoomez ou touchez une zone verte pour voir les terrains.',
                      textAlign: TextAlign.center),
                ),
              ),
            ),
          if (_route != null && _selected == null)
            Positioned(left: 12, right: 12, bottom: 16, child: _routeBar()),
          if (_selected != null)
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
                      onRoute: () => _goRoute(_selected!),
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

  Widget _routeBar() {
    final r = _route!;
    final km = r.meters / 1000;
    final min = (r.seconds / 60).round();
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Colors.blue.shade700,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.directions_car, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${km.toStringAsFixed(1).replaceAll('.', ',')} km · $min min',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _route = null),
              child: const Text('Terminer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fab(IconData icon, VoidCallback onTap) => Material(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon)),
        ),
      );
}
