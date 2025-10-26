import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditWorkOrderItemPage extends StatefulWidget {
  const EditWorkOrderItemPage({
    super.key,
    required this.workOrderId,
    required this.itemId,
    required this.initialData,
  });

  final String workOrderId;
  final String itemId;
  final Map<String, dynamic> initialData;

  @override
  State<EditWorkOrderItemPage> createState() => _EditWorkOrderItemPageState();
}

class _EditWorkOrderItemPageState extends State<EditWorkOrderItemPage> {
  final _formKey = GlobalKey<FormState>();

  late String _itemType; // service | part
  late final TextEditingController _description;
  late final TextEditingController _qty;
  late final TextEditingController _unitPrice;

  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _itemType = (d['itemType'] ?? 'service').toString();
    _description = TextEditingController(
      text: (d['description'] ?? '').toString(),
    );
    _qty = TextEditingController(text: (d['qty'] ?? 1).toString());
    _unitPrice = TextEditingController(text: (d['unitPrice'] ?? 0).toString());
  }

  @override
  void dispose() {
    _description.dispose();
    _qty.dispose();
    _unitPrice.dispose();
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requerido' : null;
  double _d(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  /// Actualiza el ítem y ajusta `itemsTotal`/`balance` en el padre
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final woRef = db.collection('workOrders').doc(widget.workOrderId);
    final itemRef = woRef.collection('items').doc(widget.itemId);

    // Totales viejo y nuevo
    final oldTotal = (widget.initialData['total'] ?? 0).toDouble();
    final qty = _d(_qty.text);
    final unit = _d(_unitPrice.text);
    final newTotal = qty * unit;
    final delta = newTotal - oldTotal; // lo que cambia el subtotal
    final now = FieldValue.serverTimestamp();

    try {
      final batch = db.batch();

      // 1) Actualiza el documento del ítem
      batch.update(itemRef, {
        'itemType': _itemType,
        'description': _description.text.trim(),
        'qty': qty,
        'unitPrice': unit,
        'total': newTotal,
        // opcional: 'updatedAt': now, si los ítems llevan updatedAt
      });

      // 2) Ajusta totales del padre con incrementos atómicos
      batch.update(woRef, {
        'itemsTotal': FieldValue.increment(delta),
        'balance': FieldValue.increment(delta), // paidTotal no cambia aquí
        'updatedAt': now,
      });

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Elimina el ítem y descuenta su total de `itemsTotal` y `balance`
  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar ítem'),
        content: const Text('Esta acción no se puede deshacer.'),
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
    if (confirm != true) return;

    setState(() => _deleting = true);

    final db = FirebaseFirestore.instance;
    final woRef = db.collection('workOrders').doc(widget.workOrderId);
    final itemRef = woRef.collection('items').doc(widget.itemId);

    final oldTotal = (widget.initialData['total'] ?? 0).toDouble();
    final now = FieldValue.serverTimestamp();

    try {
      final batch = db.batch();

      // 1) Borra el ítem
      batch.delete(itemRef);

      // 2) Descuenta del total del padre
      batch.update(woRef, {
        'itemsTotal': FieldValue.increment(-oldTotal),
        'balance': FieldValue.increment(-oldTotal),
        'updatedAt': now,
      });

      await batch.commit();

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
            onPressed: _deleting ? null : _delete,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _itemType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'service',
                        child: Text('Servicio'),
                      ),
                      DropdownMenuItem(value: 'part', child: Text('Repuesto')),
                    ],
                    onChanged: (v) =>
                        setState(() => _itemType = v ?? _itemType),
                  ),
                  pad,
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Descripción *',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    validator: _req,
                  ),
                  pad,
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qty,
                          decoration: const InputDecoration(
                            labelText: 'Cantidad *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) =>
                              (_d(v ?? '') > 0) ? null : 'Inválido',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _unitPrice,
                          decoration: const InputDecoration(
                            labelText: 'Precio unitario *',
                            prefixText: 'S/ ',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) =>
                              (_d(v ?? '') >= 0) ? null : 'Inválido',
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
    );
  }
}
