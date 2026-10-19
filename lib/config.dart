import 'package:latlong2/latlong.dart';

class AppConfig {
  static const appName = 'MapsNouakchott';

  /// Domaine du faux email créé à partir du numéro de téléphone.
  static const emailDomain = 'phone.mapsnouakchott.app';

  /// Fonds de carte. ATTENTION : le serveur OSM public est réservé au
  /// développement ; en production, prendre un fournisseur de tuiles
  /// (MapTiler, Stadia...) ou héberger ses propres tuiles.
  static const osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const satelliteTiles =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Routage. Le serveur de démo OSRM n'est pas prévu pour la production
  /// (remplacer par OpenRouteService / un OSRM auto-hébergé).
  static const routingBase = 'https://router.project-osrm.org';

  static const userAgent = 'com.haddou.mapsnouakchott';
  static const currency = 'MRU';
  static const center = LatLng(18.0866, -15.9785);
  static const lotMinZoom = 15.0;
  static const labelMinZoom = 17.0;
}
