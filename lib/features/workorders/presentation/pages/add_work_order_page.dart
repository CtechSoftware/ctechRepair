// lib/features/workorders/presentation/pages/add_work_order_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ctech_repair/core/refs.dart'; // Asegúrate que la ruta sea correcta

class AddWorkOrderPage extends StatefulWidget {
  const AddWorkOrderPage({super.key});
  @override
  State<AddWorkOrderPage> createState() => _AddWorkOrderPageState();
}

class _AddWorkOrderPageState extends State<AddWorkOrderPage> {
  final _formKey = GlobalKey<FormState>();

  // --- CAMBIO ---
  // Volvemos a usar DocumentReference para el valor del dropdown
  DocumentReference? _selectedCustomerRef;
  // Guardamos el snapshot aparte para tener los datos al guardar
  DocumentSnapshot<Map<String, dynamic>>? _selectedCustomerSnapshot;
  // --- FIN CAMBIO ---

  final _problem = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _imei = TextEditingController();

  int _priority = 0;
  DateTime? _promisedAt;
  bool _saving = false;

  @override
  void dispose() {
    _problem.dispose();
    _brand.dispose();
    _model.dispose();
    _imei.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _customersStream() {
    return FirebaseFirestore.instance
        .collection('customers')
        .where('shopId', isEqualTo: shopRef)
        .orderBy('fullName')
        .limit(200)
        .snapshots();
  }

  Future<void> _pickPromisedAt() async {
    // ... (esta función no cambia)
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 0)),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _promisedAt ?? now,
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_promisedAt ?? now),
    );
    if (time == null) {
      setState(() => _promisedAt = DateTime(date.year, date.month, date.day));
    } else {
      setState(
        () => _promisedAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    // --- CAMBIO ---
    // Verificamos el snapshot para asegurarnos de tener los datos
    if (_selectedCustomerSnapshot == null || _selectedCustomerRef == null) {
      // --- FIN CAMBIO ---
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un cliente')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final now = FieldValue.serverTimestamp();

      // Obtenemos los datos del snapshot que ya guardamos
      final customerData = _selectedCustomerSnapshot!.data();
      final customerRef =
          _selectedCustomerRef!; // Usamos la referencia guardada
      final customerName = (customerData?['fullName'] ?? '').toString();
      final customerPhone = (customerData?['phone'] ?? '').toString();
      final customerDocId = (customerData?['docId'] ?? '').toString();

      await FirebaseFirestore.instance.collection('workOrders').add({
        'shopId': shopRef,
        'status': 'new',
        'priority': _priority,
        'deviceBrand': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        'deviceModel': _model.text.trim().isEmpty ? null : _model.text.trim(),
        'deviceImei': _imei.text.trim().isEmpty ? null : _imei.text.trim(),
        'problemDescription': _problem.text.trim(),
        'promisedAt': _promisedAt == null
            ? null
            : Timestamp.fromDate(_promisedAt!),
        'createdBy': uid,
        'itemsTotal': 0,
        'paidTotal': 0,
        'balance': 0,
        'createdAt': now,
        'updatedAt': now,

        // Datos desnormalizados (esto ya estaba bien)
        'customerId': customerRef,
        'customerName': customerName.isEmpty ? null : customerName,
        'customerPhone': customerPhone.isEmpty ? null : customerPhone,
        'customerDocId': customerDocId.isEmpty ? null : customerDocId,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva orden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cliente Dropdown
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _customersStream(),
                    builder: (context, snap) {
                      // --- CAMBIO ---
                      // Volvemos a usar DocumentReference como tipo de valor
                      final items = <DropdownMenuItem<DocumentReference>>[];
                      // Mapa temporal para asociar la Referencia con su Snapshot
                      final snapshotMap =
                          <
                            DocumentReference,
                            DocumentSnapshot<Map<String, dynamic>>
                          >{};
                      // --- FIN CAMBIO ---
                      if (snap.hasData) {
                        for (final doc in snap.data!.docs) {
                          final name = (doc.data()['fullName'] ?? '—')
                              .toString();
                          // --- CAMBIO ---
                          // Guardamos la asociación Ref -> Snapshot
                          snapshotMap[doc.reference] = doc;
                          // --- FIN CAMBIO ---
                          items.add(
                            DropdownMenuItem(
                              // --- CAMBIO ---
                              // El valor es la Referencia
                              value: doc.reference,
                              // --- FIN CAMBIO ---
                              child: Text(name),
                            ),
                          );
                        }
                      }
                      return DropdownButtonFormField<DocumentReference>(
                        // <-- CAMBIO TIPO
                        // --- CAMBIO ---
                        // El valor es la Referencia
                        value: _selectedCustomerRef,
                        // --- FIN CAMBIO ---
                        items: items,
                        // --- CAMBIO ---
                        // Al cambiar, guardamos AMBOS: la Ref y el Snapshot asociado
                        onChanged: (v) => setState(() {
                          _selectedCustomerRef = v;
                          _selectedCustomerSnapshot = v == null
                              ? null
                              : snapshotMap[v];
                        }),
                        // --- FIN CAMBIO ---
                        decoration: const InputDecoration(
                          labelText: 'Cliente *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null ? 'Requerido' : null,
                      );
                    },
                  ),
                  gap,
                  // ... (resto de los TextFormField no cambian) ...
                  TextFormField(
                    controller: _problem,
                    decoration: const InputDecoration(
                      labelText: 'Descripción del problema *',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 2,
                    maxLines: 5,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  gap,
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
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                    ],
                  ),
                  gap,
                  TextFormField(
                    controller: _imei,
                    decoration: const InputDecoration(
                      labelText: 'IMEI/Serie',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  gap,
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _priority,
                          decoration: const InputDecoration(
                            labelText: 'Prioridad',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Normal')),
                            DropdownMenuItem(value: 1, child: Text('Alta')),
                            DropdownMenuItem(value: 2, child: Text('Urgente')),
                            DropdownMenuItem(value: 3, child: Text('Crítica')),
                          ],
                          onChanged: (v) => setState(() => _priority = v ?? 0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickPromisedAt,
                          icon: const Icon(Icons.event),
                          label: Text(
                            _promisedAt == null
                                ? 'Fecha de entrega'
                                : _promisedAt!.toString().substring(0, 16),
                          ),
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
                    label: const Text('Crear orden'),
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
