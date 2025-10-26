// lib/features/inventory/presentation/pages/inventory_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/refs.dart';
import 'add_inventory_item_page.dart';
import 'package:ctech_repair/features/inventory/presentation/pages/edit_inventory_item_page.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    // Si Firestore pide índice: créalo para shopId (asc), name (asc)
    return FirebaseFirestore.instance
        .collection('inventoryItems')
        .where('shopId', isEqualTo: shopRef)
        .orderBy('name') // <- índice compuesto
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Sin ítems en inventario'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final name = (d['name'] ?? '—').toString();
              final sku = (d['sku'] ?? '').toString();
              final price = (d['price'] ?? 0).toString();
              final qty = (d['qtyOnHand'] ?? 0) as num;
              final minQty = (d['minQty'] ?? 0) as num;
              final low = qty <= minQty;

              return ListTile(
                title: Text(name),
                subtitle: Text(
                  [if (sku.isNotEmpty) 'SKU: $sku', 'S/ $price'].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (low)
                      const Icon(Icons.warning_amber, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text('Stock: $qty'),
                  ],
                ),
                onTap: () async {
                  final doc = docs[i];
                  final result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => EditInventoryItemPage(
                        itemId: doc.id,
                        initialData: doc.data(),
                      ),
                    ),
                  );
                  if (result == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ítem actualizado')),
                    );
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddInventoryItemPage()),
          );
          if (saved == true && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Ítem agregado')));
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
