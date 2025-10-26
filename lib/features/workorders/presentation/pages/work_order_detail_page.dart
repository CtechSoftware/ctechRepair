import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'add_work_order_item_page.dart';
import 'edit_work_order_item_page.dart';
import 'add_work_order_payment_page.dart';
import 'edit_work_order_payment_page.dart';
import 'add_work_order_attachment_page.dart';
import 'package:firebase_storage/firebase_storage.dart'; // para borrar archivos
import 'package:ctech_repair/features/workorders/presentation/pdf/work_order_pdf.dart';

class WorkOrderDetailPage extends StatefulWidget {
  const WorkOrderDetailPage({
    super.key,
    required this.workOrderId,
    required this.initialData,
  });

  final String workOrderId;
  final Map<String, dynamic> initialData;

  @override
  State<WorkOrderDetailPage> createState() => _WorkOrderDetailPageState();
}

class _WorkOrderDetailPageState extends State<WorkOrderDetailPage> {
  static const _statuses = <String, String>{
    'new': 'Nueva',
    'diagnostic': 'Diagnóstico',
    'waiting_parts': 'Esperando repuestos',
    'in_progress': 'En curso',
    'ready': 'Lista',
    'delivered': 'Entregada',
    'cancelled': 'Cancelada',
  };

  late String _status;
  final _note = TextEditingController();
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _woRef => FirebaseFirestore
      .instance
      .collection('workOrders')
      .doc(widget.workOrderId);

  CollectionReference<Map<String, dynamic>> get _attachmentsRef =>
      _woRef.collection('attachments');

  CollectionReference<Map<String, dynamic>> get _itemsRef =>
      _woRef.collection('items');

  CollectionReference<Map<String, dynamic>> get _historyRef =>
      _woRef.collection('statusHistory');

  CollectionReference<Map<String, dynamic>> get _paymentsRef =>
      _woRef.collection('payments');

  @override
  void initState() {
    super.initState();
    _status = (widget.initialData['status'] ?? 'new').toString();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _updateStatus() async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final now = FieldValue.serverTimestamp();

      // 1) Actualiza el status en la orden
      await _woRef.update({'status': _status, 'updatedAt': now});

      // 2) Inserta un registro en el historial
      await _historyRef.add({
        'status': _status,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'userId': uid,
        'createdAt': now,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Estado actualizado')));
      Navigator.of(context).pop(true); // volver a la lista
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.message ?? e.code}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.initialData;
    final device = [
      (d['deviceBrand'] ?? '').toString(),
      (d['deviceModel'] ?? '').toString(),
    ].where((s) => s.isNotEmpty).join(' ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de orden'),
        actions: [
          IconButton(
            tooltip: 'Registrar pago',
            icon: const Icon(Icons.attach_money),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      AddWorkOrderPaymentPage(workOrderId: widget.workOrderId),
                ),
              );
              if (saved == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pago registrado')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Agregar ítem',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      AddWorkOrderItemPage(workOrderId: widget.workOrderId),
                ),
              );
              if (saved == true && mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Ítem agregado')));
              }
            },
          ),
          IconButton(
            tooltip: 'Agregar adjunto',
            icon: const Icon(Icons.attachment),
            onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AddWorkOrderAttachmentPage(
                    workOrderId: widget.workOrderId,
                  ),
                ),
              );
              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Adjunto agregado')),
                );
              }
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf),
            // --- 👇 CAMBIO AQUÍ ---
            // Se pasa el 'context' y se elimina el try/catch,
            // ya que el PDF ahora maneja sus propios errores.
            onSelected: (value) async {
              switch (value) {
                case 'full':
                  await WorkOrderPdf.generateAndShare(
                    context: context, // <-- AÑADIDO
                    workOrderId: widget.workOrderId,
                    kind: PdfKind.workOrder,
                  );
                  break;
                case 'delivery':
                  await WorkOrderPdf.generateAndShare(
                    context: context, // <-- AÑADIDO
                    workOrderId: widget.workOrderId,
                    kind: PdfKind.deliveryNoPrices,
                  );
                  break;
                case 'estimate':
                  await WorkOrderPdf.generateAndShare(
                    context: context, // <-- AÑADIDO
                    workOrderId: widget.workOrderId,
                    kind: PdfKind.estimateWithPrices,
                  );
                  break;
              }
            },
            // --- 👆 FIN DEL CAMBIO ---
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'full', child: Text('Orden (completa)')),
              PopupMenuItem(
                value: 'delivery',
                child: Text('Entrega (sin precios)'),
              ),
              PopupMenuItem(
                value: 'estimate',
                child: Text('Presupuesto (con precios)'),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (d['problemDescription'] ?? '—').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(device.isEmpty ? '—' : device),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: _statuses.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _status = v ?? _status),
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _saving ? null : _updateStatus,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Guardar estado'),
                ),
                const SizedBox(height: 24),
                // ... dentro de build(), antes del título "Historial":
                const SizedBox(height: 24),
                const Text(
                  'Adjuntos',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _attachmentsRef
                      .orderBy('uploadedAt', descending: true)
                      .snapshots(),
                  builder: (context, as) {
                    if (as.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final rows = as.data?.docs ?? [];
                    if (rows.isEmpty) return const Text('Sin adjuntos');
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rows.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                      itemBuilder: (context, i) {
                        final d = rows[i].data();
                        final url = (d['url'] ?? '').toString();
                        final caption = (d['caption'] ?? '').toString();
                        final path = (d['path'] ?? '').toString();
                        return GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) {
                                return Dialog(
                                  child: Stack(
                                    children: [
                                      InteractiveViewer(
                                        child: Image.network(
                                          url,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: IconButton(
                                          tooltip: 'Eliminar',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text(
                                                  'Eliminar adjunto',
                                                ),
                                                content: const Text(
                                                  'Esta acción no se puede deshacer.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text(
                                                      'Cancelar',
                                                    ),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Eliminar',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              try {
                                                await FirebaseStorage.instance
                                                    .ref(path)
                                                    .delete();
                                                await _attachmentsRef
                                                    .doc(rows[i].id)
                                                    .delete();
                                                if (context.mounted) {
                                                  Navigator.of(
                                                    context,
                                                  ).pop(); // cerrar el Dialog
                                                }
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Adjunto eliminado',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } on FirebaseException catch (e) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Error al eliminar: ${e.message ?? e.code}',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                      if (caption.isNotEmpty)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            color: Colors.black54,
                                            padding: const EdgeInsets.all(8),
                                            child: Text(
                                              caption,
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(url, fit: BoxFit.cover),
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 24),
                const Text(
                  'Pagos',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _paymentsRef
                      .orderBy(
                        'receivedAt',
                        descending: true,
                      ) // si pide índice, crea con el link
                      .snapshots(),
                  builder: (context, ps) {
                    if (ps.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final rows = ps.data?.docs ?? [];
                    if (rows.isEmpty) return const Text('Sin pagos aún');

                    double sum = 0;
                    final tiles = rows.map((p) {
                      final d = p.data();
                      final amt = (d['amount'] ?? 0).toDouble();
                      final method = (d['method'] ?? '—').toString();
                      final at = (d['receivedAt'] as Timestamp?)?.toDate();
                      sum += amt;
                      final methodLabel = switch (method) {
                        'cash' => 'Efectivo',
                        'card' => 'Tarjeta',
                        'transfer' => 'Transferencia',
                        'other' => 'Otro',
                        _ => method,
                      };
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(
                          'S/ ${amt.toStringAsFixed(2)} · $methodLabel',
                        ),
                        subtitle: at == null
                            ? null
                            : Text(at.toString().substring(0, 16)),
                        onTap: () async {
                          final ok = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => EditWorkOrderPaymentPage(
                                workOrderId: widget.workOrderId,
                                paymentId:
                                    p.id, // ← el id del documento de pago
                                initialData: d, // ← los datos del pago
                              ),
                            ),
                          );
                          if (ok == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Pago actualizado')),
                            );
                          }
                        },
                      );
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...tiles,
                        const Divider(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Total pagado: S/ ${sum.toStringAsFixed(2)}',
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),
                const Text(
                  'Ítems',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _itemsRef
                      .orderBy(
                        'createdAt',
                        descending: true,
                      ) // comenta si te pide índice
                      .snapshots(),
                  builder: (context, s) {
                    if (s.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final docs = s.data?.docs ?? [];
                    if (docs.isEmpty) return const Text('Sin ítems aún');

                    double sum = 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...docs.map((it) {
                          final d = it.data();
                          final type = (d['itemType'] ?? '').toString();
                          final desc = (d['description'] ?? '').toString();
                          final qty = (d['qty'] ?? 0).toString();
                          final unit = (d['unitPrice'] ?? 0).toString();
                          final tot = (d['total'] ?? 0).toDouble();
                          sum += tot;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              type == 'part' ? Icons.memory : Icons.build,
                            ),
                            title: Text(desc),
                            subtitle: Text('Cant: $qty · Unit: S/ $unit'),
                            trailing: Text('S/ ${tot.toStringAsFixed(2)}'),
                            onTap: () async {
                              final ok = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => EditWorkOrderItemPage(
                                    workOrderId: widget.workOrderId,
                                    itemId: it.id,
                                    initialData: d,
                                  ),
                                ),
                              );
                              if (ok == true && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Ítem actualizado'),
                                  ),
                                );
                              }
                            },
                          );
                        }),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Subtotal items: S/ ${sum.toStringAsFixed(2)}',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const Text(
                  'Historial',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _historyRef
                      .orderBy(
                        'createdAt',
                        descending: true,
                      ) // puede pedir índice
                      .limit(20)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final hs = snap.data?.docs ?? [];
                    if (hs.isEmpty) return const Text('Sin movimientos aún');
                    return Column(
                      children: hs.map((h) {
                        final s = (h['status'] ?? '').toString();
                        final note = (h['note'] ?? '').toString();
                        final label = _statuses[s] ?? s;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history),
                          title: Text(label),
                          subtitle: note.isEmpty ? null : Text(note),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
