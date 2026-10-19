import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../repo.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'team_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Vous devrez saisir à nouveau votre numéro et votre mot de passe.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Se déconnecter')),
        ],
      ),
    );
    if (ok == true) {
      appState.tab = 0;
      await AuthService.signOut();
    }
  }

  void _about(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded, color: AppColors.primary),
        title: const Text('À propos des données'),
        content: const Text(
            'Les lots en vert viennent des plans officiels.\n\n'
            'Les parcelles en orange sont des estimations calculées d\'après les rues et le bâti : '
            'elles n\'ont aucune valeur juridique.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Compris'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final name = (u?.displayName ?? '').trim();
    final role = repo.isAdmin ? 'Admin' : (repo.isStaff ? 'Équipe' : 'Client');
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // carte profil
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primarySoft,
                  foregroundColor: AppColors.primaryDark,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Utilisateur' : name,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(u == null ? '' : '+222 ${AuthService.phoneOf(u)}',
                          style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 8),
                      Badge2(role,
                          bg: role == 'Client' ? AppColors.primarySoft : AppColors.sand,
                          fg: role == 'Client' ? AppColors.primaryDark : AppColors.sandDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (repo.isAdmin) ...[
            const SectionLabel('Administration'),
            _Group(children: [
              _Item(
                icon: Icons.groups_2_outlined,
                title: 'Équipe',
                subtitle: 'Créer des comptes et gérer leurs autorisations',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const TeamPage())),
              ),
            ]),
          ],
          const SectionLabel('Application'),
          _Group(children: [
            _Item(
              icon: Icons.layers_outlined,
              title: 'À propos des données',
              subtitle: 'Plans officiels et estimations',
              onTap: () => _about(context),
            ),
            _Item(
              icon: Icons.tag_rounded,
              title: AppConfig.appName,
              subtitle: 'Version 1.0',
            ),
          ]),
          const SizedBox(height: 18),
          _Group(children: [
            _Item(
              icon: Icons.logout_rounded,
              title: 'Se déconnecter',
              danger: true,
              onTap: () => _logout(context),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Bloc de lignes regroupées dans une carte arrondie.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const Divider(height: 1, indent: 64));
      items.add(children[i]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: items),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  const _Item({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB4483E) : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: danger ? color : AppColors.text)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            if (onTap != null && !danger)
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
