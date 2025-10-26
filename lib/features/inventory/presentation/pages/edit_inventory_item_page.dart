import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditInventoryItemPage extends StatefulWidget {
  const EditInventoryItemPage({
    super.key,
    required this.itemId,
    required this.initialData,
  });

  final String itemId;
  final Map<String, dynamic> initialData;

  @override
  State<EditInventoryItemPage> createState() => _EditInventoryItemPageState();
}

class _EditInventoryItemPageState extends State<EditInventoryItemPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _sku;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _qtyOnHand;
  late final TextEditingController _minQty;

  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _sku = TextEditingController(text: (d['sku'] ?? '').toString());
    _name = TextEditingController(text: (d['name'] ?? '').toString());
    _category = TextEditingController(text: (d['category'] ?? '').toString());
    _brand = TextEditingController(text: (d['brand'] ?? '').toString());
    _model = TextEditingController(text: (d['model'] ?? '').toString());
    _cost = TextEditingController(text: (d['cost'] ?? 0).toString());
    _price = TextEditingController(text: (d['price'] ?? 0).toString());
    _qtyOnHand = TextEditingController(text: (d['qtyOnHand'] ?? 0).toString());
    _minQty = TextEditingController(text: (d['minQty'] ?? 0).toString());
  }

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
      await FirebaseFirestore.instance
          .collection('inventoryItems')
          .doc(widget.itemId)
          .update({
            // No tocamos shopId (ya es Reference correcto en el doc)
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
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      Navigator.of(context).pop(true); // avisa a la lista que hubo cambios
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ítem'),
        content: const Text(
          'Esta acción no se puede deshacer. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) _delete();
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await FirebaseFirestore.instance
          .collection('inventoryItems')
          .doc(widget.itemId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ítem eliminado')));
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _deltaQty(int delta) {
    final current = _i(_qtyOnHand.text);
    final next = (current + delta).clamp(0, 1 << 31);
    setState(() => _qtyOnHand.text = next.toString());
  }

  @override
  Widget build(BuildContext context) {
    const pad = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar ítem'),
        actions: [
          IconButton(
            tooltip: 'Eliminar ítem',
            icon: _deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            onPressed: _deleting ? null : _confirmDelete,
          ),
        ],
      ),
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '−1',
                              onPressed: () => _deltaQty(-1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            IconButton(
                              tooltip: '+1',
                              onPressed: () => _deltaQty(1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
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
                      label: const Text('Guardar cambios'),
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
