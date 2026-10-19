import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../repo.dart';
import '../services.dart';
import 'chat_pages.dart';

/// Onglet Annonces : une annonce = un lot avec une offre (vente / location) publiée par l'admin.
class ListingsPage extends StatefulWidget {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage> {
  late Future<List<MapEntry<String, LotDetail>>> _f;
  String _filter = 'tous';
  int _lastTab = -1;

  @override
  void initState() {
    super.initState();
    _f = repo.loadOffers();
    appState.addListener(_onTab);
  }

  @override
  void dispose() {
    appState.removeListener(_onTab);
    super.dispose();
  }

  // Recharge à chaque ouverture de l'onglet (index 1).
  void _onTab() {
    if (appState.tab == 1 && _lastTab != 1) {
      setState(() => _f = repo.loadOffers());
    }
    _lastTab = appState.tab;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Annonces')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'tous', label: Text('Toutes')),
                ButtonSegment(value: 'vente', label: Text('Ventes')),
                ButtonSegment(value: 'location', label: Text('Locations')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MapEntry<String, LotDetail>>>(
              future: _f,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) return Center(child: Text('${snap.error}'));
                final items = snap.data!
                    .where((e) => _filter == 'tous' || e.value.offer == _filter)
                    .where((e) => repo.byKey.containsKey(e.key))
                    .toList();
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _f = repo.loadOffers());
                    await _f;
                  },
                  child: items.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Aucune annonce pour le moment.')),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _AnnonceCard(
                            lot: repo.byKey[items[i].key]!,
                            detail: items[i].value,
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnonceCard extends StatelessWidget {
  final Lot lot;
  final LotDetail detail;
  const _AnnonceCard({required this.lot, required this.detail});

  bool get _clientView => !(repo.canChat || repo.canRequests);

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k : ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: v),
        ])),
      );

  Future<void> _contact(BuildContext context) async {
    final price = detail.price == null ? '' : ' à ${fmtNum(detail.price!)} ${AppConfig.currency}';
    final text = 'Bonjour, je suis intéressé par l\'annonce : lot ${lot.display} '
        '(${repo.lotissementName(lot)}, ${repo.moughataaName(lot)}), '
        '${detail.offer == 'location' ? 'location' : 'vente'}$price. '
        'Pouvez-vous me contacter ?';
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ContactSheet(initialText: text),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Message envoyé à l\'agence.'),
        action: SnackBarAction(label: 'Ouvrir le chat', onPressed: appState.openChat),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dims = lot.dimensions;
    final isRent = detail.offer == 'location';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhotoCarousel(photos: detail.photos),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: Text(isRent ? 'Location' : 'Vente'),
                      backgroundColor: isRent ? cs.secondaryContainer : cs.primaryContainer,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 6),
                    if (detail.construction != null)
                      Chip(
                        label: Text(detail.construction == 'libre'
                            ? 'Terrain libre'
                            : 'Construit'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                Text('Lot ${lot.display} — ${repo.lotissementName(lot)}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (detail.price != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      '${fmtNum(detail.price!)} ${AppConfig.currency}',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700, color: cs.primary),
                    ),
                  ),
                _row('Superficie', '${fmtNum(lot.area)} m²'),
                _row('Moughataa', repo.moughataaName(lot)),
                _row('Lotissement', repo.lotissementName(lot)),
                if (lot.block != null) _row('Bloc', '${lot.block}'),
                if (dims.isNotEmpty) _row('Dimensions', dims.map(fmtMeters).join(', ')),
                if (detail.construction != null)
                  _row('Terrain',
                      detail.construction == 'libre' ? 'Libre (aucune construction)' : 'Construit'),
                if (detail.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(detail.description),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => appState.openMap(
                          FocusRequest(title: 'Lot ${lot.display}', selectKey: lot.key)),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Voir sur la carte'),
                    ),
                    if (_clientView)
                      FilledButton.icon(
                        onPressed: () => _contact(context),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Contacter l\'agence'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photos de l'annonce : défilement horizontal, points d'avancement, plein écran au tap.
class _PhotoCarousel extends StatefulWidget {
  final List<String> photos;
  const _PhotoCarousel({required this.photos});

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  final _ctrl = PageController();
  int _i = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _img(String url, {BoxFit fit = BoxFit.cover}) => Image.network(
        url,
        fit: fit,
        width: double.infinity,
        loadingBuilder: (c, child, p) => p == null
            ? child
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (_, _, _) => const Center(child: Icon(Icons.image_not_supported_outlined)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.photos.isEmpty) {
      return Container(
        height: 140,
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.landscape_outlined, size: 48),
      );
    }
    return SizedBox(
      height: 230,
      child: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog.fullscreen(
                  backgroundColor: Colors.black,
                  child: Stack(
                    children: [
                      Center(
                        child: InteractiveViewer(child: _img(widget.photos[i], fit: BoxFit.contain)),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: _img(widget.photos[i]),
            ),
          ),
          if (widget.photos.length > 1) ...[
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_i + 1}/${widget.photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < widget.photos.length; k++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: k == _i ? Colors.white : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Feuille « Contacter l'agence » : message modifiable, envoyé dans le chat du client.
class _ContactSheet extends StatefulWidget {
  final String initialText;
  const _ContactSheet({required this.initialText});

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final _ctrl = TextEditingController(text: widget.initialText);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sendClientChatMessage(t);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Envoi impossible : $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Contacter l\'agence', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Envoyer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
