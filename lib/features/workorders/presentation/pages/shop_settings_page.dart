import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ctech_repair/core/refs.dart'; // <-- donde tienes shopRef

class ShopSettingsPage extends StatefulWidget {
  const ShopSettingsPage({super.key});

  @override
  State<ShopSettingsPage> createState() => _ShopSettingsPageState();
}

class _ShopSettingsPageState extends State<ShopSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _igvCtrl = TextEditingController(); // 0.18
  final _baseUrlCtrl = TextEditingController(); // trackingBaseUrl

  bool _pricesIncludeIgv = true;
  String? _logoUrl;
  bool _saving = false;
  bool _appliedSnapshot =
      false; // para no sobreescribir cambios locales en hot-rebuild

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rucCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _igvCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> d) {
    _nameCtrl.text = (d['name'] ?? '').toString();
    _rucCtrl.text = (d['ruc'] ?? '').toString();
    _addrCtrl.text = (d['address'] ?? '').toString();
    _phoneCtrl.text = (d['phone'] ?? '').toString();
    _igvCtrl.text = ((d['igvRate'] ?? 0.18) as num).toString();
    _baseUrlCtrl.text = (d['trackingBaseUrl'] ?? '').toString();
    _pricesIncludeIgv = (d['pricesIncludeIgv'] ?? true) as bool;
    _logoUrl = (d['logoUrl'] ?? '').toString().trim().isEmpty
        ? null
        : (d['logoUrl'] as String);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final igv = double.tryParse(_igvCtrl.text.replaceAll(',', '.')) ?? 0.18;
      await shopRef.update({
        'name': _nameCtrl.text.trim(),
        'ruc': _rucCtrl.text.trim(),
        'address': _addrCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'igvRate': igv,
        'pricesIncludeIgv': _pricesIncludeIgv,
        'trackingBaseUrl': _baseUrlCtrl.text.trim(),
        // 'logoUrl' ya se actualiza al subir imagen
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Guardado')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadLogo() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (x == null) return;

      final file = File(x.path);
      final path =
          'shops/${shopRef.id}/logos/logo_${DateTime.now().millisecondsSinceEpoch}.png';
      final ref = FirebaseStorage.instance.ref(path);
      final upload = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/png'),
      );
      final url = await upload.ref.getDownloadURL();

      await shopRef.update({
        'logoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _logoUrl = url);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logo actualizado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al subir logo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Object?>>(
      stream: shopRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.data() != null && !_appliedSnapshot) {
          final data = snap.data!.data();
          if (data is Map<String, dynamic>) {
            _apply(data);
            _appliedSnapshot = true;
          }
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Configuración de la tienda'),
            actions: [
              IconButton(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                tooltip: 'Guardar',
              ),
            ],
          ),
          body:
              snap.connectionState == ConnectionState.waiting &&
                  !_appliedSnapshot
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Center(
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundImage: _logoUrl == null
                                    ? null
                                    : NetworkImage(_logoUrl!),
                                child: _logoUrl == null
                                    ? const Icon(Icons.store, size: 36)
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _pickAndUploadLogo,
                                icon: const Icon(Icons.image),
                                label: const Text('Cambiar logo'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                        TextFormField(
                          controller: _rucCtrl,
                          decoration: const InputDecoration(labelText: 'RUC'),
                        ),
                        TextFormField(
                          controller: _addrCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dirección',
                          ),
                        ),
                        TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _igvCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'IGV (ej. 0.18)',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SwitchListTile(
                                title: const Text('Precios incluyen IGV'),
                                value: _pricesIncludeIgv,
                                onChanged: (v) =>
                                    setState(() => _pricesIncludeIgv = v),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                        TextFormField(
                          controller: _baseUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'URL pública de seguimiento (base)',
                            hintText: 'https://mi-dominio.com/orden',
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save),
                          label: _saving
                              ? const Text('Guardando...')
                              : const Text('Guardar cambios'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
