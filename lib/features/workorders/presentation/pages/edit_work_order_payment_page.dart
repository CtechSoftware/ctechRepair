import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditWorkOrderPaymentPage extends StatefulWidget {
  const EditWorkOrderPaymentPage({
    super.key,
    required this.workOrderId,
    required this.paymentId,
    required this.initialData,
  });

  final String workOrderId;
  final String paymentId;
  final Map<String, dynamic> initialData;

  @override
  State<EditWorkOrderPaymentPage> createState() =>
      _EditWorkOrderPaymentPageState();
}

class _EditWorkOrderPaymentPageState extends State<EditWorkOrderPaymentPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _method; // cash | card | transfer | other
  late DateTime _receivedAt;

  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _amount = TextEditingController(text: (d['amount'] ?? 0).toString());
    _note = TextEditingController(text: (d['note'] ?? '').toString());
    _method = (d['method'] ?? 'cash').toString();
    final ts = d['receivedAt'] as Timestamp?;
    _receivedAt = ts?.toDate() ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double _d(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0;

  Future<void> _pickReceivedAt() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _receivedAt,
    );
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_receivedAt),
    );
    setState(() {
      _receivedAt = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? 0,
        t?.minute ?? 0,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final woRef = db.collection('workOrders').doc(widget.workOrderId);
    final payRef = woRef.collection('payments').doc(widget.paymentId);

    final oldAmount = (widget.initialData['amount'] ?? 0).toDouble();
    final newAmount = _d(_amount.text);
    final delta = newAmount - oldAmount; // + sube pagado, - baja pagado
    final now = FieldValue.serverTimestamp();

    try {
      final batch = db.batch();

      // 1) Actualiza el pago
      batch.update(payRef, {
        'amount': newAmount,
        'method': _method,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'receivedAt': Timestamp.fromDate(_receivedAt),
        'updatedAt': now,
      });

      // 2) Ajusta totales del padre
      batch.update(woRef, {
        'paidTotal': FieldValue.increment(delta),
        'balance': FieldValue.increment(-delta),
        'updatedAt': now,
      });

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar pago: ${e.message ?? e.code}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar pago'),
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
    if (ok != true) return;

    setState(() => _deleting = true);

    final db = FirebaseFirestore.instance;
    final woRef = db.collection('workOrders').doc(widget.workOrderId);
    final payRef = woRef.collection('payments').doc(widget.paymentId);

    final oldAmount = (widget.initialData['amount'] ?? 0).toDouble();
    final now = FieldValue.serverTimestamp();

    try {
      final batch = db.batch();

      // 1) Borra el pago
      batch.delete(payRef);

      // 2) Revierte su impacto en totales
      batch.update(woRef, {
        'paidTotal': FieldValue.increment(-oldAmount),
        'balance': FieldValue.increment(oldAmount),
        'updatedAt': now,
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pago eliminado')));
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
        title: const Text('Editar pago'),
        actions: [
          IconButton(
            tooltip: 'Eliminar pago',
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
                  TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'Monto *',
                      prefixText: 'S/ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) =>
                        (_d(v ?? '') > 0) ? null : 'Monto inválido',
                  ),
                  pad,
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Método',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                      DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                      DropdownMenuItem(
                        value: 'transfer',
                        child: Text('Transferencia'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Otro')),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? _method),
                  ),
                  pad,
                  OutlinedButton.icon(
                    onPressed: _pickReceivedAt,
                    icon: const Icon(Icons.event),
                    label: Text(
                      'Fecha/hora: ${_receivedAt.toString().substring(0, 16)}',
                    ),
                  ),
                  pad,
                  TextField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      border: OutlineInputBorder(),
                    ),
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
