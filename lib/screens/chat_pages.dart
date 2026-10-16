import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repo.dart';
import '../services.dart';

class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const SizedBox();
    if (repo.isAdmin) return const AdminChatList();
    return Scaffold(
      appBar: AppBar(title: const Text('Nous contacter')),
      body: ChatThread(uid: u.uid, asAdmin: false),
    );
  }
}

class AdminChatList extends StatelessWidget {
  const AdminChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .orderBy('lastAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Aucune conversation.'));
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final unread = d['unreadAdmin'] == true;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text((d['name'] ?? 'Client') as String,
                    style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text('+222 ${d['phone'] ?? ''} · ${d['lastMessage'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: unread
                    ? const Icon(Icons.circle, size: 12, color: Colors.red)
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text((d['name'] ?? 'Client') as String)),
                      body: ChatThread(uid: docs[i].id, asAdmin: true),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatThread extends StatefulWidget {
  final String uid; // uid du client propriétaire de la conversation
  final bool asAdmin;
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
    if (d != null && appState.tab == 3) {
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
    final now = Timestamp.now();
    await _chat.collection('messages').add({
      'text': text,
      'from': widget.asAdmin ? 'admin' : 'client',
      'at': now,
    });
    if (widget.asAdmin) {
      await _chat.set({
        'lastMessage': text,
        'lastAt': now,
        'unreadUser': true,
        'unreadAdmin': false,
      }, SetOptions(merge: true));
    } else {
      final u = FirebaseAuth.instance.currentUser!;
      await _chat.set({
        'name': u.displayName ?? 'Client',
        'phone': AuthService.phoneOf(u),
        'lastMessage': text,
        'lastAt': now,
        'unreadAdmin': true,
        'unreadUser': false,
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                return const Center(child: Text('Écrivez votre message ci-dessous.'));
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final mine = (m['from'] == 'admin') == widget.asAdmin;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text((m['text'] ?? '') as String),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
