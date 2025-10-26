import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddWorkOrderPaymentPage extends StatefulWidget {
  const AddWorkOrderPaymentPage({super.key, required this.workOrderId});
  final String workOrderId;

  @override
  State<AddWorkOrderPaymentPage> createState() =>
      _AddWorkOrderPaymentPageState();
}

class _AddWorkOrderPaymentPageState extends State<AddWorkOrderPaymentPage> {
  final _formKey = GlobalKey<FormState>();

  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash'; // cash | card | transfer | other
  DateTime _receivedAt = DateTime.now();
  bool _saving = false;

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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final woRef = db.collection('workOrders').doc(widget.workOrderId);
    final paysRef = woRef.collection('payments');

    final amount = _d(_amount.text);
    final now = FieldValue.serverTimestamp();

    try {
      final batch = db.batch();

      // 1) Crea el pago
      final payRef = paysRef.doc();
      batch.set(payRef, {
        'amount': amount,
        'method': _method,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'receivedAt': Timestamp.fromDate(_receivedAt),
        'receivedBy': uid,
        'createdAt': now,
      });

      // 2) Actualiza totales: paidTotal ↑ amount, balance ↓ amount
      batch.update(woRef, {
        'paidTotal': FieldValue.increment(amount),
        'balance': FieldValue.increment(-amount),
        'updatedAt': now,
      });

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando pago: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pad = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar pago')),
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
                    onChanged: (v) => setState(() => _method = v ?? 'cash'),
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
                    label: const Text('Guardar pago'),
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
