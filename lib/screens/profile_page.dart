import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repo.dart';
import '../services.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(u?.displayName ?? 'Utilisateur'),
            subtitle: Text(u == null ? '' : '+222 ${AuthService.phoneOf(u)}'),
            trailing: repo.isAdmin ? const Chip(label: Text('Admin')) : null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () async {
              appState.tab = 2;
              await AuthService.signOut();
            },
          ),
        ],
      ),
    );
  }
}
