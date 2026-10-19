import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../est_models.dart';
import '../models.dart';
import '../repo.dart';
import '../theme.dart';
import 'ui.dart';

class EstLotCard extends StatelessWidget {
  final EstLot lot;
  final VoidCallback onClose;
  final VoidCallback onRoute;
  final bool routing;

  const EstLotCard({
    super.key,
    required this.lot,
    required this.onClose,
    required this.onRoute,
    required this.routing,
  });

  static const _poiLabels = {
    'school': 'École',
    'health': 'Santé',
    'pharmacy': 'Pharmacie',
    'mosque': 'Mosquée',
    'market': 'Marché',
  };
  static const _streetClassFr = {
    'trunk': 'artère',
    'primary': 'principale',
    'secondary': 'secondaire',
    'tertiary': 'tertiaire',
    'residential': 'résidentielle',
    'unclassified': 'non classée',
    'service': 'desserte',
    'track': 'piste',
    'path': 'sentier',
    'footway': 'piétonne',
  };

  static String _dist(int m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '$m m';

  @override
  Widget build(BuildContext context) {
    final blk = repo.estBlockById[lot.block];
    final m = blk == null ? null : repo.moughataa(blk.m);
    final lts = blk?.lts == null
        ? null
        : repo.lotissements.where((l) => l.id == blk!.lts).cast<Lotissement?>().firstOrNull;
    final quartier = repo.estQuartier(blk?.quartier);
    final street = repo.estStreet(lot);
    final sclass = (lot.streetClass != null &&
            repo.est != null &&
            lot.streetClass! < repo.est!.streetClasses.length)
        ? repo.est!.streetClasses[lot.streetClass!]
        : '';
    final dims = lot.dimensions;
    final c = lot.centroid;
    final poi = repo.est?.poi ?? const <String>[];
    final prox = <String>[];
    for (var k = 0; k < poi.length && k < lot.dist.length; k++) {
      final d = lot.dist[k];
      if (d != null) prox.add('${_poiLabels[poi[k]] ?? poi[k]} ${_dist(d)}');
    }
    return SheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Parcelle estimée',
                        style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    Text(lot.label, style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
              SoftCloseButton(onTap: onClose),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warm.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.sandDark),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Estimation d\'après les rues et le bâti — sans valeur juridique.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.sandDark)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InfoTile(
                    icon: Icons.square_foot_rounded,
                    label: 'Superficie',
                    value: '≈ ${fmtNum(lot.area)} m²'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InfoTile(
                    icon: Icons.grid_view_rounded, label: 'Îlot', value: 'B${lot.block}'),
              ),
            ],
          ),
          if (dims.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoTile(
                icon: Icons.straighten_rounded,
                label: 'Dimensions',
                value: dims.map(fmtMeters).join('  ·  ')),
          ],
          const SizedBox(height: 8),
          if (m != null) kvRow('Moughataa', m.fr),
          if (lts != null) kvRow('Lotissement', '${lts.title} (probable)'),
          if (quartier.isNotEmpty) kvRow('Quartier', quartier),
          if (street.isNotEmpty)
            kvRow('Rue',
                sclass.isEmpty ? street : '$street · voie ${_streetClassFr[sclass] ?? sclass}'),
          if (lot.altDm != null)
            kvRow('Altitude',
                '≈ ${(lot.altDm! / 10).toStringAsFixed(1).replaceAll('.', ',')} m (indicatif)'),
          if (prox.isNotEmpty) kvRow('À proximité', prox.join(' · ')),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: routing ? null : onRoute,
                icon: routing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.directions_rounded),
                label: const Text('Itinéraire'),
              ),
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(
                    text: 'Parcelle estimée ${lot.label} — ≈ ${fmtNum(lot.area)} m²'
                        '${m != null ? ' (${m.fr})' : ''}\n'
                        'https://www.openstreetmap.org/?mlat=${c.latitude.toStringAsFixed(6)}&mlon=${c.longitude.toStringAsFixed(6)}#map=19/${c.latitude.toStringAsFixed(6)}/${c.longitude.toStringAsFixed(6)}')),
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Partager'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
