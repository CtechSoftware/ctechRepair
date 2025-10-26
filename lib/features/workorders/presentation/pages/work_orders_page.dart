// lib/features/workorders/presentation/pages/work_orders_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/refs.dart';
import 'add_work_order_page.dart';
import 'shop_settings_page.dart';
import 'work_order_detail_page.dart';

// Qué campo usar para el filtro de fecha
enum DateField { createdAt, promisedAt }

const Map<String, String> kStatusLabels = {
  'new': 'Nueva',
  'diagnostic': 'Diagnóstico',
  'waiting_parts': 'Esperando repuestos',
  'in_progress': 'En curso',
  'ready': 'Lista',
  'delivered': 'Entregada',
  'cancelled': 'Cancelada',
};

class WorkOrdersPage extends StatefulWidget {
  const WorkOrdersPage({super.key});

  @override
  State<WorkOrdersPage> createState() => _WorkOrdersPageState();
}

class _WorkOrdersPageState extends State<WorkOrdersPage> {
  // --------- Filtros ----------
  String? _status; // 'new', 'diagnostic', ...
  int? _priority; // 0..3
  DateTimeRange? _range; // creado entre fechas (inclusive)
  DateField _dateField = DateField.createdAt; // por defecto

  // Últimos docs mostrados (para export)
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastDocs = [];

  // --------- Búsqueda local ----------
  final _searchCtrl = TextEditingController();
  String _search = ''; // texto a buscar (local)
  Timer? _debounce;

  final _df = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // --------- Debounce ----------
  void _onSearchChangedDebounced(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _search = v);
    });
  }

  // --------- Query base (sin búsqueda local) ----------
  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('workOrders')
        .where('shopId', isEqualTo: shopRef);

    if (_status != null) q = q.where('status', isEqualTo: _status);
    if (_priority != null) q = q.where('priority', isEqualTo: _priority);

    final dateField = _dateField == DateField.createdAt
        ? 'createdAt'
        : 'promisedAt';

    if (_range != null) {
      final start = DateTime(
        _range!.start.year,
        _range!.start.month,
        _range!.start.day,
      );
      final endExclusive = DateTime(
        _range!.end.year,
        _range!.end.month,
        _range!.end.day,
      ).add(const Duration(days: 1));

      q = q
          .where(dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where(dateField, isLessThan: Timestamp.fromDate(endExclusive))
          .orderBy(dateField, descending: true);
    } else {
      q = q.orderBy(dateField, descending: true);
    }

    return q.limit(100);
  }

  // --------- Búsqueda local en memoria ----------
  bool _matchesSearch(Map<String, dynamic> d) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;

    final customerName = (d['customerName'] ?? '').toString();
    final cust = d['customer'];
    final fallbackName = (cust is Map<String, dynamic>)
        ? ((cust['fullName'] ?? cust['name'] ?? '').toString())
        : '';

    final fields = <String>[
      customerName.isNotEmpty ? customerName : fallbackName, // cliente
      (d['number'] ?? '').toString(), // si numeras WO
      (d['problemDescription'] ?? '').toString(),
      (d['deviceImei'] ?? '').toString(),
      (d['deviceBrand'] ?? '').toString(),
      (d['deviceModel'] ?? '').toString(),
    ];
    return fields.any((s) => s.toLowerCase().contains(q));
  }

  // --------- Export CSV (sin lecturas extra) ----------
  Future<void> _exportCsv() async {
    if (_lastDocs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay órdenes para exportar')),
        );
      }
      return;
    }

    try {
      final dfDate = DateFormat('yyyy-MM-dd HH:mm');
      final nowStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      final rows = <List<dynamic>>[
        [
          'ID',
          'Número',
          'Creada',
          'Promesa',
          'Estado',
          'Prioridad',
          'Cliente',
          'Equipo',
          'Problema',
          'IMEI',
          'ItemsTotal',
          'Pagado',
          'Balance',
        ],
      ];

      for (final doc in _lastDocs) {
        final d = doc.data();

        final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
        final promisedAt = (d['promisedAt'] as Timestamp?)?.toDate();

        final status = (d['status'] ?? '').toString();
        final priority = (d['priority'] ?? '').toString();

        // Nombre sin lecturas:
        String name = (d['customerName'] ?? '').toString().trim();
        if (name.isEmpty) {
          final cust = d['customer'];
          if (cust is Map<String, dynamic>) {
            name = (cust['fullName'] ?? cust['name'] ?? '').toString().trim();
          }
        }
        if (name.isEmpty) name = '—';

        final brand = (d['deviceBrand'] ?? '').toString();
        final model = (d['deviceModel'] ?? '').toString();
        final device = [brand, model].where((s) => s.isNotEmpty).join(' ');

        final problem = (d['problemDescription'] ?? '').toString();
        final imei = (d['deviceImei'] ?? '').toString();

        final itemsTotal = (d['itemsTotal'] ?? 0).toDouble();
        final paidTotal = (d['paidTotal'] ?? 0).toDouble();
        final balance = (d['balance'] ?? (itemsTotal - paidTotal)).toDouble();

        rows.add([
          doc.id,
          (d['number'] ?? '').toString(),
          createdAt == null ? '' : dfDate.format(createdAt),
          promisedAt == null ? '' : dfDate.format(promisedAt),
          status,
          priority,
          name,
          device,
          problem,
          imei,
          itemsTotal.toStringAsFixed(2),
          paidTotal.toStringAsFixed(2),
          balance.toStringAsFixed(2),
        ]);
      }

      final csv = const ListToCsvConverter(eol: '\n').convert(rows);
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/work_orders_$nowStamp.csv';
      await File(path).writeAsString(csv, encoding: utf8);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Órdenes exportadas ($nowStamp)',
        subject: 'Exportación de órdenes',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  // --------- Chips de filtros activos (una línea) ----------
  Widget _activeFiltersChips() {
    final chips = <Widget>[];

    if (_status != null) {
      chips.add(
        InputChip(
          label: Text('Estado: ${kStatusLabels[_status] ?? _status}'),
          onDeleted: () => setState(() => _status = null),
        ),
      );
    }
    if (_priority != null) {
      chips.add(
        InputChip(
          label: Text('Prioridad: $_priority'),
          onDeleted: () => setState(() => _priority = null),
        ),
      );
    }
    if (_range != null) {
      final df = DateFormat('dd/MM');
      chips.add(
        InputChip(
          label: Text(
            'Fecha: ${df.format(_range!.start)}–${df.format(_range!.end)}'
            ' (${_dateField == DateField.createdAt ? "creación" : "promesa"})',
          ),
          onDeleted: () => setState(() => _range = null),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ...chips.map(
              (c) =>
                  Padding(padding: const EdgeInsets.only(right: 8), child: c),
            ),
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.layers_clear),
              label: const Text('Limpiar'),
            ),
          ],
        ),
      ),
    );
  }

  // --------- BottomSheet de filtros ----------
  void _openFiltersSheet() async {
    String? tmpStatus = _status;
    int? tmpPriority = _priority;
    DateField tmpDateField = _dateField;
    DateTimeRange? tmpRange = _range;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> pickRange() async {
              final initial =
                  tmpRange ??
                  DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 7)),
                    end: DateTime.now(),
                  );
              final picked = await showDateRangePicker(
                context: ctx,
                firstDate: DateTime(2020, 1, 1),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: initial,
                helpText: tmpDateField == DateField.createdAt
                    ? 'Rango por creación'
                    : 'Rango por promesa',
                saveText: 'Aplicar',
              );
              if (picked != null) setModal(() => tmpRange = picked);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Filtros',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setModal(() {
                                  tmpStatus = null;
                                  tmpPriority = null;
                                  tmpRange = null;
                                });
                              },
                              child: const Text('Limpiar'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        const Text(
                          'Estado',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Todos'),
                              selected: tmpStatus == null,
                              onSelected: (_) =>
                                  setModal(() => tmpStatus = null),
                            ),
                            for (final entry in kStatusLabels.entries)
                              ChoiceChip(
                                label: Text(entry.value),
                                selected: tmpStatus == entry.key,
                                onSelected: (_) =>
                                    setModal(() => tmpStatus = entry.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'Prioridad',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Todas'),
                              selected: tmpPriority == null,
                              onSelected: (_) =>
                                  setModal(() => tmpPriority = null),
                            ),
                            for (final p in [0, 1, 2, 3])
                              ChoiceChip(
                                label: Text('$p'),
                                selected: tmpPriority == p,
                                onSelected: (_) =>
                                    setModal(() => tmpPriority = p),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'Campo de fecha',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Creación'),
                              selected: tmpDateField == DateField.createdAt,
                              onSelected: (_) => setModal(
                                () => tmpDateField = DateField.createdAt,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('Promesa'),
                              selected: tmpDateField == DateField.promisedAt,
                              onSelected: (_) => setModal(
                                () => tmpDateField = DateField.promisedAt,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'Rango de fechas',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: pickRange,
                                icon: const Icon(Icons.event),
                                label: Text(
                                  tmpRange == null
                                      ? 'Elegir rango'
                                      : '${DateFormat('dd/MM').format(tmpRange!.start)} – '
                                            '${DateFormat('dd/MM').format(tmpRange!.end)}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (tmpRange != null)
                              IconButton(
                                tooltip: 'Quitar rango',
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setModal(() => tmpRange = null),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                final now = DateTime.now();
                                final start = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                );
                                setModal(
                                  () => tmpRange = DateTimeRange(
                                    start: start,
                                    end: start,
                                  ),
                                );
                              },
                              child: const Text('Hoy'),
                            ),
                            OutlinedButton(
                              onPressed: () {
                                final now = DateTime.now();
                                final start = now.subtract(
                                  const Duration(days: 7),
                                );
                                setModal(
                                  () => tmpRange = DateTimeRange(
                                    start: DateTime(
                                      start.year,
                                      start.month,
                                      start.day,
                                    ),
                                    end: DateTime(now.year, now.month, now.day),
                                  ),
                                );
                              },
                              child: const Text('Últimos 7'),
                            ),
                            OutlinedButton(
                              onPressed: () {
                                final now = DateTime.now();
                                final start = now.subtract(
                                  const Duration(days: 30),
                                );
                                setModal(
                                  () => tmpRange = DateTimeRange(
                                    start: DateTime(
                                      start.year,
                                      start.month,
                                      start.day,
                                    ),
                                    end: DateTime(now.year, now.month, now.day),
                                  ),
                                );
                              },
                              child: const Text('Últimos 30'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                label: const Text('Aplicar'),
                                onPressed: () {
                                  setState(() {
                                    _status = tmpStatus;
                                    _priority = tmpPriority;
                                    _dateField = tmpDateField;
                                    _range = tmpRange;
                                  });
                                  Navigator.pop(ctx);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int _activeFiltersCount() {
    var c = 0;
    if (_status != null) c++;
    if (_priority != null) c++;
    if (_range != null) c++;
    return c;
  }

  void _clearFilters() {
    setState(() {
      _status = null;
      _priority = null;
      _range = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _buildQuery();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes de trabajo'),
        actions: [
          IconButton(
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
          ),
          // Botón Filtros con badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Filtros',
                icon: const Icon(Icons.tune),
                onPressed: _openFiltersSheet,
              ),
              if (_activeFiltersCount() > 0)
                Positioned(
                  right: 10,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_activeFiltersCount()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'settings') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShopSettingsPage()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: Text('Configuración de la tienda'),
              ),
            ],
          ),
        ],
        // 🔎 Barra de búsqueda integrada al AppBar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChangedDebounced,
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    'Buscar (cliente / número / problema / IMEI / marca / modelo)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _debounce?.cancel();
                          setState(() {
                            _search = '';
                            _searchCtrl.clear();
                          });
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),

      body: Column(
        children: [
          _activeFiltersChips(),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final all = snap.data?.docs ?? [];

                // BÚSQUEDA LOCAL sobre los docs recibidos
                final docs = all
                    .where((doc) => _matchesSearch(doc.data()))
                    .toList();
                _lastDocs = docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No hay órdenes con esos filtros/búsqueda'),
                  );
                }

                // Contadores por estado (en base a docs filtrados)
                final statuses = [
                  'new',
                  'diagnostic',
                  'waiting_parts',
                  'in_progress',
                  'ready',
                  'delivered',
                  'cancelled',
                ];
                final counts = {for (final s in statuses) s: 0};
                for (final d in docs) {
                  final st = (d.data()['status'] ?? 'new').toString();
                  if (counts.containsKey(st)) counts[st] = counts[st]! + 1;
                }
                final total = docs.length;

                return Column(
                  children: [
                    // Chips de resumen
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text('Todos ($total)'),
                              selected: _status == null,
                              onSelected: (_) => setState(() => _status = null),
                            ),
                            const SizedBox(width: 8),
                            ...statuses.map(
                              (s) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    '${kStatusLabels[s] ?? s} (${counts[s]})',
                                  ),
                                  selected: _status == s,
                                  onSelected: (_) =>
                                      setState(() => _status = s),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    // Lista de órdenes
                    Expanded(
                      child: ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final d = doc.data();

                          final status = (d['status'] ?? 'new').toString();
                          final number = (d['number'] ?? '').toString();

                          final problem = (d['problemDescription'] ?? '—')
                              .toString();
                          final brand = (d['deviceBrand'] ?? '').toString();
                          final model = (d['deviceModel'] ?? '').toString();
                          final promisedAt = d['promisedAt'] as Timestamp?;
                          final createdAt = d['createdAt'] as Timestamp?;

                          // Cliente (denormalizado con fallback)
                          String customer = (d['customerName'] ?? '')
                              .toString()
                              .trim();
                          if (customer.isEmpty) {
                            final cust = d['customer'];
                            if (cust is Map<String, dynamic>) {
                              customer =
                                  (cust['fullName'] ?? cust['name'] ?? '')
                                      .toString()
                                      .trim();
                            }
                          }

                          final device = [
                            brand,
                            model,
                          ].where((s) => s.isNotEmpty).join(' ');

                          final parts = <String>[];
                          if (customer.isNotEmpty) parts.add(customer);
                          if (device.isNotEmpty) parts.add(device);
                          if (promisedAt != null) {
                            parts.add(
                              'Entrega: ${_df.format(promisedAt.toDate())}',
                            );
                          }
                          if (createdAt != null) {
                            parts.add(
                              'Creada: ${_df.format(createdAt.toDate())}',
                            );
                          }

                          return ListTile(
                            title: Text(
                              number.isNotEmpty
                                  ? '$number · $problem'
                                  : problem,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              parts.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: _StatusChip(status: status),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => WorkOrderDetailPage(
                                    workOrderId: doc.id,
                                    initialData: d,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddWorkOrderPage()),
          );
          if (saved == true && context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Orden creada')));
          }
        },
        child: const Icon(Icons.playlist_add),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'new' => 'Nueva',
      'diagnostic' => 'Diagnóstico',
      'waiting_parts' => 'Esperando repuestos',
      'in_progress' => 'En curso',
      'ready' => 'Lista',
      'delivered' => 'Entregada',
      'cancelled' => 'Cancelada',
      _ => status,
    };
    return Chip(label: Text(label));
  }
}
