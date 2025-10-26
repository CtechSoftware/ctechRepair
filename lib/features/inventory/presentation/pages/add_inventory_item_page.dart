// lib/features/inventory/presentation/pages/add_inventory_item_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/refs.dart';

class AddInventoryItemPage extends StatefulWidget {
  const AddInventoryItemPage({super.key});

  @override
  State<AddInventoryItemPage> createState() => _AddInventoryItemPageState();
}

class _AddInventoryItemPageState extends State<AddInventoryItemPage> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _cost = TextEditingController(text: '0');
  final _price = TextEditingController(text: '0');
  final _qtyOnHand = TextEditingController(text: '0');
  final _minQty = TextEditingController(text: '0');

  bool _saving = false;

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _category.dispose();
    _brand.dispose();
    _model.dispose();
    _cost.dispose();
    _price.dispose();
    _qtyOnHand.dispose();
    _minQty.dispose();
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;
  double _d(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;
  int _i(String s) => int.tryParse(s) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('inventoryItems').add({
        'shopId': shopRef,
        'sku': _sku.text.trim(),
        'name': _name.text.trim(),
        'category': _category.text.trim().isEmpty
            ? null
            : _category.text.trim(),
        'brand': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        'model': _model.text.trim().isEmpty ? null : _model.text.trim(),
        'cost': _d(_cost.text),
        'price': _d(_price.text),
        'qtyOnHand': _i(_qtyOnHand.text),
        'minQty': _i(_minQty.text),
        'createdAt': now,
        'updatedAt': now,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pad = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar ítem')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _sku,
                      decoration: const InputDecoration(
                        labelText: 'SKU *',
                        hintText: 'BAT-IPH11-001',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: _req,
                    ),
                    pad,
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        hintText: 'Batería iPhone 11',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: _req,
                    ),
                    pad,
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cost,
                            decoration: const InputDecoration(
                              labelText: 'Costo *',
                              prefixText: 'S/ ',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (v) =>
                                (_d(v ?? '0') < 0) ? 'Inválido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _price,
                            decoration: const InputDecoration(
                              labelText: 'Precio *',
                              prefixText: 'S/ ',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (v) =>
                                (_d(v ?? '0') < 0) ? 'Inválido' : null,
                          ),
                        ),
                      ],
                    ),
                    pad,
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _qtyOnHand,
                            decoration: const InputDecoration(
                              labelText: 'Stock *',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (_i(v ?? '0') < 0) ? 'Inválido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _minQty,
                            decoration: const InputDecoration(
                              labelText: 'Stock mínimo *',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) =>
                                (_i(v ?? '0') < 0) ? 'Inválido' : null,
                          ),
                        ),
                      ],
                    ),
                    pad,
                    TextFormField(
                      controller: _category,
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        hintText: 'Repuesto / Accesorio / Servicio',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    pad,
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _brand,
                            decoration: const InputDecoration(
                              labelText: 'Marca',
                              border: OutlineInputBorder(),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _model,
                            decoration: const InputDecoration(
                              labelText: 'Modelo',
                              border: OutlineInputBorder(),
                            ),
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _save(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
