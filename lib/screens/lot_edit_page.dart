import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../repo.dart';

class LotEditPage extends StatefulWidget {
  final Lot lot;
  const LotEditPage({super.key, required this.lot});

  @override
  State<LotEditPage> createState() => _LotEditPageState();
}

class _LotEditPageState extends State<LotEditPage> {
  late LotDetail _d;
  final _price = TextEditingController();
  final _desc = TextEditingController();
  final _owner = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = (await repo.getDetail(widget.lot.key)).copy();
    _d = d;
    _price.text = d.price == null ? '' : d.price.toString();
    _desc.text = d.description;
    _owner.text = repo.owners[widget.lot.key] ?? '';
    _note.text = repo.ownerNotes[widget.lot.key] ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (files.isEmpty) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final name = '${DateTime.now().microsecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref('lots/${widget.lot.key}/$name');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        _d.photos.add(await ref.getDownloadURL());
      }
    } catch (e) {
      _error = 'Envoi de photo impossible : $e';
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _removePhoto(String url) async {
    setState(() => _d.photos.remove(url));
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
  }

  Future<void> _save() async {
    final priceText = _price.text.replaceAll(RegExp(r'[^0-9.]'), '');
    _d.price = priceText.isEmpty ? null : num.tryParse(priceText);
    _d.description = _desc.text.trim();
    if (_d.offer != null && _d.price == null) {
      setState(() => _error = 'Indiquez un prix pour une vente / location.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.saveLot(widget.lot, _d, owner: _owner.text, note: _note.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Enregistrement impossible : $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;
    return Scaffold(
      appBar: AppBar(
        title: Text('Lot ${lot.display}'),
        actions: [
          TextButton(
            onPressed: (_loading || _saving) ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${repo.lotissementName(lot)} · ${repo.moughataaName(lot)} · ${fmtNum(lot.area)} m²',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Actif (visible par les clients)'),
                  subtitle: const Text('Désactiver si le terrain n\'existe plus.'),
                  value: _d.active,
                  onChanged: (v) => setState(() => _d.active = v),
                ),
                const Divider(),
                DropdownButtonFormField<String?>(
                  initialValue: _d.offer,
                  decoration: const InputDecoration(labelText: 'Offre', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Aucune')),
                    DropdownMenuItem(value: 'vente', child: Text('Vente')),
                    DropdownMenuItem(value: 'location', child: Text('Location')),
                  ],
                  onChanged: (v) => setState(() => _d.offer = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _d.construction,
                  decoration: const InputDecoration(
                      labelText: 'Terrain (visible sur les annonces)',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Non précisé')),
                    DropdownMenuItem(value: 'libre', child: Text('Libre (aucune construction)')),
                    DropdownMenuItem(value: 'construit', child: Text('Construit')),
                  ],
                  onChanged: (v) => setState(() => _d.construction = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Prix (MRU)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _desc,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                      labelText: 'Description (visible par les clients)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Photos', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _uploading ? null : _addPhotos,
                      icon: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Ajouter'),
                    ),
                  ],
                ),
                SizedBox(
                  height: 96,
                  child: _d.photos.isEmpty
                      ? const Align(alignment: Alignment.centerLeft, child: Text('Aucune photo.'))
                      : ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final url in _d.photos)
                              Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(url, width: 96, height: 96, fit: BoxFit.cover),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 0,
                                    child: InkWell(
                                      onTap: () => _removePhoto(url),
                                      child: const CircleAvatar(
                                          radius: 11,
                                          backgroundColor: Colors.black54,
                                          child: Icon(Icons.close, size: 14, color: Colors.white)),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                ),
                const Divider(height: 32),
                Row(children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 6),
                  Text('Privé — visible uniquement par l\'admin',
                      style: Theme.of(context).textTheme.labelLarge),
                ]),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _owner.text),
                  optionsBuilder: (v) => repo.distinctOwners
                      .where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => _owner.text = v,
                  fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                    ctrl.addListener(() => _owner.text = ctrl.text);
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      decoration: const InputDecoration(
                          labelText: 'Propriétaire', border: OutlineInputBorder()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Note privée', border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
