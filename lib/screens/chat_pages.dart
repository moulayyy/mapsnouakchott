import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repo.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'requests_pages.dart';

final _hm = DateFormat('HH:mm');
final _dm = DateFormat('dd/MM');

String _timeOf(dynamic t) => t is Timestamp ? _hm.format(t.toDate()) : '';

String _listTime(dynamic t) {
  if (t is! Timestamp) return '';
  final d = t.toDate(), n = DateTime.now();
  return (d.year == n.year && d.month == n.month && d.day == n.day) ? _hm.format(d) : _dm.format(d);
}

/// Onglet Chat : messages + demandes.
/// Client : « Discussion » et « Mes demandes ».
/// Équipe (admin / employé) : « Conversations » et « Demandes » selon ses autorisations.
class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const SizedBox();
    final team = repo.canChat || repo.canRequests;
    final tabs = <Tab>[];
    final pages = <Widget>[];
    if (!team) {
      tabs.addAll(const [Tab(text: 'Discussion'), Tab(text: 'Mes demandes')]);
      pages.addAll([
        ChatThread(uid: u.uid, asAdmin: false),
        const RequestsClientPage(),
      ]);
    } else {
      if (repo.canChat) {
        tabs.add(const Tab(text: 'Conversations'));
        pages.add(const AdminChatList());
      }
      if (repo.canRequests) {
        tabs.add(const Tab(text: 'Demandes'));
        pages.add(const RequestsStaffPage());
      }
    }
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(team ? 'Messages' : 'Nous contacter'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEAE0),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  tabs: tabs,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.tiny,
                  ),
                  splashBorderRadius: BorderRadius.circular(14),
                  labelColor: AppColors.primaryDark,
                  unselectedLabelColor: AppColors.muted,
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(children: pages),
      ),
    );
  }
}

class AdminChatList extends StatelessWidget {
  const AdminChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .orderBy('lastAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_outlined,
            title: 'Aucune conversation',
            text: 'Les messages des clients apparaîtront ici.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final unread = d['unreadAdmin'] == true;
            final name = ((d['name'] ?? 'Client') as String);
            return Tile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                foregroundColor: AppColors.primaryDark,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              title: Text(name,
                  style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
              subtitle: Text('${d['lastMessage'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: unread ? AppColors.text : AppColors.muted,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_listTime(d['lastAt']),
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 4),
                  if (unread)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                    ),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: Theme.of(context).textTheme.titleMedium),
                          Text('+222 ${d['phone'] ?? ''}',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    body: ChatThread(uid: docs[i].id, asAdmin: true),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Envoie un message du client connecté à l'agence (conversation `chats/{uid}`).
Future<void> sendClientChatMessage(String text) async {
  final u = FirebaseAuth.instance.currentUser!;
  final chat = FirebaseFirestore.instance.collection('chats').doc(u.uid);
  final now = Timestamp.now();
  await chat.collection('messages').add({
    'text': text,
    'from': 'client',
    'by': u.displayName ?? '',
    'at': now,
  });
  await chat.set({
    'name': u.displayName ?? 'Client',
    'phone': AuthService.phoneOf(u),
    'lastMessage': text,
    'lastAt': now,
    'unreadAdmin': true,
    'unreadUser': false,
  }, SetOptions(merge: true));
}

class ChatThread extends StatefulWidget {
  final String uid; // uid du client propriétaire de la conversation
  final bool asAdmin; // vrai pour l'équipe (admin ou employé)
  const ChatThread({super.key, required this.uid, required this.asAdmin});

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  late final DocumentReference<Map<String, dynamic>> _chat;

  @override
  void initState() {
    super.initState();
    _chat = FirebaseFirestore.instance.collection('chats').doc(widget.uid);
    appState.addListener(_draft);
    _markRead();
    _draft();
  }

  @override
  void dispose() {
    appState.removeListener(_draft);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _draft() {
    if (widget.asAdmin) return;
    final d = appState.chatDraft;
    if (d != null && appState.tab == 2) {
      _ctrl.text = d;
      appState.chatDraft = null;
    }
  }

  Future<void> _markRead() async {
    try {
      final s = await _chat.get();
      if (!s.exists) return;
      await _chat.update(
          widget.asAdmin ? {'unreadAdmin': false} : {'unreadUser': false});
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    if (!widget.asAdmin) {
      await sendClientChatMessage(text);
      return;
    }
    final now = Timestamp.now();
    final u = FirebaseAuth.instance.currentUser!;
    await _chat.collection('messages').add({
      'text': text,
      'from': 'admin',
      'by': u.displayName ?? '',
      'at': now,
    });
    await _chat.set({
      'lastMessage': text,
      'lastAt': now,
      'unreadUser': true,
      'unreadAdmin': false,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _chat.collection('messages').orderBy('at').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return widget.asAdmin
                    ? const EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Aucun message',
                        text: 'Écrivez pour démarrer la conversation.')
                    : const EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Parlons de votre projet',
                        text: 'Écrivez-nous ici : l\'agence vous répond directement dans l\'application.');
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final mine = (m['from'] == 'admin') == widget.asAdmin;
                  return ChatBubble(
                    text: (m['text'] ?? '') as String,
                    mine: mine,
                    time: _timeOf(m['at']),
                    name: (m['from'] == 'admin' && !mine) ? (m['by'] ?? '') as String : null,
                  );
                },
              );
            },
          ),
        ),
        MessageInput(controller: _ctrl, onSend: _send),
      ],
    );
  }
}
