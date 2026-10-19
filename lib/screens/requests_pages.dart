import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../repo.dart';
import '../services.dart';
import '../theme.dart';
import '../widgets/ui.dart';

final _dateFmt = DateFormat('dd/MM HH:mm');
final _hm = DateFormat('HH:mm');
String _fmtTs(dynamic t) => t is Timestamp ? _dateFmt.format(t.toDate()) : '';
String _fmtHm(dynamic t) => t is Timestamp ? _hm.format(t.toDate()) : '';
int _ms(Map<String, dynamic> d) =>
    (d['lastAt'] is Timestamp) ? (d['lastAt'] as Timestamp).millisecondsSinceEpoch : 0;

String _s(Map<String, dynamic> d, String k) => ((d[k] ?? '') as String).trim();

String requestSummary(Map<String, dynamic> d) {
  final p = <String>[];
  if (_s(d, 'moughataa').isNotEmpty) p.add(_s(d, 'moughataa'));
  if (_s(d, 'lotissement').isNotEmpty) p.add(_s(d, 'lotissement'));
  if (_s(d, 'lot').isNotEmpty) p.add('Lot ${_s(d, 'lot')}');
  final a0 = d['areaMin'] as num?, a1 = d['areaMax'] as num?;
  if (a0 != null || a1 != null) {
    p.add('${a0 != null ? fmtNum(a0) : '…'} à ${a1 != null ? fmtNum(a1) : '…'} m²');
  }
  final b0 = d['budgetMin'] as num?, b1 = d['budgetMax'] as num?;
  if (b0 != null || b1 != null) {
    p.add('${b0 != null ? fmtNum(b0) : '…'} à ${b1 != null ? fmtNum(b1) : '…'} MRU');
  }
  if (d['offer'] != null) p.add(d['offer'] == 'location' ? 'Location' : 'Achat');
  if (d['construction'] != null) {
    p.add(d['construction'] == 'libre' ? 'Terrain libre' : 'Terrain construit');
  }
  return p.join(' · ');
}

class _RequestList extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final bool staff;
  const _RequestList({required this.docs, required this.staff});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_outlined,
        title: staff ? 'Aucune demande' : 'Aucune demande pour le moment',
        text: staff
            ? 'Les demandes des clients apparaîtront ici.'
            : 'Décrivez le terrain que vous cherchez : l\'agence vous répond dans l\'application.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final d = docs[i].data();
        final unread = staff ? d['unreadStaff'] == true : d['unreadClient'] == true;
        final summary = requestSummary(d);
        final open = d['status'] != 'traitée';
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RequestThreadPage(id: docs[i].id, staff: staff)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Badge2(open ? 'Ouverte' : 'Traitée',
                          bg: open ? AppColors.primarySoft : AppColors.sand,
                          fg: open ? AppColors.primaryDark : AppColors.sandDark),
                      const Spacer(),
                      if (unread)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: const BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle),
                        ),
                      Text(_fmtTs(d['lastAt']),
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    summary.isEmpty ? ((d['message'] ?? 'Demande') as String) : summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                        height: 1.25),
                  ),
                  if (staff) ...[
                    const SizedBox(height: 4),
                    Text('${d['name'] ?? 'Client'} · +222 ${d['phone'] ?? ''}',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ],
                  if ('${d['lastMessage'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${d['lastMessage']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.muted, height: 1.3)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Client : ses propres demandes.
class RequestsClientPage extends StatelessWidget {
  const RequestsClientPage({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const NewRequestPage())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvelle demande'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .where('uid', isEqualTo: u.uid)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.toList()
            ..sort((a, b) => _ms(b.data()).compareTo(_ms(a.data())));
          return _RequestList(docs: docs, staff: false);
        },
      ),
    );
  }
}

/// Équipe : toutes les demandes.
class RequestsStaffPage extends StatefulWidget {
  const RequestsStaffPage({super.key});

  @override
  State<RequestsStaffPage> createState() => _RequestsStaffPageState();
}

class _RequestsStaffPageState extends State<RequestsStaffPage> {
  bool _onlyOpen = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Ouvertes')),
                ButtonSegment(value: false, label: Text('Toutes')),
              ],
              selected: {_onlyOpen},
              onSelectionChanged: (s) => setState(() => _onlyOpen = s.first),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('requests')
                .orderBy('lastAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs
                  .where((d) => !_onlyOpen || d.data()['status'] != 'traitée')
                  .toList();
              return _RequestList(docs: docs, staff: true);
            },
          ),
        ),
      ],
    );
  }
}

class NewRequestPage extends StatefulWidget {
  const NewRequestPage({super.key});

  @override
  State<NewRequestPage> createState() => _NewRequestPageState();
}

class _NewRequestPageState extends State<NewRequestPage> {
  String? _moughataa;
  String? _offer;
  String? _construction;
  final _lotissement = TextEditingController();
  final _a0 = TextEditingController();
  final _a1 = TextEditingController();
  final _b0 = TextEditingController();
  final _b1 = TextEditingController();
  final _msg = TextEditingController();
  bool _busy = false;
  String? _error;

  num? _num(TextEditingController c) {
    final t = c.text.replaceAll(RegExp(r'[^0-9.]'), '');
    return t.isEmpty ? null : num.tryParse(t);
  }

  Future<void> _submit() async {
    final a0 = _num(_a0), a1 = _num(_a1), b0 = _num(_b0), b1 = _num(_b1);
    final any = _moughataa != null ||
        _lotissement.text.trim().isNotEmpty ||
        a0 != null || a1 != null || b0 != null || b1 != null ||
        _offer != null || _construction != null ||
        _msg.text.trim().isNotEmpty;
    if (!any) {
      setState(() => _error = 'Renseignez au moins un critère ou un message.');
      return;
    }
    if (a0 != null && a1 != null && a0 > a1) {
      setState(() => _error = 'Superficie : le minimum dépasse le maximum.');
      return;
    }
    if (b0 != null && b1 != null && b0 > b1) {
      setState(() => _error = 'Budget : le minimum dépasse le maximum.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final u = FirebaseAuth.instance.currentUser!;
      final now = Timestamp.now();
      final data = <String, dynamic>{
        'uid': u.uid,
        'name': u.displayName ?? 'Client',
        'phone': AuthService.phoneOf(u),
        'moughataa': _moughataa,
        'lotissement': _lotissement.text.trim(),
        'areaMin': a0,
        'areaMax': a1,
        'budgetMin': b0,
        'budgetMax': b1,
        'offer': _offer,
        'construction': _construction,
        'message': _msg.text.trim(),
        'status': 'ouverte',
        'createdAt': now,
        'lastAt': now,
        'unreadStaff': true,
        'unreadClient': false,
      };
      data['lastMessage'] = _msg.text.trim().isNotEmpty
          ? _msg.text.trim()
          : requestSummary(data);
      await FirebaseFirestore.instance.collection('requests').add(data);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Demande envoyée.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Envoi impossible : $e';
        });
      }
    }
  }

  Widget _numField(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle demande')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const Text('Décrivez le terrain que vous cherchez.',
              style: TextStyle(color: AppColors.muted)),
          const SectionLabel('Zone'),
          DropdownButtonFormField<String?>(
            initialValue: _moughataa,
            decoration: const InputDecoration(labelText: 'Moughataa'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Indifférent')),
              for (final m in repo.moughataas)
                DropdownMenuItem(value: m.fr, child: Text(m.fr)),
            ],
            onChanged: (v) => setState(() => _moughataa = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lotissement,
            decoration: const InputDecoration(labelText: 'Lotissement (facultatif)'),
          ),
          const SectionLabel('Superficie'),
          Row(children: [
            _numField(_a0, 'Min (m²)'),
            const SizedBox(width: 10),
            _numField(_a1, 'Max (m²)'),
          ]),
          const SectionLabel('Budget'),
          Row(children: [
            _numField(_b0, 'Min (MRU)'),
            const SizedBox(width: 10),
            _numField(_b1, 'Max (MRU)'),
          ]),
          const SectionLabel('Type de bien'),
          DropdownButtonFormField<String?>(
            initialValue: _offer,
            decoration: const InputDecoration(labelText: 'Achat ou location'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Indifférent')),
              DropdownMenuItem(value: 'vente', child: Text('Achat')),
              DropdownMenuItem(value: 'location', child: Text('Location')),
            ],
            onChanged: (v) => setState(() => _offer = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _construction,
            decoration: const InputDecoration(labelText: 'Terrain'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Indifférent')),
              DropdownMenuItem(value: 'libre', child: Text('Libre (aucune construction)')),
              DropdownMenuItem(value: 'construit', child: Text('Construit')),
            ],
            onChanged: (v) => setState(() => _construction = v),
          ),
          const SectionLabel('Message'),
          TextField(
            controller: _msg,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Précisions utiles pour l\'agence…'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
  }
}

class RequestThreadPage extends StatefulWidget {
  final String id;
  final bool staff;
  const RequestThreadPage({super.key, required this.id, required this.staff});

  @override
  State<RequestThreadPage> createState() => _RequestThreadPageState();
}

class _RequestThreadPageState extends State<RequestThreadPage> {
  late final DocumentReference<Map<String, dynamic>> _ref;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ref = FirebaseFirestore.instance.collection('requests').doc(widget.id);
    _markRead();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      final d = (await _ref.get()).data();
      if (d == null) return;
      final key = widget.staff ? 'unreadStaff' : 'unreadClient';
      if (d[key] == true) await _ref.update({key: false});
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    final now = Timestamp.now();
    final u = FirebaseAuth.instance.currentUser!;
    await _ref.collection('replies').add({
      'text': text,
      'from': widget.staff ? 'staff' : 'client',
      'name': u.displayName ?? '',
      'at': now,
    });
    await _ref.update({
      'lastAt': now,
      'lastMessage': text,
      if (widget.staff) ...{'unreadClient': true, 'unreadStaff': false}
      else ...{'unreadStaff': true, 'unreadClient': false},
    });
  }

  Future<void> _toggleStatus(bool open) => _ref.update({'status': open ? 'ouverte' : 'traitée'});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ref.snapshots(),
      builder: (context, reqSnap) {
        final d = reqSnap.data?.data();
        final open = d?['status'] != 'traitée';
        return Scaffold(
          appBar: AppBar(
            title: const Text('Demande'),
            actions: [
              if (widget.staff && d != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: () => _toggleStatus(!open),
                    child: Text(open ? 'Marquer traitée' : 'Rouvrir'),
                  ),
                ),
            ],
          ),
          body: d == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _ref.collection('replies').orderBy('at').snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) return Center(child: Text('${snap.error}'));
                          final replies = snap.data?.docs ?? const [];
                          return ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                            itemCount: replies.length + 1,
                            itemBuilder: (context, i) {
                              if (i == 0) return _header(context, d, open);
                              final m = replies[i - 1].data();
                              final fromStaff = m['from'] == 'staff';
                              final mine = fromStaff == widget.staff;
                              return ChatBubble(
                                text: (m['text'] ?? '') as String,
                                mine: mine,
                                time: _fmtHm(m['at']),
                                name: mine ? null : (m['name'] ?? '') as String,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    MessageInput(controller: _ctrl, onSend: _send, hint: 'Répondre'),
                  ],
                ),
        );
      },
    );
  }

  Widget _header(BuildContext context, Map<String, dynamic> d, bool open) {
    final summary = requestSummary(d);
    final msg = _s(d, 'message');
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Badge2(open ? 'Ouverte' : 'Traitée',
                  bg: open ? AppColors.primarySoft : AppColors.sand,
                  fg: open ? AppColors.primaryDark : AppColors.sandDark),
              const Spacer(),
              Text(_fmtTs(d['createdAt']),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          if (widget.staff) ...[
            const SizedBox(height: 10),
            Text('${d['name'] ?? 'Client'} · +222 ${d['phone'] ?? ''}',
                style: Theme.of(context).textTheme.titleSmall),
          ],
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(summary,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.3)),
          ],
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(msg, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }
}
