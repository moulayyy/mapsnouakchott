import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../repo.dart';
import '../services.dart';

class ListingsPage extends StatefulWidget {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage> {
  late Future<List<MapEntry<String, LotDetail>>> _f;
  String _filter = 'tous';

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

  int _lastTab = -1;
  void _onTab() {
    if (appState.tab == 1 && _lastTab != 1) {
      setState(() => _f = repo.loadOffers());
    }
    _lastTab = appState.tab;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ventes & Locations')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'tous', label: Text('Tous')),
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
                if (snap.hasError) {
                  return Center(child: Text('${snap.error}'));
                }
                final items = snap.data!
                    .where((e) => _filter == 'tous' || e.value.offer == _filter)
                    .where((e) => repo.byKey.containsKey(e.key))
                    .toList();
                if (items.isEmpty) {
                  return const Center(child: Text('Aucune offre pour le moment.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _f = repo.loadOffers());
                    await _f;
                  },
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final lot = repo.byKey[e.key]!;
                      final d = e.value;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: d.photos.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(d.photos.first,
                                      width: 56, height: 56, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported)),
                                )
                              : const Icon(Icons.landscape),
                          title: Text('Lot ${lot.display} — ${repo.lotissementName(lot)}'),
                          subtitle: Text(
                              '${d.offer == 'location' ? 'Location' : 'Vente'} · ${fmtNum(lot.area)} m² · ${repo.moughataaName(lot)}'),
                          trailing: Text(
                            d.price == null ? '' : '${fmtNum(d.price!)}\n${AppConfig.currency}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onTap: () => appState.openMap(FocusRequest(
                              title: 'Lot ${lot.display}', selectKey: lot.key)),
                        ),
                      );
                    },
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
