import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Minuscules, sans accents, `_` -> espace : pour la recherche.
String norm(String s) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final c in s.toLowerCase().runes) {
    final ch = String.fromCharCode(c);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : (ch == '_' ? ' ' : ch));
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

String fmtNum(num v, {int decimals = 0}) {
  final s = v.toStringAsFixed(decimals);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ');
  return parts.length > 1 ? '$intPart,${parts[1]}' : intPart;
}

String fmtMeters(double v) {
  if ((v - v.round()).abs() < 0.05) return '${v.round()} m';
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} m';
}

class Moughataa {
  final int code;
  final String fr;
  final String ar;
  Moughataa(this.code, this.fr, this.ar);
}

class Plan {
  final int idx;
  final String plan;
  final String name;
  final int ltsId;
  final int m;
  final int n;
  final double? accuracy;
  final bool partial;
  final double minLat, minLon, maxLat, maxLon;
  Plan({
    required this.idx,
    required this.plan,
    required this.name,
    required this.ltsId,
    required this.m,
    required this.n,
    required this.accuracy,
    required this.partial,
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  factory Plan.fromJson(Map<String, dynamic> j) {
    final b = (j['b'] as List).map((e) => (e as num).toDouble()).toList();
    return Plan(
      idx: j['idx'] as int,
      plan: j['plan'] as String,
      name: j['name'] as String,
      ltsId: j['ltsId'] as int,
      m: j['m'] as int,
      n: j['n'] as int,
      accuracy: (j['acc'] as num?)?.toDouble(),
      partial: j['partial'] == true,
      minLat: b[0],
      minLon: b[1],
      maxLat: b[2],
      maxLon: b[3],
    );
  }

  String get title => name.replaceAll('_', ' ');
  List<LatLng> get rect => [
        LatLng(minLat, minLon),
        LatLng(minLat, maxLon),
        LatLng(maxLat, maxLon),
        LatLng(maxLat, minLon),
      ];
  bool containsPoint(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLon &&
      p.longitude <= maxLon;
}

class Lotissement {
  final int id;
  final String name;
  final int m;
  final int planLots;
  final double lat;
  final double lon;
  final int planIdx; // -1 si aucun plan de lots
  Lotissement(this.id, this.name, this.m, this.planLots, this.lat, this.lon,
      this.planIdx);

  factory Lotissement.fromRow(List r) => Lotissement(
        r[0] as int,
        r[1] as String,
        r[2] as int,
        (r[3] as num).toInt(),
        (r[4] as num).toDouble(),
        (r[5] as num).toDouble(),
        r[6] as int,
      );

  String get title => name.replaceAll('_', ' ');
  bool get hasPlan => planIdx >= 0;
}

/// Bloc (îlot) : groupe de lots voisins, contour = enveloppe des lots.
class Block {
  final int plan;
  final int n;
  final int count;
  final int? lo;
  final int? hi;
  final List<LatLng> ring;
  final double minLat, minLon, maxLat, maxLon;

  Block._(this.plan, this.n, this.count, this.lo, this.hi, this.ring, this.minLat,
      this.minLon, this.maxLat, this.maxLon);

  /// Ligne : [plan, n, count, lo, hi, ring(lon,lat plat)]
  factory Block.fromRow(List r) {
    final flat = (r[5] as List).map((e) => (e as num).toDouble()).toList();
    final pts = <LatLng>[];
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (var i = 0; i + 1 < flat.length; i += 2) {
      pts.add(LatLng(flat[i + 1], flat[i]));
      minLat = math.min(minLat, flat[i + 1]);
      maxLat = math.max(maxLat, flat[i + 1]);
      minLon = math.min(minLon, flat[i]);
      maxLon = math.max(maxLon, flat[i]);
    }
    return Block._(
      (r[0] as num).toInt(),
      (r[1] as num).toInt(),
      (r[2] as num).toInt(),
      (r[3] as num?)?.toInt(),
      (r[4] as num?)?.toInt(),
      pts,
      minLat,
      minLon,
      maxLat,
      maxLon,
    );
  }

  String get title => 'Bloc $n';
  String get range => (lo != null && hi != null && lo != hi)
      ? 'lots $lo à $hi · $count lots'
      : '$count lot${count > 1 ? 's' : ''}';
  List<double> get bbox => [minLat, minLon, maxLat, maxLon];

  bool contains(LatLng p) {
    if (p.latitude < minLat || p.latitude > maxLat || p.longitude < minLon || p.longitude > maxLon) {
      return false;
    }
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
}

class Lot {
  final String key;
  final String? label;
  final int kind;
  final double area;
  final String? status;
  final String? name;
  final int plan;
  final int? block; // n° de bloc (îlot) dans le plan, null si équipement
  final String chunk;
  final List<LatLng> ring;
  final List<dynamic> raw;
  final double minLat, maxLat, minLon, maxLon;

  Lot._({
    required this.key,
    required this.label,
    required this.kind,
    required this.area,
    required this.status,
    required this.name,
    required this.plan,
    required this.block,
    required this.chunk,
    required this.ring,
    required this.raw,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  /// Ligne : [key,label,kind,area,status,name,ring(lon,lat plat)]
  factory Lot.fromRow(List row, int plan, String chunk) {
    final flat = (row[6] as List).map((e) => (e as num).toDouble()).toList();
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
    return Lot._(
      key: row[0] as String,
      label: row[1] as String?,
      kind: (row[2] as num).toInt(),
      area: (row[3] as num).toDouble(),
      status: row[4] as String?,
      name: row[5] as String?,
      plan: plan,
      block: row.length > 7 ? (row[7] as num?)?.toInt() : null,
      chunk: chunk,
      ring: pts,
      raw: row,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
    );
  }

  bool get isLot => kind == 0;
  String get display => label ?? name ?? '—';

  /// Centre de gravité du polygone (pour placer le numéro), repli : moyenne des sommets.
  late final LatLng labelPoint = _areaCentroid();

  LatLng _areaCentroid() {
    final n = ring.length;
    if (n < 3) return centroid;
    final lat0 = ring[0].latitude, lon0 = ring[0].longitude;
    var a = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < n; i++) {
      final p = ring[i], q = ring[(i + 1) % n];
      final x1 = p.longitude - lon0, y1 = p.latitude - lat0;
      final x2 = q.longitude - lon0, y2 = q.latitude - lat0;
      final f = x1 * y2 - x2 * y1;
      a += f;
      cx += (x1 + x2) * f;
      cy += (y1 + y2) * f;
    }
    if (a.abs() < 1e-14) return centroid;
    return LatLng(lat0 + cy / (3 * a), lon0 + cx / (3 * a));
  }

  LatLng get centroid {
    var la = 0.0, lo = 0.0;
    for (final p in ring) {
      la += p.latitude;
      lo += p.longitude;
    }
    return LatLng(la / ring.length, lo / ring.length);
  }

  bool contains(LatLng p) {
    if (p.latitude < minLat ||
        p.latitude > maxLat ||
        p.longitude < minLon ||
        p.longitude > maxLon) {
      return false;
    }
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Longueurs des côtés (sommets alignés fusionnés).
  List<double> get dimensions {
    var pts = List<LatLng>.from(ring);
    if (pts.length > 1 &&
        pts.first.latitude == pts.last.latitude &&
        pts.first.longitude == pts.last.longitude) {
      pts.removeLast();
    }
    if (pts.length < 3) return [];
    final lat0 = pts.first.latitude, lon0 = pts.first.longitude;
    final kx = 111320.0 * math.cos(lat0 * math.pi / 180);
    const ky = 110574.0;
    final xy = pts
        .map((p) => [(p.longitude - lon0) * kx, (p.latitude - lat0) * ky])
        .toList();
    final n = xy.length;
    final corners = <int>[];
    for (var i = 0; i < n; i++) {
      final p0 = xy[(i - 1 + n) % n], p1 = xy[i], p2 = xy[(i + 1) % n];
      final ax = p1[0] - p0[0], ay = p1[1] - p0[1];
      final bx = p2[0] - p1[0], by = p2[1] - p1[1];
      final cross = ax * by - ay * bx;
      final dot = ax * bx + ay * by;
      final ang = math.atan2(cross, dot).abs();
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
}

/// Autorisations d'un compte employé. À compléter quand les droits seront définis :
/// ajouter une entrée ici (et la vérifier dans les règles Firestore).
const kPermissions = <String, String>{
  'demandes': 'Voir et répondre aux demandes des clients',
  'chat': 'Répondre aux messages du chat',
};

class LotDetail {
  bool active;
  String? offer; // 'vente' | 'location' | null
  String? construction; // 'libre' | 'construit' | null
  num? price;
  String description;
  List<String> photos;

  LotDetail({
    this.active = true,
    this.offer,
    this.construction,
    this.price,
    this.description = '',
    List<String>? photos,
  }) : photos = photos ?? [];

  factory LotDetail.fromMap(Map<String, dynamic>? m) {
    if (m == null) return LotDetail();
    return LotDetail(
      active: m['active'] != false,
      offer: m['offer'] as String?,
      construction: m['construction'] as String?,
      price: m['price'] as num?,
      description: (m['description'] as String?) ?? '',
      photos: ((m['photos'] as List?) ?? const []).cast<String>().toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'active': active,
        'offer': offer,
        'construction': construction,
        'price': price,
        'description': description,
        'photos': photos,
      };

  LotDetail copy() => LotDetail(
        active: active,
        offer: offer,
        construction: construction,
        price: price,
        description: description,
        photos: List<String>.from(photos),
      );
}
