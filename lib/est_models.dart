import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Longueurs des côtés d'un polygone (sommets alignés fusionnés).
List<double> ringDimensions(List<LatLng> ring) {
  final pts = List<LatLng>.from(ring);
  if (pts.length > 1 &&
      pts.first.latitude == pts.last.latitude &&
      pts.first.longitude == pts.last.longitude) {
    pts.removeLast();
  }
  if (pts.length < 3) return [];
  final lat0 = pts.first.latitude, lon0 = pts.first.longitude;
  final kx = 111320.0 * math.cos(lat0 * math.pi / 180);
  const ky = 110574.0;
  final xy = pts.map((p) => [(p.longitude - lon0) * kx, (p.latitude - lat0) * ky]).toList();
  final n = xy.length;
  final corners = <int>[];
  for (var i = 0; i < n; i++) {
    final p0 = xy[(i - 1 + n) % n], p1 = xy[i], p2 = xy[(i + 1) % n];
    final ax = p1[0] - p0[0], ay = p1[1] - p0[1];
    final bx = p2[0] - p1[0], by = p2[1] - p1[1];
    final ang = math.atan2(ax * by - ay * bx, ax * bx + ay * by).abs();
    if (ang > 10 * math.pi / 180) corners.add(i);
  }
  if (corners.length < 3) return [];
  final out = <double>[];
  for (var c = 0; c < corners.length; c++) {
    final a = xy[corners[c]], b = xy[corners[(c + 1) % corners.length]];
    final dx = b[0] - a[0], dy = b[1] - a[1];
    out.add(math.sqrt(dx * dx + dy * dy));
  }
  return out;
}

bool _pip(LatLng p, List<LatLng> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) +
                a.longitude) {
      inside = !inside;
    }
  }
  return inside;
}

/// Index des parcelles estimées : grille de tuiles, listes de noms.
class EstMeta {
  final double aoiW, aoiS, tileDeg;
  final Set<String> tiles;
  final List<String> streetNames, streetClasses;
  final List<List<String>> quartiers;
  final List<String> poi;

  EstMeta({
    required this.aoiW,
    required this.aoiS,
    required this.tileDeg,
    required this.tiles,
    required this.streetNames,
    required this.streetClasses,
    required this.quartiers,
    required this.poi,
  });

  factory EstMeta.fromJson(Map<String, dynamic> j) {
    final aoi = (j['aoi'] as List).map((e) => (e as num).toDouble()).toList();
    return EstMeta(
      aoiW: aoi[0],
      aoiS: aoi[1],
      tileDeg: (j['tileDeg'] as num).toDouble(),
      tiles: (j['tiles'] as List).cast<String>().toSet(),
      streetNames: (j['streetNames'] as List).cast<String>(),
      streetClasses: (j['streetClasses'] as List).cast<String>(),
      quartiers: (j['quartiers'] as List)
          .map((q) => (q as List).map((e) => (e ?? '') as String).toList())
          .toList(),
      poi: (j['poi'] as List).cast<String>(),
    );
  }

  String tileKey(double lat, double lon) =>
      '${((lon - aoiW) / tileDeg).floor()}_${((lat - aoiS) / tileDeg).floor()}';

  /// Clés des tuiles existantes qui touchent la zone.
  List<String> tilesIn(double south, double west, double north, double east) {
    final x0 = ((west - aoiW) / tileDeg).floor(), x1 = ((east - aoiW) / tileDeg).floor();
    final y0 = ((south - aoiS) / tileDeg).floor(), y1 = ((north - aoiS) / tileDeg).floor();
    final out = <String>[];
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final k = '${x}_$y';
        if (tiles.contains(k)) out.add(k);
      }
    }
    return out;
  }
}

/// Îlot estimé.
/// Ligne : [id, m, tier, module, src, nb, area, regular, first, last, galt, quartier, lts, mCorr, inCert, ring]
class EstBlock {
  final int id, m, first, last;
  final double area;
  final int nb;
  final int? galt, quartier, lts;
  final bool mCorr, inCert;
  final List<LatLng> ring;
  final double minLat, minLon, maxLat, maxLon;

  EstBlock._(this.id, this.m, this.first, this.last, this.area, this.nb, this.galt,
      this.quartier, this.lts, this.mCorr, this.inCert, this.ring, this.minLat,
      this.minLon, this.maxLat, this.maxLon);

  factory EstBlock.fromRow(List r) {
    final flat = (r[15] as List).map((e) => (e as num).toDouble()).toList();
    final pts = <LatLng>[];
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final lon = flat[i], lat = flat[i + 1];
      pts.add(LatLng(lat, lon));
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
      minLon = math.min(minLon, lon);
      maxLon = math.max(maxLon, lon);
    }
    return EstBlock._(
      (r[0] as num).toInt(),
      (r[1] as num).toInt(),
      (r[8] as num?)?.toInt() ?? 0,
      (r[9] as num?)?.toInt() ?? 0,
      (r[6] as num).toDouble(),
      (r[5] as num?)?.toInt() ?? 0,
      (r[10] as num?)?.toInt(),
      (r[11] as num?)?.toInt(),
      (r[12] as num?)?.toInt(),
      (r[13] as num?) != null && (r[13] as num) != 0,
      (r[14] as num?) != null && (r[14] as num) != 0,
      pts,
      minLat,
      minLon,
      maxLat,
      maxLon,
    );
  }

  String get label => 'B$id';
  int get lotCount => first > 0 ? last - first + 1 : 0;
  List<double> get bbox => [minLat, minLon, maxLat, maxLon];
  bool contains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLon &&
      p.longitude <= maxLon &&
      _pip(p, ring);
}

/// Parcelle estimée (sans valeur juridique).
/// Ligne : [lot, blk, area, mod, src, nb, frDm, dpDm, row, col, altDm, sname, sclass, d0..d4, ring]
class EstLot {
  final int id, block, nb, row, col;
  final double area;
  final int? altDm, streetName, streetClass;
  final List<int?> dist;
  final List<LatLng> ring;
  final double minLat, minLon, maxLat, maxLon;

  EstLot._(this.id, this.block, this.nb, this.row, this.col, this.area, this.altDm,
      this.streetName, this.streetClass, this.dist, this.ring, this.minLat, this.minLon,
      this.maxLat, this.maxLon);

  factory EstLot.fromRow(List r, double ox, double oy) {
    final flat = (r[18] as List).map((e) => (e as num).toDouble()).toList();
    final pts = <LatLng>[];
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final lon = ox + flat[i] / 1e6, lat = oy + flat[i + 1] / 1e6;
      pts.add(LatLng(lat, lon));
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
      minLon = math.min(minLon, lon);
      maxLon = math.max(maxLon, lon);
    }
    return EstLot._(
      (r[0] as num).toInt(),
      (r[1] as num).toInt(),
      (r[5] as num?)?.toInt() ?? -1,
      (r[8] as num?)?.toInt() ?? 0,
      (r[9] as num?)?.toInt() ?? 0,
      (r[2] as num).toDouble(),
      (r[10] as num?)?.toInt(),
      (r[11] as num?)?.toInt(),
      (r[12] as num?)?.toInt(),
      [for (var k = 13; k < 18; k++) (r[k] as num?)?.toInt()],
      pts,
      minLat,
      minLon,
      maxLat,
      maxLon,
    );
  }

  String get label => 'P$id';
  List<double> get bbox => [minLat, minLon, maxLat, maxLon];
  List<double> get dimensions => ringDimensions(ring);

  LatLng get centroid {
    var la = 0.0, lo = 0.0;
    for (final p in ring) {
      la += p.latitude;
      lo += p.longitude;
    }
    return LatLng(la / ring.length, lo / ring.length);
  }

  bool contains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLon &&
      p.longitude <= maxLon &&
      _pip(p, ring);
}
