import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models.dart';
import '../repo.dart';
import '../services.dart';

class LotCard extends StatelessWidget {
  final Lot lot;
  final VoidCallback onClose;
  final VoidCallback onRoute;
  final VoidCallback onEdit;
  final bool routing;

  const LotCard({
    super.key,
    required this.lot,
    required this.onClose,
    required this.onRoute,
    required this.onEdit,
    required this.routing,
  });

  String get _shareText {
    final c = lot.centroid;
    return '${lot.isLot ? 'Lot ${lot.display}' : lot.display} — ${repo.lotissementName(lot)} '
        '(${repo.moughataaName(lot)}) — ${fmtNum(lot.area)} m²\n'
        'https://www.openstreetmap.org/?mlat=${c.latitude.toStringAsFixed(6)}&mlon=${c.longitude.toStringAsFixed(6)}#map=19/${c.latitude.toStringAsFixed(6)}/${c.longitude.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final dims = lot.dimensions;
    final h = MediaQuery.of(context).size.height;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.55),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lot.isLot ? 'Lot : ${lot.display}' : '${repo.kindLabel(lot)}${lot.name != null ? ' — ${lot.name}' : ''}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
                ],
              ),
              _row('Superficie', '${fmtNum(lot.area, decimals: 0)} m²'),
              _row('Moughataa', repo.moughataaName(lot)),
              _row('Lotissement', repo.lotissementName(lot)),
              if (dims.isNotEmpty) _row('Dimensions', dims.map(fmtMeters).join(', ')),
              if (repo.isAdmin && lot.status != null) _row('Statut (admin)', lot.status!),
              if (lot.isLot) _Detail(lot: lot),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: routing ? null : onRoute,
                    icon: routing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.directions),
                    label: const Text('Itinéraire'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText)),
                    icon: const Icon(Icons.share),
                    label: const Text('Partager'),
                  ),
                  if (lot.isLot)
                    OutlinedButton.icon(
                      onPressed: () => appState.openChat(
                          draft: 'Bonjour, je suis intéressé par le lot ${lot.display} '
                              '(${repo.lotissementName(lot)}, ${repo.moughataaName(lot)}).'),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Nous contacter'),
                    ),
                  if (repo.isAdmin && lot.isLot)
                    FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit),
                      label: const Text('Modifier'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k : ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: v),
        ])),
      );
}

class _Detail extends StatelessWidget {
  final Lot lot;
  const _Detail({required this.lot});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LotDetail>(
      key: ValueKey(lot.key),
      future: repo.getDetail(lot.key),
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox(height: 4);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.offer != null && d.price != null)
              LotCard._row(d.offer == 'location' ? 'Location' : 'Vente',
                  '${fmtNum(d.price!)} ${AppConfig.currency}'),
            if (d.description.isNotEmpty) LotCard._row('Description', d.description),
            if (repo.isAdmin) ...[
              if (!d.active)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text('Désactivé : invisible pour les clients.',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                ),
              if (repo.owners[lot.key] != null)
                LotCard._row('Propriétaire (admin)', repo.owners[lot.key]!),
              if (repo.ownerNotes[lot.key] != null)
                LotCard._row('Note (admin)', repo.ownerNotes[lot.key]!),
            ],
            if (d.photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final u in d.photos)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: InteractiveViewer(child: Image.network(u)),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(u, width: 120, height: 90, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
