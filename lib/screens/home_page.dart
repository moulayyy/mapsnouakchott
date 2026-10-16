import 'package:flutter/material.dart';

import '../repo.dart';
import '../services.dart';
import 'search_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _search(BuildContext context) async {
    final r = await Navigator.push<FocusRequest>(
        context, MaterialPageRoute(builder: (_) => const SearchPage()));
    if (r != null) appState.openMap(r);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MapsNouakchott'),
        actions: [
          if (repo.isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: const Text('Admin'),
                backgroundColor: cs.tertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: () => _search(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(children: [
                Icon(Icons.search),
                SizedBox(width: 12),
                Expanded(child: Text('Moughataa, lotissement, n° de lot…')),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Text('Moughataas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in repo.moughataas)
                ActionChip(
                  label: Text(m.fr),
                  onPressed: () => appState.openMap(
                      FocusRequest(title: m.fr, moughataa: m.code)),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Nous contacter'),
              subtitle: const Text('Écrivez-nous directement dans l\'application'),
              onTap: () => appState.openChat(),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: const Text('Ventes & Locations'),
              onTap: () => appState.setTab(1),
            ),
          ),
        ],
      ),
    );
  }
}
