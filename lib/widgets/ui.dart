import 'package:flutter/material.dart';

import '../theme.dart';

/// Panneau flottant en bas de la carte : coins arrondis, ombre douce, poignée.
class SheetShell extends StatelessWidget {
  final Widget child;
  final double maxHeightFactor;
  const SheetShell({super.key, required this.child, this.maxHeightFactor = 0.58});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.soft,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * maxHeightFactor),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton de fermeture discret.
class SoftCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const SoftCloseButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
        ),
      );
}

/// Tuile d'information (libellé discret + valeur).
class InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const InfoTile({super.key, required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Ligne « libellé : valeur » sobre, pour les détails secondaires.
Widget kvRow(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(k, style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
          ),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
        ],
      ),
    );

/// Petit badge arrondi.
class Badge2 extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Badge2(this.text, {super.key, this.bg = AppColors.primarySoft, this.fg = AppColors.primaryDark});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

/// Ligne de liste en carte arrondie (même paramètres que ListTile).
class Tile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final Color? tileColor;

  const Tile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.tileColor,
  });

  @override
  Widget build(BuildContext context) {
    final lead = (leading == null || leading is CircleAvatar)
        ? leading
        : Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: Center(child: leading),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: tileColor ?? AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
        child: ListTile(
          leading: lead,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
          onTap: onTap,
          dense: dense,
        ),
      ),
    );
  }
}

/// Bulle de message : à moi = teal, à l'autre = blanc avec fine bordure.
class ChatBubble extends StatelessWidget {
  final String text;
  final bool mine;
  final String time;
  final String? name;
  const ChatBubble({super.key, required this.text, required this.mine, required this.time, this.name});

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : AppColors.text;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.surface,
          border: mine ? null : Border.all(color: AppColors.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine && (name ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(name!,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            Text(text, style: TextStyle(fontSize: 15, height: 1.3, color: fg)),
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.centerRight,
              child: Text(time,
                  style: TextStyle(
                      fontSize: 10.5, color: mine ? Colors.white70 : AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre de saisie : champ arrondi + bouton d'envoi rond.
class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final String hint;
  const MessageInput({super.key, required this.controller, required this.onSend, this.hint = 'Votre message'});

  @override
  Widget build(BuildContext context) {
    const noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
      borderSide: BorderSide.none,
    );
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: AppColors.bg,
                  border: noBorder,
                  enabledBorder: noBorder,
                  focusedBorder: noBorder,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 21),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titre de section discret (petites capitales).
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
      );
}

/// État vide : pastille d'icône + titre + texte.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const EmptyState({super.key, required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, height: 1.4)),
            ],
          ),
        ),
      );
}
