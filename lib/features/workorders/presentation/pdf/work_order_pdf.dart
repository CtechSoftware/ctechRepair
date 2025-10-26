import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // <--- AÑADIDO para BuildContext y SnackBar
import 'package:flutter/services.dart'
    show rootBundle; // <--- AÑADIDO para cargar fuentes
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

// 🔹 Ajusta esta ruta si tu refs.dart está en otro lugar
import '../../../../core/refs.dart'; // contiene shopRef

// 🔹 Tipos de plantilla disponibles
enum PdfKind { workOrder, deliveryNoPrices, estimateWithPrices }

class WorkOrderPdf {
  static final _df = DateFormat('dd/MM/yyyy HH:mm');

  // Formato de moneda Perú
  static final _moneyFmt = NumberFormat.currency(
    locale: 'es_PE',
    symbol: 'S/ ',
    decimalDigits: 2,
  );
  static String _money(num v) => _moneyFmt.format(v);

  /// Genera y comparte el PDF de una orden.
  /// kind:
  ///   - PdfKind.workOrder         → Orden completa (precios, pagos, totales)
  ///   - PdfKind.deliveryNoPrices   → Entrega sin precios (sin pagos, sin totales)
  ///   - PdfKind.estimateWithPrices → Presupuesto con precios (sin pagos)
  static Future<void> generateAndShare({
    required BuildContext context, // <--- AÑADIDO
    required String workOrderId,
    Map<String, dynamic>? initialOrderData,
    PdfKind kind = PdfKind.workOrder,
  }) async {
    // --- MANEJO DE ERRORES (AÑADIDO) ---
    try {
      final db = FirebaseFirestore.instance;

      // ----- 0) Cargar Fuentes (¡NUEVO!) -----
      // Esto soluciona el error de caracteres '☒'
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final ttfFont = pw.Font.ttf(fontData);
      final boldFontData = await rootBundle.load(
        'assets/fonts/Roboto-Bold.ttf',
      );
      final ttfBoldFont = pw.Font.ttf(boldFontData);

      // ----- 1) Datos de tienda (nombre, logo, RUC, dirección, teléfono, IGV)
      String shopName = 'Mi Taller';
      String? logoUrl;
      String shopAddress = '';
      String shopPhone = '';
      String shopRuc = '';
      double igvRate = 0.18; // 18% por defecto
      bool pricesIncludeIgv = true; // asume precios con IGV incluido

      try {
        final shopSnap = await shopRef.get();
        final sdata = shopSnap.data() as Map<String, dynamic>?;
        if (sdata != null) {
          shopName = (sdata['name'] ?? shopName).toString();
          final raw = (sdata['logoUrl'] ?? '').toString().trim();
          logoUrl = raw.isEmpty ? null : raw;
          shopAddress = (sdata['address'] ?? '').toString();
          shopPhone = (sdata['phone'] ?? '').toString();
          shopRuc = (sdata['ruc'] ?? '').toString();

          if (sdata['igvRate'] != null) {
            igvRate = (sdata['igvRate'] as num).toDouble(); // ej. 0.18
          }
          final incl = sdata['pricesIncludeIgv'];
          if (incl is bool) pricesIncludeIgv = incl;
        }
      } catch (_) {}

      final logoImage = (logoUrl == null) ? null : await networkImage(logoUrl!);

      // ----- 2) Datos de la orden
      final woRef = db.collection('workOrders').doc(workOrderId);

      Map<String, dynamic> order;
      if (initialOrderData != null) {
        order = initialOrderData;
      } else {
        final snap = await woRef.get();
        if (!snap.exists) {
          throw Exception('Orden no encontrada');
        }
        order = snap.data() as Map<String, dynamic>;
      }

      final createdAt = (order['createdAt'] as Timestamp?)?.toDate();
      final promisedAt = (order['promisedAt'] as Timestamp?)?.toDate();
      final status = (order['status'] ?? 'new').toString();
      final priority = (order['priority'] ?? 0).toString();

      final customerName = (order['customerName'] ?? '').toString();
      final customerDocId = (order['customerDocId'] ?? '').toString();
      final phone = (order['customerPhone'] ?? '').toString();

      final brand = (order['deviceBrand'] ?? '').toString();
      final model = (order['deviceModel'] ?? '').toString();
      final imei = (order['deviceImei'] ?? '').toString();
      final problem = (order['problemDescription'] ?? '—').toString();

      double itemsTotal = (order['itemsTotal'] ?? 0).toDouble();
      double paidTotal = (order['paidTotal'] ?? 0).toDouble();
      double balance = (order['balance'] ?? (itemsTotal - paidTotal))
          .toDouble();

      // ----- 3) Ítems
      final itemsSnap = await woRef
          .collection('items')
          .orderBy('createdAt', descending: false)
          .get();
      final items = itemsSnap.docs.map((d) => d.data()).toList();

      if (itemsTotal == 0) {
        itemsTotal = 0;
        for (final it in items) {
          final qty = (it['qty'] ?? 1).toDouble();
          final unitPrice = (it['unitPrice'] ?? it['price'] ?? 0).toDouble();
          itemsTotal += qty * unitPrice;
        }
      }

      // ----- 4) Pagos
      final paySnap = await woRef
          .collection('payments')
          .orderBy('receivedAt', descending: false)
          .get();
      final payments = paySnap.docs.map((d) => d.data()).toList();

      if (paidTotal == 0 && payments.isNotEmpty) {
        paidTotal = 0;
        for (final p in payments) {
          paidTotal += (p['amount'] ?? 0).toDouble();
        }
      }

      // ---------- 5) Plantillas ----------
      final bool showPrices;
      final bool showPayments;
      final bool showTotals;
      final String docTitle;

      switch (kind) {
        case PdfKind.workOrder:
          docTitle = 'Orden de trabajo';
          showPrices = true;
          showPayments = true;
          showTotals = true;
          break;
        case PdfKind.deliveryNoPrices:
          docTitle = 'Constancia de Entrega';
          showPrices = false;
          showPayments = false;
          showTotals = false;
          paidTotal = 0; // no mostramos pagos
          break;
        case PdfKind.estimateWithPrices:
          docTitle = 'Presupuesto';
          showPrices = true;
          showPayments = false; // presupuesto no muestra pagos
          showTotals = true;
          paidTotal = 0; // saldo = total
          break;
      }

      // ----- 6) IGV y totales
      double subTotal, igvAmount, grandTotal;
      if (pricesIncludeIgv) {
        subTotal = itemsTotal / (1 + igvRate);
        igvAmount = itemsTotal - subTotal;
        grandTotal = itemsTotal;
      } else {
        subTotal = itemsTotal;
        igvAmount = subTotal * igvRate;
        grandTotal = subTotal + igvAmount;
      }
      balance = grandTotal - paidTotal;

      // ----- 7) Construcción del PDF -----
      // --- (AÑADIDO) Se aplica el tema con las fuentes ---
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: ttfFont, bold: ttfBoldFont),
      );
      String _fmtDate(DateTime? d) => d == null ? '—' : _df.format(d);

      final header = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (logoImage != null)
                pw.Container(
                  width: 60,
                  height: 60,
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(logoImage),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    shopName,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (shopRuc.isNotEmpty)
                    pw.Text(
                      'RUC: $shopRuc',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  if (shopAddress.isNotEmpty)
                    pw.Text(
                      shopAddress,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  if (shopPhone.isNotEmpty)
                    pw.Text(
                      'Tel: $shopPhone',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  pw.SizedBox(height: 2),
                  pw.Text(docTitle, style: const pw.TextStyle(fontSize: 12)),
                  pw.Text(
                    '#$workOrderId',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          pw.BarcodeWidget(
            data: workOrderId, // cambia por una URL pública si quieres
            barcode: pw.Barcode.qrCode(),
            width: 70,
            height: 70,
          ),
        ],
      );

      final custBox = pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: _sectionDeco(),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Cliente',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(customerName.isEmpty ? '—' : customerName),
            if (customerDocId.isNotEmpty) pw.Text('Doc: $customerDocId'),
            if (phone.isNotEmpty) pw.Text('Tel: $phone'),
          ],
        ),
      );

      final orderBox = pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: _sectionDeco(),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Orden',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Estado: $status'),
            pw.Text('Prioridad: $priority'),
            pw.Text('Creada: ${_fmtDate(createdAt)}'),
            pw.Text('Entrega: ${_fmtDate(promisedAt)}'),
            pw.SizedBox(height: 2),
            if (showPrices)
              pw.Text(
                'IGV: ${(igvRate * 100).toStringAsFixed(0)}%  '
                '${pricesIncludeIgv ? "(incluido en precios)" : "(se agrega al subtotal)"}',
              ),
          ],
        ),
      );

      // Tabla de ítems (condicional con/sin precios)
      final itemsTable = showPrices
          ? pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(32), // Cant.
                1: const pw.FlexColumnWidth(), // Descripción
                2: const pw.FixedColumnWidth(70), // P. Unit
                3: const pw.FixedColumnWidth(70), // Importe
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _th('Cant.'),
                    _th('Descripción'),
                    _th('P. Unit', alignRight: true),
                    _th('Importe', alignRight: true),
                  ],
                ),
                if (items.isEmpty)
                  pw.TableRow(
                    children: [
                      _td('—'),
                      _td('Sin ítems'),
                      _td('—', alignRight: true),
                      _td('—', alignRight: true),
                    ],
                  )
                else
                  ...items.map((it) {
                    final desc = (it['name'] ?? it['description'] ?? '—')
                        .toString();
                    final qty = (it['qty'] ?? 1).toDouble();
                    final unit = (it['unitPrice'] ?? it['price'] ?? 0)
                        .toDouble();
                    final total = qty * unit;
                    return pw.TableRow(
                      children: [
                        _td(
                          qty.toStringAsFixed(
                            qty.truncateToDouble() == qty ? 0 : 2,
                          ),
                        ),
                        _td(desc),
                        _td(_money(unit), alignRight: true),
                        _td(_money(total), alignRight: true),
                      ],
                    );
                  }),
              ],
            )
          : pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(32), // Cant.
                1: const pw.FlexColumnWidth(), // Descripción
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [_th('Cant.'), _th('Descripción')],
                ),
                if (items.isEmpty)
                  pw.TableRow(children: [_td('—'), _td('Sin ítems')])
                else
                  ...items.map((it) {
                    final desc = (it['name'] ?? it['description'] ?? '—')
                        .toString();
                    final qty = (it['qty'] ?? 1).toDouble();
                    return pw.TableRow(
                      children: [
                        _td(
                          qty.toStringAsFixed(
                            qty.truncateToDouble() == qty ? 0 : 2,
                          ),
                        ),
                        _td(desc),
                      ],
                    );
                  }),
              ],
            );

      // Pagos (solo si corresponde)
      final paymentsTable = pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(95), // Fecha
          1: const pw.FixedColumnWidth(70), // Monto
          2: const pw.FlexColumnWidth(), // Método / Nota
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _th('Fecha'),
              _th('Monto', alignRight: true),
              _th('Método / Nota'),
            ],
          ),
          if (payments.isEmpty)
            pw.TableRow(
              children: [
                _td('—'),
                _td('—', alignRight: true),
                _td('Sin pagos'),
              ],
            )
          else
            ...payments.map((p) {
              final when = (p['receivedAt'] as Timestamp?)?.toDate();
              final amount = (p['amount'] ?? 0).toDouble();
              final method = (p['method'] ?? '').toString();
              final note = (p['note'] ?? '').toString();
              return pw.TableRow(
                children: [
                  _td(_fmtDate(when)),
                  _td(_money(amount), alignRight: true),
                  _td([method, note].where((s) => s.isNotEmpty).join(' · ')),
                ],
              );
            }),
        ],
      );

      // Totales (solo si corresponde)
      final totalsBox = pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: _sectionDeco(),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _totalRow('Subtotal', _money(subTotal)),
            _totalRow(
              'IGV ${(igvRate * 100).toStringAsFixed(0)}%',
              _money(igvAmount),
            ),
            pw.Divider(),
            _totalRow('Total', _money(grandTotal), bold: true),
            _totalRow('Pagado', _money(paidTotal)),
            pw.Divider(),
            _totalRow('Saldo', _money(balance), bold: true),
          ],
        ),
      );

      // ---- Página ----
      const baseStyle = pw.TextStyle(fontSize: 10);

      pdf.addPage(
        pw.MultiPage(
          pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(24)),
          build: (context) => [
            pw.DefaultTextStyle(
              style: baseStyle,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  header,
                  pw.SizedBox(height: 12),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(child: custBox),
                      pw.SizedBox(width: 12),
                      pw.Expanded(child: orderBox),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: _sectionDeco(),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Equipo',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Marca/Modelo: ${(brand + ' ' + model).trim().isEmpty ? '—' : (brand + ' ' + model).trim()}',
                        ),
                        pw.Text('IMEI/Serie: ${imei.isEmpty ? '—' : imei}'),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Problema:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(problem),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'Ítems / Servicios',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  itemsTable,
                  if (kind == PdfKind.deliveryNoPrices) ...[
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Constancia: El equipo fue entregado al cliente en conformidad. '
                      'Este documento no muestra montos.',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                  if (showPayments) ...[
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'Pagos',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    paymentsTable,
                  ],
                  if (showTotals) ...[pw.SizedBox(height: 12), totalsBox],
                  pw.SizedBox(height: 16),
                  pw.Row(
                    children: [
                      pw.Expanded(child: _signatureBox('Cliente')),
                      pw.SizedBox(width: 24),
                      pw.Expanded(child: _signatureBox('Técnico')),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'Términos: Garantía limitada a la intervención realizada. No nos responsabilizamos por daño previo o pérdida de datos.',
                  ),
                ],
              ),
            ),
          ],
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Generado el ${_df.format(DateTime.now())}'),
          ),
        ),
      );

      // Compartir / Imprimir
      final Uint8List bytes = await pdf.save();
      await Printing.sharePdf(bytes: bytes, filename: 'orden_$workOrderId.pdf');
      // Alternativa: vista previa/impresión directa
      // await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      // <--- BLOQUE CATCH AÑADIDO
      // Si algo falla, informa al usuario
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ------ Helpers de UI PDF ------
  static pw.BoxDecoration _sectionDeco() => pw.BoxDecoration(
    border: pw.Border.all(color: PdfColors.grey400),
    borderRadius: pw.BorderRadius.circular(6),
  );

  static pw.Widget _th(String text, {bool alignRight = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );

  static pw.Widget _td(String text, {bool alignRight = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );

  static pw.Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    );
  }

  static pw.Widget _signatureBox(String who) => pw.Container(
    height: 60,
    padding: const pw.EdgeInsets.all(8),
    decoration: _sectionDeco(),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [pw.Spacer(), pw.Divider(), pw.Text('Firma $who')],
    ),
  );
}
