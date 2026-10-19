import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services.dart';

/// Gestion des comptes employés (admin uniquement).
class TeamPage extends StatelessWidget {
  const TeamPage({super.key});

  Future<void> _editPerms(BuildContext context, String id, String name, List<String> current) async {
    final sel = current.toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text('Autorisations — $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in kPermissions.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: sel.contains(e.key),
                  onChanged: (v) => setS(() => v == true ? sel.add(e.key) : sel.remove(e.key)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('staff')
          .doc(id)
          .update({'permissions': sel.toList()});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Équipe')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AddStaffPage())),
        icon: const Icon(Icons.person_add),
        label: const Text('Créer un compte'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('staff').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.toList()
            ..sort((a, b) => ((a['name'] ?? '') as String)
                .toLowerCase()
                .compareTo(((b['name'] ?? '') as String).toLowerCase()));
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun compte employé. Créez-en un avec le bouton ci-dessous.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final perms = ((d['permissions'] as List?) ?? const []).cast<String>();
              final active = d['active'] == true;
              final name = (d['name'] ?? '') as String;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                  title: Text(name),
                  subtitle: Text(
                    '+222 ${d['phone'] ?? ''}\n'
                    '${perms.isEmpty ? 'Aucune autorisation' : perms.map((p) => kPermissions[p] ?? p).join(', ')}',
                  ),
                  isThreeLine: true,
                  trailing: Switch(
                    value: active,
                    onChanged: (v) => docs[i].reference.update({'active': v}),
                  ),
                  onTap: () => _editPerms(context, docs[i].id, name, perms),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AddStaffPage extends StatefulWidget {
  const AddStaffPage({super.key});

  @override
  State<AddStaffPage> createState() => _AddStaffPageState();
}

class _AddStaffPageState extends State<AddStaffPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  late final Set<String> _perms = kPermissions.keys.toSet();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    final phone = AuthService.normalizePhone(_phone.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Entrez un nom.');
      return;
    }
    if (phone.length < 8) {
      setState(() => _error = 'Numéro de téléphone invalide.');
      return;
    }
    if (_pass.text.length < 6) {
      setState(() => _error = 'Mot de passe : 6 caractères minimum.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.createStaff(
        name: _name.text.trim(),
        phone: phone,
        password: _pass.text,
        permissions: _perms.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compte créé pour ${_name.text.trim()}.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AuthService.message(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau compte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Nom du compte', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Téléphone', prefixText: '+222 ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Autorisations', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final e in kPermissions.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.value),
              value: _perms.contains(e.key),
              onChanged: (v) => setState(() => v == true ? _perms.add(e.key) : _perms.remove(e.key)),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Créer le compte'),
          ),
          const SizedBox(height: 8),
          Text(
            'Communiquez le numéro et le mot de passe à la personne. '
            'Elle se connecte comme un client ; ses accès d\'équipe viennent des autorisations ci-dessus.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
