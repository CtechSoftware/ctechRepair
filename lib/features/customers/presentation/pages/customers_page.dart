// lib/features/customers/presentation/pages/customers_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'edit_customer_page.dart';
import '../../../../core/refs.dart';
import 'add_customer_page.dart';
import 'package:ctech_repair/features/inventory/presentation/pages/inventory_page.dart';
import 'package:ctech_repair/features/workorders/presentation/pages/work_orders_page.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _customersStream() {
    return FirebaseFirestore.instance
        .collection('customers')
        .where('shopId', isEqualTo: shopRef)
        .orderBy('fullName') // requiere índice compuesto (ya lo creaste)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Órdenes',
            icon: const Icon(Icons.build_outlined),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const WorkOrdersPage()));
            },
          ),
          // 👇 Botón para abrir Inventario
          IconButton(
            tooltip: 'Inventario',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const InventoryPage()));
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _customersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Sin clientes aún'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = docs[i].data();
              final subtitle = [
                if ((c['phone'] ?? '').toString().isNotEmpty) c['phone'],
                if ((c['email'] ?? '').toString().isNotEmpty) c['email'],
              ].join(' · ');
              return ListTile(
                title: Text(c['fullName'] ?? '—'),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final doc = docs[i];
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditCustomerPage(
                        customerId: doc.id,
                        initialData: doc.data(),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddCustomerPage()),
          );
          if (saved == true && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Cliente registrado')));
          }
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
