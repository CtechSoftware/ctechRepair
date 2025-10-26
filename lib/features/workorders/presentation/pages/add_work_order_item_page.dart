import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AddWorkOrderItemPage extends StatefulWidget {
  const AddWorkOrderItemPage({super.key, required this.workOrderId});

  final String workOrderId;

  @override
  State<AddWorkOrderItemPage> createState() => _AddWorkOrderItemPageState();
}

class _AddWorkOrderItemPageState extends State<AddWorkOrderItemPage> {
  final _formKey = GlobalKey<FormState>();
  String _itemType = 'service'; // service | part
  final _description = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _unitPrice = TextEditingController(text: '0');

  bool _saving = false;

  @override
  void dispose() {
    _description.dispose();
    _qty.dispose();
    _unitPrice.dispose();
    super.dispose();
  }

  double _d(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;
  double _q(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final woRef = db.collection('workOrders').doc(widget.workOrderId);
    final itemsRef = woRef.collection('items');

    // Parseos
    final qty = double.tryParse(_qty.text.replaceAll(',', '.')) ?? 0;
    final unit = double.tryParse(_unitPrice.text.replaceAll(',', '.')) ?? 0;
    final total = qty * unit;
    final now = FieldValue.serverTimestamp();

    try {
      // 1) batch: crea item + actualiza totales de la orden
      final batch = db.batch();

      final newItemRef = itemsRef.doc();
      batch.set(newItemRef, {
        'itemType': _itemType, // 'service' | 'part'
        'description': _description.text.trim(),
        'qty': qty,
        'unitPrice': unit,
        'total': total,
        'inventoryItemId': null,
        'createdAt': now,
      });

      // 2) Actualiza totales sin leer el doc: incrementos atómicos
      batch.update(woRef, {
        'itemsTotal': FieldValue.increment(total),
        'balance': FieldValue.increment(
          total,
        ), // paidTotal no cambia, así que balance sube lo mismo que itemsTotal
        'updatedAt': now,
      });

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando ítem: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error inesperado: $e')));
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
                        setState(() => _itemType = v ?? 'service'),
                  ),
                  pad,
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Descripción *',
                      hintText: 'Diagnóstico / Cambio de batería / etc.',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
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
                              ((_q(v ?? '') <= 0) ? 'Inválido' : null),
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
                              ((_d(v ?? '') < 0) ? 'Inválido' : null),
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
                    label: const Text('Guardar ítem'),
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
