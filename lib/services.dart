import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'config.dart';

/// Demande de mise au point de la carte (recherche, propriétaire, offre...).
class FocusRequest {
  final String title;
  final int? moughataa;
  final int? plan;
  final int? block;
  final int? estBlock; // îlot estimé (n° B…)
  final int? estLot; // parcelle estimée (n° P…)
  final Set<String>? lotKeys;
  final String? selectKey;
  final LatLng? point;
  final List<double>? bbox; // minLat, minLon, maxLat, maxLon

  const FocusRequest({
    required this.title,
    this.moughataa,
    this.plan,
    this.block,
    this.estBlock,
    this.estLot,
    this.lotKeys,
    this.selectKey,
    this.point,
    this.bbox,
  });
}

class AppState extends ChangeNotifier {
  // 0 = Carte, 1 = Annonces, 2 = Chat, 3 = Paramètres
  int tab = 0;
  FocusRequest? pendingFocus;
  String? chatDraft;

  void openMap(FocusRequest f) {
    pendingFocus = f;
    tab = 0;
    notifyListeners();
  }

  void openChat({String? draft}) {
    chatDraft = draft;
    tab = 2;
    notifyListeners();
  }

  void setTab(int t) {
    tab = t;
    notifyListeners();
  }

  FocusRequest? takeFocus() {
    final f = pendingFocus;
    pendingFocus = null;
    return f;
  }

  String? takeDraft() {
    final d = chatDraft;
    chatDraft = null;
    return d;
  }
}

final appState = AppState();

class AuthService {
  static final _auth = FirebaseAuth.instance;

  /// Garde uniquement les chiffres, retire l'indicatif 222.
  static String normalizePhone(String p) {
    var d = p.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('222') && d.length > 8) d = d.substring(3);
    return d;
  }

  static String emailFor(String phone) =>
      '${normalizePhone(phone)}@${AppConfig.emailDomain}';

  static String phoneOf(User u) => (u.email ?? '').split('@').first;

  static Future<void> signIn(String phone, String password) async {
    await _auth.signInWithEmailAndPassword(
        email: emailFor(phone), password: password);
  }

  static Future<void> register(String name, String phone, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: emailFor(phone), password: password);
    final u = cred.user!;
    await u.updateDisplayName(name);
    await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
      'name': name,
      'phone': normalizePhone(phone),
      'createdAt': Timestamp.now(),
    });
  }

  static Future<bool> isAdmin(String uid) async {
    try {
      final s = await FirebaseFirestore.instance.collection('admins').doc(uid).get();
      return s.exists;
    } catch (_) {
      return false;
    }
  }

  /// Fiche employé si le compte en a une et qu'elle est active, sinon null.
  static Future<Map<String, dynamic>?> staffInfo(String uid) async {
    try {
      final s = await FirebaseFirestore.instance.collection('staff').doc(uid).get();
      final d = s.data();
      if (d == null || d['active'] != true) return null;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// Crée un compte employé sans déconnecter l'admin (2e instance Firebase),
  /// puis enregistre sa fiche `staff/{uid}`.
  static Future<void> createStaff({
    required String name,
    required String phone,
    required String password,
    required List<String> permissions,
  }) async {
    FirebaseApp secondary;
    try {
      secondary = Firebase.app('staffCreator');
    } catch (_) {
      secondary = await Firebase.initializeApp(
          name: 'staffCreator', options: Firebase.app().options);
    }
    final auth2 = FirebaseAuth.instanceFor(app: secondary);
    final cred = await auth2.createUserWithEmailAndPassword(
        email: emailFor(phone), password: password);
    final uid = cred.user!.uid;
    await cred.user!.updateDisplayName(name);
    await auth2.signOut();
    await FirebaseFirestore.instance.collection('staff').doc(uid).set({
      'name': name,
      'phone': normalizePhone(phone),
      'permissions': permissions,
      'active': true,
      'createdAt': Timestamp.now(),
    });
  }

  static Future<void> signOut() => _auth.signOut();

  static String message(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-email':
          return 'Téléphone ou mot de passe incorrect.';
        case 'email-already-in-use':
          return 'Ce numéro est déjà inscrit.';
        case 'weak-password':
          return 'Mot de passe trop court (6 caractères minimum).';
        case 'network-request-failed':
          return 'Pas de connexion internet.';
        case 'too-many-requests':
          return 'Trop de tentatives. Réessayez plus tard.';
        case 'operation-not-allowed':
          return 'Connexion par email non activée dans Firebase.';
      }
      return 'Erreur : ${e.code}';
    }
    return e.toString();
  }
}

class RouteResult {
  final List<LatLng> points;
  final double meters;
  final double seconds;
  RouteResult(this.points, this.meters, this.seconds);
}

class Routing {
  static Future<RouteResult> fetch(LatLng from, LatLng to) async {
    final url = Uri.parse(
        '${AppConfig.routingBase}/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson');
    final r = await http
        .get(url, headers: {'User-Agent': AppConfig.userAgent})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Itinéraire indisponible (${r.statusCode}).');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final routes = j['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw Exception('Aucun itinéraire trouvé.');
    }
    final route = routes.first as Map<String, dynamic>;
    final coords = (route['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    coords.add(to);
    return RouteResult(coords, (route['distance'] as num).toDouble(),
        (route['duration'] as num).toDouble());
  }
}

class LocationService {
  static Future<LatLng> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Activez la localisation du téléphone.');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      throw Exception('Autorisation de localisation refusée.');
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    return LatLng(pos.latitude, pos.longitude);
  }
}
