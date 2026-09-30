import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'app_events.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

class HistorialVentasScreen extends StatefulWidget {
  const HistorialVentasScreen({super.key});

  @override
  State<HistorialVentasScreen> createState() => _HistorialVentasScreenState();
}

class _HistorialVentasScreenState extends State<HistorialVentasScreen> {
  List<dynamic> _facturasOriginales = [];
  List<dynamic> _facturasFiltradas = []; 
  
  bool _isLoading = true;
  
  // Hacemos las fechas "nullable" (pueden ser nulas para indicar "Todo el histórico")
  DateTime? _fechaInicio = DateTime.now();
  DateTime? _fechaFin = DateTime.now();
  String _filtroEstado = 'TODAS'; 
  String _etiquetaPeriodo = 'Hoy';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    AppEvents.refreshNotifier.addListener(_cargarDatos);
  }

  @override
  void dispose() {
    AppEvents.refreshNotifier.removeListener(_cargarDatos);
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      String queryParams = '';
      if (_fechaInicio != null && _fechaFin != null) {
        String inicioStr = DateFormat('yyyy-MM-dd').format(_fechaInicio!);
        String finStr = DateFormat('yyyy-MM-dd').format(_fechaFin!);
        queryParams = '?fecha_inicio=$inicioStr&fecha_fin=$finStr';
      }

      final resVentas = await http.get(Uri.parse('http://127.0.0.1:3000/api/facturas$queryParams'));
      
      if (mounted) {
        setState(() {
          _facturasOriginales = jsonDecode(resVentas.body);
          _aplicarFiltroEstado(_filtroEstado); 
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  // --- FILTROS RÁPIDOS DE FECHA ---
  void _setFiltroFecha(String tipo) {
    final now = DateTime.now();
    setState(() {
      if (tipo == 'HOY') {
        _fechaInicio = now;
        _fechaFin = now;
        _etiquetaPeriodo = 'Hoy';
      } else if (tipo == 'MES') {
        _fechaInicio = DateTime(now.year, now.month, 1);
        _fechaFin = DateTime(now.year, now.month + 1, 0); // Último día del mes
        _etiquetaPeriodo = 'Este Mes';
      } else if (tipo == 'TODO') {
        _fechaInicio = null;
        _fechaFin = null;
        _etiquetaPeriodo = 'Histórico Completo';
      }
    });
    
    if (tipo != 'PERIODO') {
      _cargarDatos();
    } else {
      _seleccionarFechasPersonalizadas();
    }
  }

  Future<void> _seleccionarFechasPersonalizadas() async {
    final DateTimeRange? rango = await showDateRangePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.input,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _fechaInicio != null && _fechaFin != null 
          ? DateTimeRange(start: _fechaInicio!, end: _fechaFin!) 
          : DateTimeRange(start: DateTime.now(), end: DateTime.now()),
      
      // --- MAGIA DE DISEÑO: Forzamos a que sea una ventana centrada ---
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500, // Ancho perfecto de ventana
              maxHeight: 600, // Alto proporcionado
            ),
            child: Theme(
              // Opcional: Le damos un toque más elegante a los colores
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: Colors.blue.shade700,
                  onPrimary: Colors.white,
                  onSurface: Colors.black87,
                ),
              ),
              child: child!,
            ),
          ),
        );
      },
    );

    if (rango != null) {
      setState(() {
        _fechaInicio = rango.start;
        _fechaFin = rango.end;
        _etiquetaPeriodo = "${DateFormat('dd/MM/yy').format(rango.start)} al ${DateFormat('dd/MM/yy').format(rango.end)}";
      });
      _cargarDatos();
    }
  }

  // --- FILTROS DE ESTADO ---
  void _aplicarFiltroEstado(String estado) {
    setState(() {
      _filtroEstado = estado;
      if (estado == 'TODAS') {
        _facturasFiltradas = List.from(_facturasOriginales);
      } else {
        _facturasFiltradas = _facturasOriginales.where((f) => f['estado'] == estado).toList();
      }
    });
  }

  String _formatearFecha(String fechaIso) {
    return DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.parse(fechaIso).toLocal());
  }

  // --- VER PRODUCTOS DE LA FACTURA ---
  void _verDetallesProductos(Map<String, dynamic> factura) {
    final List<dynamic> detalles = factura['DetalleFacturas'] ?? factura['DetalleFactura'] ?? factura['detalles_factura'] ?? [];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Productos - Factura ${factura['numero_factura'] ?? ''}'),
        content: SizedBox(
          width: 400,
          child: detalles.isEmpty
              ? const Padding(padding: EdgeInsets.all(20.0), child: Text('No hay detalles registrados.', textAlign: TextAlign.center))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: detalles.length,
                  itemBuilder: (context, index) {
                    final det = detalles[index];
                    final nombreProducto = det['Producto'] != null ? det['Producto']['nombre'] : 'Producto eliminado';
                    return ListTile(
                      leading: const Icon(Icons.shopping_bag, color: Colors.blue),
                      title: Text(nombreProducto, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${det['cantidad']} unid. a \$${det['precio_unitario_usd']}'),
                      trailing: Text('\$${det['subtotal_usd']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      )
    );
  }

Future<void> _generarReportePDF() async {
    if (_facturasFiltradas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay datos para exportar')));
      return;
    }

    final pdf = pw.Document();
    
    double ventasTotales = 0;
    double ventasTotalesBs = 0;

    for (var f in _facturasFiltradas) {
      if (f['estado'] != 'ANULADA') {
        ventasTotales += double.parse(f['total_usd'].toString());
        ventasTotalesBs += double.parse(f['total_bs'].toString());
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(30), // Márgenes un poco más pequeños
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Reporte de Ventas Fiscales', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text('Emitido: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}')
              ]
            )
          ),
          pw.Text('Periodo: $_etiquetaPeriodo', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          pw.Text('Filtro aplicado: $_filtroEstado', style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey)),
          pw.SizedBox(height: 15),
          
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            color: PdfColors.grey200,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Text('Facturas: ${_facturasFiltradas.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('TOTAL BS: Bs ${ventasTotalesBs.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text('TOTAL USD: \$${ventasTotales.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.green800)),
              ]
            )
          ),
          pw.SizedBox(height: 15),

          pw.TableHelper.fromTextArray(
            headers: ['N° Factura', 'Fecha', 'Cliente', 'Estado', 'Base (Bs)', 'IVA (Bs)', 'Total (Bs)', 'Total (\$)'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 9), // Fuente más pequeña para que quepan 8 columnas
            cellAlignment: pw.Alignment.centerLeft,
            data: _facturasFiltradas.map((f) {
              // Cálculos matemáticos extrayendo la tasa de la BD
              final tasa = double.tryParse(f['tasa_bcv'].toString()) ?? 1.0;
              final subtotalUsd = double.tryParse(f['subtotal_usd'].toString()) ?? 0.0;
              final ivaUsd = double.tryParse(f['iva_usd'].toString()) ?? 0.0;
              
              final baseBs = subtotalUsd * tasa;
              final ivaBs = ivaUsd * tasa;
              final totalBs = double.tryParse(f['total_bs'].toString()) ?? 0.0;
              final totalUsd = double.tryParse(f['total_usd'].toString()) ?? 0.0;

              // Acortamos el nombre del cliente si es muy largo
              String clienteStr = f['Cliente'] != null ? f['Cliente']['nombre'] : 'Contado';
              if (clienteStr.length > 15) clienteStr = '${clienteStr.substring(0, 15)}...';

              return [
                f['numero_factura'] ?? '',
                DateFormat('dd/MM/yy').format(DateTime.parse(f['createdAt']).toLocal()),
                clienteStr,
                f['estado'],
                baseBs.toStringAsFixed(2),
                ivaBs.toStringAsFixed(2),
                totalBs.toStringAsFixed(2),
                '\$${totalUsd.toStringAsFixed(2)}'
              ];
            }).toList(),
          )
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Reporte_Ventas_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf'
    );
  }

// --- DESCARGAR EXCEL ---
  Future<void> _descargarExcel() async {
    // Si estás usando variables para filtrar por fecha, puedes anexarlas así:
    // final url = Uri.parse('http://127.0.0.1:3000/api/facturas/exportar-excel?fecha_inicio=...&fecha_fin=...');
    
    final url = Uri.parse('http://127.0.0.1:3000/api/facturas/exportar-excel');
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo iniciar la descarga del Excel')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al descargar: $e')));
      }
    }
  }

  // --- ACCIONES DE FACTURA (COBRAR Y ANULAR) ---
  Future<void> _anularFactura(int id) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.put(Uri.parse('http://127.0.0.1:3000/api/facturas/anular/$id'));
      
      if (res.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Factura anulada con éxito y Nota de Crédito emitida'), backgroundColor: Colors.orange));
        _cargarDatos(); // Esto apaga el cargador al terminar
        AppEvents.dispararActualizacion();
      } else {
        // SOLUCIÓN: Mostrar el error del backend y APAGAR la carga
        if (mounted) {
          final errorMsg = jsonDecode(res.body)['mensaje'] ?? 'Error desconocido';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aviso: $errorMsg'), backgroundColor: Colors.red));
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  void _mostrarDialogoAnulacion(Map<String, dynamic> factura) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Factura', style: TextStyle(color: Colors.red)),
        content: Text('¿Estás seguro de anular la factura ${factura['numero_factura']}?\nLos productos regresarán al inventario.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () { Navigator.pop(ctx); _anularFactura(factura['id']); },
            child: const Text('Sí, Anular')
          )
        ]
      )
    );
  }

  Future<void> _procesarCobroFactura(int id, String metodo) async {
    setState(() => _isLoading = true);
    try {
      final bodyData = jsonEncode({"metodo_pago": metodo});
      final res = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/facturas/$id/pagar'),
        headers: {"Content-Type": "application/json"},
        body: bodyData
      );

      if (res.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Factura cobrada correctamente'), backgroundColor: Colors.green));
        _cargarDatos();
        AppEvents.dispararActualizacion();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
    }
  }

  void _mostrarDialogoCobro(Map<String, dynamic> factura) {
    String metodoPago = 'Transferencia';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Cobrar Factura ${factura['numero_factura']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total a cobrar: \$${factura['total_usd']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Método de Pago Final', border: OutlineInputBorder()),
                  initialValue: metodoPago,
                  items: ['Efectivo', 'Pago Móvil', 'Zelle', 'Punto de Venta', 'Transferencia'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => setStateDialog(() => metodoPago = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                onPressed: () { Navigator.pop(ctx); _procesarCobroFactura(factura['id'], metodoPago); },
                icon: const Icon(Icons.attach_money),
                label: const Text('Confirmar Cobro'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              )
            ],
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalVentasUsd = 0;
    double totalVentasBs = 0; // Acumulador del valor REAL histórico en Bs
    int emitidas = 0;
    
    for (var f in _facturasFiltradas) {
      if (f['estado'] != 'ANULADA') {
        totalVentasUsd += double.parse(f['total_usd'].toString());
        // Sumamos el total_bs exactamente como se guardó en la base de datos el día de la venta
        totalVentasBs += double.tryParse((f['total_bs'] ?? '0').toString()) ?? 0.0;
        emitidas++;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Módulo de Reportes y Ventas'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Mostrando: $_etiquetaPeriodo', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 16),
                          
                          // MENÚ DESPLEGABLE DE FILTROS DE FECHA
                          PopupMenuButton<String>(
                            onSelected: _setFiltroFecha,
                            icon: const Icon(Icons.filter_list_alt, color: Colors.blue),
                            tooltip: 'Opciones de fecha',
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'HOY', child: Text('Día de Hoy')),
                              const PopupMenuItem(value: 'MES', child: Text('Mes Actual')),
                              const PopupMenuItem(value: 'PERIODO', child: Text('Elegir Rango...')),
                              const PopupMenuDivider(),
                              const PopupMenuItem(value: 'TODO', child: Text('Limpiar (Ver Todo Histórico)', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _generarReportePDF,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('PDF'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                          ),
                          const SizedBox(width: 10), // Separador entre los botones
                          ElevatedButton.icon(
                            onPressed: _descargarExcel, // 👈 ¡Aquí desaparece el warning!
                            icon: const Icon(Icons.table_view),
                            label: const Text('Excel'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 20),

                  // DASHBOARD DE TOTALES
                  Row(
                    children: [
                      Expanded(child: Card(color: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Facturas Listadas', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), Text('$emitidas', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))),
                      Expanded(child: Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total USD', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), Text('\$${totalVentasUsd.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))),
                      // Aquí se muestran los Bs reales sumados históricamente, NO el cálculo con la tasa actual
                      Expanded(child: Card(color: Colors.purple.shade50, child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Histórico (Bs)', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)), Text('Bs ${totalVentasBs.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // BOTONES DE FILTRO RÁPIDO
                  Row(
                    children: [
                      const Text('Filtrar por estado: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      ChoiceChip(label: const Text('Todas'), selected: _filtroEstado == 'TODAS', onSelected: (_) => _aplicarFiltroEstado('TODAS')),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Pagadas'), selected: _filtroEstado == 'PAGADA', onSelected: (_) => _aplicarFiltroEstado('PAGADA'), selectedColor: Colors.green.shade200),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Pendientes'), selected: _filtroEstado == 'PENDIENTE', onSelected: (_) => _aplicarFiltroEstado('PENDIENTE'), selectedColor: Colors.orange.shade200),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Anuladas'), selected: _filtroEstado == 'ANULADA', onSelected: (_) => _aplicarFiltroEstado('ANULADA'), selectedColor: Colors.red.shade200),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // TABLA
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: _construirTabla(_facturasFiltradas),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _construirTabla(List<dynamic> listaFacturas) {
    if (listaFacturas.isEmpty) {
      return const Center(child: Text('No hay ventas que coincidan con este filtro.', style: TextStyle(color: Colors.grey, fontSize: 16)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.resolveWith((states) => Colors.blue.shade50),
                columns: const [
                  DataColumn(label: Text('N° Factura', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total USD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total BS', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: listaFacturas.map((factura) {
                  final isAnulada = factura['estado'] == 'ANULADA';
                  final isPendiente = factura['estado'] == 'PENDIENTE';
                  
                  Color badgeColor = Colors.green.shade100;
                  Color textColor = Colors.green.shade800;
                  if (isAnulada) { badgeColor = Colors.red.shade100; textColor = Colors.red.shade800; }
                  else if (isPendiente) { badgeColor = Colors.orange.shade100; textColor = Colors.orange.shade800; }

                  return DataRow(
                    cells: [
                      DataCell(Text(factura['numero_factura'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(_formatearFecha(factura['createdAt']))),
                      DataCell(Text(factura['Cliente'] != null ? factura['Cliente']['nombre'] : '-')),
                      DataCell(Text('\$${factura['total_usd']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                      // Agregamos la columna de los bolívares fijos guardados en la BD
                      DataCell(Text('Bs ${factura['total_bs'] ?? '0.00'}', style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12)),
                          child: Text(factura['estado'], style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // EL BOTÓN DEL OJITO PARA VER PRODUCTOS
                            IconButton(
                              icon: const Icon(Icons.remove_red_eye, color: Colors.blue),
                              tooltip: 'Ver Productos',
                              onPressed: () => _verDetallesProductos(factura),
                            ),
                            const SizedBox(width: 8),

                            if (isPendiente) ...[
                              ElevatedButton.icon(
                                onPressed: () => _mostrarDialogoCobro(factura),
                                icon: const Icon(Icons.attach_money, size: 16),
                                label: const Text('Cobrar'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                              ),
                              const SizedBox(width: 8),
                            ],
                            
                            if (!isAnulada)
                              IconButton(
                                icon: const Icon(Icons.remove_shopping_cart, color: Colors.red),
                                tooltip: 'Anular Factura',
                                onPressed: () => _mostrarDialogoAnulacion(factura),
                              )
                            else
                               const Text('Devolución', style: TextStyle(color: Colors.red, fontSize: 12))
                          ],
                        )
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}