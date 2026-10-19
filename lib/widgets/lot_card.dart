import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models.dart';
import '../repo.dart';
import '../services.dart';
import '../theme.dart';
import 'ui.dart';

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
    final team = repo.isAdmin || repo.isStaff;
    return SheetShell(
      child: FutureBuilder<LotDetail>(
        key: ValueKey(lot.key),
        future: lot.isLot ? repo.getDetail(lot.key) : null,
        builder: (context, snap) => _content(context, snap.data, team),
      ),
    );
  }

  Widget _content(BuildContext context, LotDetail? d, bool team) {
    final dims = lot.dimensions;
    final isAd = d != null && d.active && d.offer != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                lot.isLot
                    ? 'Lot ${lot.display}'
                    : '${repo.kindLabel(lot)}${lot.name != null ? ' — ${lot.name}' : ''}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            SoftCloseButton(onTap: onClose),
          ],
        ),
        const SizedBox(height: 2),
        Text('${repo.lotissementName(lot)} · ${repo.moughataaName(lot)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        if (d != null && d.offer != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Badge2(d.offer == 'location' ? 'Location' : 'Vente',
                  bg: AppColors.primary, fg: Colors.white),
              if (d.construction != null) ...[
                const SizedBox(width: 6),
                Badge2(d.construction == 'libre' ? 'Terrain libre' : 'Construit',
                    bg: AppColors.sand, fg: AppColors.sandDark),
              ],
            ],
          ),
          if (d.price != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${fmtNum(d.price!)} ${AppConfig.currency}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: AppColors.primary)),
            ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: InfoTile(
                  icon: Icons.square_foot_rounded,
                  label: 'Superficie',
                  value: '${fmtNum(lot.area, decimals: 0)} m²'),
            ),
            if (lot.block != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: InfoTile(
                    icon: Icons.grid_view_rounded, label: 'Bloc', value: '${lot.block}'),
              ),
            ],
          ],
        ),
        if (dims.isNotEmpty) ...[
          const SizedBox(height: 10),
          InfoTile(
              icon: Icons.straighten_rounded,
              label: 'Dimensions',
              value: dims.map(fmtMeters).join('  ·  ')),
        ],
        if (d != null && d.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(d.description, style: const TextStyle(fontSize: 14.5, height: 1.4)),
        ],
        if (repo.isAdmin) ...[
          const SizedBox(height: 8),
          if (lot.status != null) kvRow('Statut', lot.status!),
          if (d != null && !d.active)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Désactivé : invisible pour les clients.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ),
          if (repo.owners[lot.key] != null) kvRow('Propriétaire', repo.owners[lot.key]!),
          if (repo.ownerNotes[lot.key] != null) kvRow('Note', repo.ownerNotes[lot.key]!),
        ],
        if (d != null && d.photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final u in d.photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(u))),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(u, width: 124, height: 92, fit: BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
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
              onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText)),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Partager'),
            ),
            if (lot.isLot && !team && isAd)
              OutlinedButton.icon(
                onPressed: () => appState.openChat(
                    draft: 'Bonjour, je suis intéressé par le lot ${lot.display} '
                        '(${repo.lotissementName(lot)}, ${repo.moughataaName(lot)}).'),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Nous contacter'),
              ),
            if (repo.isAdmin && lot.isLot)
              FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Modifier'),
              ),
          ],
        ),
      ],
    );
  }
}
