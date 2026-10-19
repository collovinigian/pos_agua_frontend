import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'app_events.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';

class HistorialVentasScreen extends StatefulWidget {
  const HistorialVentasScreen({super.key});

  @override
  State<HistorialVentasScreen> createState() => _HistorialVentasScreenState();
}

class _HistorialVentasScreenState extends State<HistorialVentasScreen> {
  List<dynamic> _facturasOriginales = [];
  List<dynamic> _facturasFiltradas = []; 
  
  bool _isLoading = true;
  
  // Variables del Buscador
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);
    try {
      String queryParams = '';
      if (_fechaInicio != null && _fechaFin != null) {
        // 🔥 CORRECCIÓN: Quitamos el ".000Z" para que respete la hora de Venezuela
        String inicioStr = "${DateFormat('yyyy-MM-dd').format(_fechaInicio!)}T00:00:00";
        String finStr = "${DateFormat('yyyy-MM-dd').format(_fechaFin!)}T23:59:59";
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
  Future<void> _seleccionarRangoFechas() async {
    final DateTimeRange? rango = await showDateRangePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.input, // <-- Permite alternar entre calendario y texto
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)), // Permite seleccionar hasta un año en el futuro
      helpText: 'Selecciona el rango de fechas',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      initialDateRange: _fechaInicio != null && _fechaFin != null 
          ? DateTimeRange(start: _fechaInicio!, end: _fechaFin!) 
          : DateTimeRange(start: DateTime.now(), end: DateTime.now()),
      
      // --- MAGIA DE DISEÑO: Restauramos tu ventana centrada ---
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500, // Ancho perfecto de ventana
              maxHeight: 600, // Alto proporcionado
            ),
            child: Theme(
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
        // 🔥 EL TRUCO VITAL: Alargamos el último día hasta el último segundo de la noche
        _fechaFin = rango.end.add(const Duration(hours: 23, minutes: 59, seconds: 59));
        
        _etiquetaPeriodo = '${DateFormat('dd/MM/yy').format(rango.start)} al ${DateFormat('dd/MM/yy').format(rango.end)}';
      });
      _cargarDatos();
    }
  }

// --- FILTROS RÁPIDOS DE FECHA (RESTAURADO) ---
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
      }
    });
    
    if (tipo != 'PERIODO') {
      _cargarDatos();
    } else {
      _seleccionarRangoFechas(); // Abre el calendario con la corrección de las 23:59
    }
  }

  void _limpiarFiltrosYDatos() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _fechaInicio = null;
      _fechaFin = null;
      _etiquetaPeriodo = 'Histórico Completo';
    });
    _cargarDatos();
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
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _mostrarModalReimpresion(factura);
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Reimprimir Copia'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      )
    );
  }

  // --- MODAL DE REIMPRESIÓN (TICKET TFHKA O PDF CARTA) ---
  void _mostrarModalReimpresion(Map<String, dynamic> factura) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.print, color: Colors.indigo, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reimprimir Factura ${factura['numero_factura'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 2),
                  const Text('Modalidad: Copia No Fiscal (Sin efecto en inventario ni Reporte Z)',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(),
              const SizedBox(height: 12),
              
              // OPCIÓN 1: TICKET FÍSICO IMPRESORA FISCAL (DNF)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  _reimprimirTicketFiscal(factura);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.receipt_long, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('1. Ticket Físico (Impresora Fiscal)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              'Emite ticket térmico en la impresora TFHKA PP9 PLUS (Comandos 80/81 DNF).',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.blue),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),

              // OPCIÓN 2: FACTURA DIGITAL PDF CARTA
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.pop(ctx);
                  _generarFacturaPdfCarta(factura);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('2. Factura Digital en PDF (Tamaño Carta)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              'Documento formal membretado listo para guardar (.pdf), enviar por WhatsApp/Correo o imprimir en impresora normal.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.red),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  // --- REIMPRIMIR TICKET FÍSICO (TFHKA DNF) ---
  Future<void> _reimprimirTicketFiscal(Map<String, dynamic> factura) async {
    final id = factura['id'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('🖨️ Enviando copia de factura ${factura['numero_factura']} a la impresora fiscal...'),
          ],
        ),
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.blue.shade800,
      ),
    );

    try {
      final res = await http.post(
        Uri.parse('http://127.0.0.1:3000/api/facturas/$id/reimprimir'),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Copia No Fiscal de la factura ${factura['numero_factura']} impresa con éxito'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        String errorMsg = 'Error al imprimir ticket';
        try {
          final data = jsonDecode(res.body);
          if (data['mensaje'] != null) errorMsg = data['mensaje'];
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $errorMsg'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error de conexión al reimprimir: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // --- GENERAR FACTURA DIGITAL EN PDF TAMAÑO CARTA (COPIA NO FISCAL) ---
  Future<void> _generarFacturaPdfCarta(Map<String, dynamic> factura) async {
    final pdf = pw.Document();
    final config = AppEvents.configNotifier.value;

    // Logo si está configurado en Base64
    pw.Widget? logoWidget;
    if (config.logoBase64 != null && config.logoBase64!.isNotEmpty) {
      try {
        final imageBytes = base64Decode(config.logoBase64!.split(',').last);
        logoWidget = pw.Image(
          pw.MemoryImage(imageBytes),
          width: 70,
          height: 70,
          fit: pw.BoxFit.contain,
        );
      } catch (_) {}
    }

    final cliente = factura['Cliente'] ?? {};
    final String nombreCliente = cliente['nombre'] ?? 'Cliente Contado';
    final String rifCliente = '${cliente['tipo_documento'] ?? 'V'}-${cliente['numero_documento'] ?? '00000000'}';
    final String dirCliente = cliente['direccion'] != null && cliente['direccion'].toString().trim().isNotEmpty
        ? cliente['direccion'].toString()
        : 'N/A';
    final String telCliente = cliente['telefono'] != null && cliente['telefono'].toString().trim().isNotEmpty
        ? cliente['telefono'].toString()
        : 'N/A';

    final double tasa = double.tryParse(factura['tasa_bcv'].toString()) ?? 1.0;
    final double subtotalUsd = double.tryParse(factura['subtotal_usd'].toString()) ?? 0.0;
    final double ivaUsd = double.tryParse(factura['iva_usd'].toString()) ?? 0.0;
    final double totalUsd = double.tryParse(factura['total_usd'].toString()) ?? 0.0;
    final double totalBs = double.tryParse((factura['total_bs'] ?? '0').toString()) ?? (totalUsd * tasa);
    final double subtotalBs = subtotalUsd * tasa;
    final double ivaBs = ivaUsd * tasa;

    final diasCredito = int.tryParse(factura['dias_credito']?.toString() ?? '0') ?? 0;
    final String condicion = diasCredito > 0 ? 'Crédito ($diasCredito días)' : 'Contado';
    
    String fechaEmision = '';
    try {
      fechaEmision = factura['createdAt'] != null
          ? _formatearFecha(factura['createdAt'].toString())
          : DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    } catch (_) {
      fechaEmision = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    }

    final List<dynamic> detalles = factura['DetalleFacturas'] ?? factura['DetalleFactura'] ?? factura['detalles_factura'] ?? [];

    // Calcular base exenta y base imponible si hay productos exentos y gravados
    double baseImponibleUsd = 0.0;
    double montoExentoUsd = 0.0;
    for (var d in detalles) {
      final double subItem = double.tryParse(d['subtotal_usd']?.toString() ?? '0') ?? 
          ((double.tryParse(d['cantidad']?.toString() ?? '0') ?? 0) * (double.tryParse(d['precio_unitario_usd']?.toString() ?? '0') ?? 0));
      if (d['aplica_iva'] == true) {
        baseImponibleUsd += subItem;
      } else {
        montoExentoUsd += subItem;
      }
    }
    // Si no había detalles desglosados, usamos los totales de la factura
    if (detalles.isEmpty) {
      if (ivaUsd > 0) {
        baseImponibleUsd = subtotalUsd;
      } else {
        montoExentoUsd = subtotalUsd;
      }
    }
    final double baseImponibleBs = baseImponibleUsd * tasa;
    final double montoExentoBs = montoExentoUsd * tasa;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        build: (pw.Context context) => [
          // 1. BANNER SUPERIOR COPIA NO FISCAL
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              border: pw.Border.all(color: PdfColors.grey400, width: 1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  '*** DOCUMENTO NO FISCAL - COPIA DE FACTURA ***',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'ESTE DOCUMENTO ES UNA REIMPRESIÓN PARA FINES ADMINISTRATIVOS - NO GENERA CRÉDITO FISCAL',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // 2. ENCABEZADO: EMPRESA (IZQ) Y DATOS DE FACTURA (DER)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Columna Izquierda: Datos de la Empresa
              pw.Expanded(
                flex: 6,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoWidget != null) ...[
                      logoWidget,
                      pw.SizedBox(width: 12),
                    ],
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            config.razonSocial,
                            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text('RIF: ${config.rif}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Dirección: ${config.direccion}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                          if (config.telefono.isNotEmpty)
                            pw.Text('Teléfono: ${config.telefono}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 14),

              // Columna Derecha: Recuadro Factura
              pw.Expanded(
                flex: 4,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    border: pw.Border.all(color: PdfColors.blue800, width: 1.2),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('FACTURA', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: const pw.BoxDecoration(color: PdfColors.red700, borderRadius: pw.BorderRadius.all(pw.Radius.circular(3))),
                            child: pw.Text('COPIA NO FISCAL', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                          ),
                        ],
                      ),
                      pw.Divider(color: PdfColors.blue800, height: 8),
                      pw.Text('N° Factura: ${factura['numero_factura'] ?? ''}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Fecha: $fechaEmision', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Condición: $condicion', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Método de Pago: ${factura['metodo_pago'] ?? 'N/A'}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Estado: ${factura['estado']}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: factura['estado'] == 'ANULADA' ? PdfColors.red800 : PdfColors.green800)),
                      pw.Text('Tasa Oficial BCV: Bs ${tasa.toStringAsFixed(2)} / \$', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // 3. DATOS DEL CLIENTE
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('DATOS DEL CLIENTE / RECEPTOR', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                pw.Divider(height: 6, color: PdfColors.grey300),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Text('Razón Social / Nombre: $nombreCliente', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text('CI / RIF: $rifCliente', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Text('Dirección Fiscal: $dirCliente', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text('Teléfono: $telCliente', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // 4. TABLA DE DETALLES DE PRODUCTOS
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Descripción', 'Cant.', 'Precio (\$)', 'Precio (Bs)', 'Alícuota', 'Total (\$)', 'Total (Bs)'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(40),
              3: pw.FixedColumnWidth(55),
              4: pw.FixedColumnWidth(65),
              5: pw.FixedColumnWidth(48),
              6: pw.FixedColumnWidth(60),
              7: pw.FixedColumnWidth(70),
            },
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.center,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
            data: detalles.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final d = entry.value;
              final nombreProd = d['Producto'] != null ? d['Producto']['nombre'] : (d['nombre'] ?? 'Producto');
              final double cant = double.tryParse(d['cantidad']?.toString() ?? '1') ?? 1.0;
              final double pUsd = double.tryParse(d['precio_unitario_usd']?.toString() ?? '0') ?? 0.0;
              final double pBs = pUsd * tasa;
              final double subUsd = double.tryParse(d['subtotal_usd']?.toString() ?? '0') ?? (cant * pUsd);
              final double subBs = subUsd * tasa;
              final bool aplicaIva = d['aplica_iva'] == true;

              return [
                '$idx',
                nombreProd,
                cant.toStringAsFixed(cant % 1 == 0 ? 0 : 2),
                '\$${pUsd.toStringAsFixed(2)}',
                'Bs ${pBs.toStringAsFixed(2)}',
                aplicaIva ? '16% (G)' : 'Exento (E)',
                '\$${subUsd.toStringAsFixed(2)}',
                'Bs ${subBs.toStringAsFixed(2)}',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),

          // 5. RESUMEN Y TOTALES
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Izquierda: Nota informativa
              pw.Expanded(
                flex: 5,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('NOTAS Y CONDICIONES:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                      pw.SizedBox(height: 3),
                      pw.Text('• Factura original emitida a través de impresora fiscal TFHKA / Aclas.', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      pw.Text('• Montos en Bolívares calculados a la tasa de cambio histórica de la emisión (\$1 = Bs ${tasa.toStringAsFixed(2)}).', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      if (factura['estado'] == 'ANULADA')
                        pw.Text('• ADVERTENCIA: Esta factura fue ANULADA en el sistema mediante Nota de Crédito fiscal.', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                      if (factura['estado'] == 'PENDIENTE')
                        pw.Text('• Factura emitida a crédito, pendiente por cobrar.', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange800)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 20),

              // Derecha: Cuadro de Totales
              pw.Expanded(
                flex: 5,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blueGrey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('\$${subtotalUsd.toStringAsFixed(2)}  |  Bs ${subtotalBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      if (montoExentoUsd > 0) ...[
                        pw.SizedBox(height: 2),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Monto Exento (E):', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('\$${montoExentoUsd.toStringAsFixed(2)}  |  Bs ${montoExentoBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ],
                      if (baseImponibleUsd > 0) ...[
                        pw.SizedBox(height: 2),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Base Imponible (G 16%):', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('\$${baseImponibleUsd.toStringAsFixed(2)}  |  Bs ${baseImponibleBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ],
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('IVA (16%):', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('\$${ivaUsd.toStringAsFixed(2)}  |  Bs ${ivaBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.Divider(color: PdfColors.blueGrey800, height: 8),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('TOTAL USD:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                          pw.Text('\$${totalUsd.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('TOTAL BS:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                          pw.Text('Bs ${totalBs.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // 6. PIE DE PÁGINA
          pw.Center(
            child: pw.Text(
              '*** COPIA SIN DERECHO A CRÉDITO FISCAL - REIMPRESIÓN DIGITAL ***',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    final String numFacturaLimpio = (factura['numero_factura'] ?? '000').replaceAll('/', '_').replaceAll('\\', '_');
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Copia_Factura_${numFacturaLimpio}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
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

    // Usar la lista filtrada también por el buscador para el PDF
    List<dynamic> facturasParaPdf = _facturasFiltradas.where((f) {
      if (_searchQuery.isEmpty) return true;
      String numero = (f['numero_factura'] ?? '').toLowerCase();
      String cliente = f['Cliente'] != null ? f['Cliente']['nombre'].toLowerCase() : '';
      return numero.contains(_searchQuery) || cliente.contains(_searchQuery);
    }).toList();

    for (var f in facturasParaPdf) {
      if (f['estado'] != 'ANULADA') {
        ventasTotales += double.parse(f['total_usd'].toString());
        ventasTotalesBs += double.parse(f['total_bs'].toString());
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(30),
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
                pw.Text('Facturas: ${facturasParaPdf.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
            cellStyle: const pw.TextStyle(fontSize: 9), 
            cellAlignment: pw.Alignment.centerLeft,
            data: facturasParaPdf.map((f) {
              final tasa = double.tryParse(f['tasa_bcv'].toString()) ?? 1.0;
              final subtotalUsd = double.tryParse(f['subtotal_usd'].toString()) ?? 0.0;
              final ivaUsd = double.tryParse(f['iva_usd'].toString()) ?? 0.0;
              
              final baseBs = subtotalUsd * tasa;
              final ivaBs = ivaUsd * tasa;
              final totalBs = double.tryParse(f['total_bs'].toString()) ?? 0.0;
              final totalUsd = double.tryParse(f['total_usd'].toString()) ?? 0.0;

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
    // 1. Abrimos la ventana nativa de "Guardar como..." usando file_selector (Oficial de Flutter)
    final FileSaveLocation? ubicacion = await getSaveLocation(
      suggestedName: 'Reporte_Ventas_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Archivos Excel', extensions: ['xlsx']),
      ],
    );

    // Si el usuario presiona "Cancelar" o cierra la ventana, detenemos el proceso
    if (ubicacion == null) return;

    setState(() => _isLoading = true);

    try {
      String urlStr = 'http://127.0.0.1:3000/api/facturas/exportar-excel';
      
      if (_fechaInicio != null && _fechaFin != null) {
        String inicioStr = "${DateFormat('yyyy-MM-dd').format(_fechaInicio!)}T00:00:00";
        String finStr = "${DateFormat('yyyy-MM-dd').format(_fechaFin!)}T23:59:59";
        urlStr += '?fecha_inicio=$inicioStr&fecha_fin=$finStr';
      }
      
      final url = Uri.parse(urlStr);
      
      // 2. Hacemos la petición GET para descargar los "bytes" del archivo
      final res = await http.get(url);

      if (res.statusCode == 200) {
        // 3. Escribimos los bytes directamente en la ruta elegida (ubicacion.path)
        final archivoFisico = File(ubicacion.path);
        await archivoFisico.writeAsBytes(res.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ Excel guardado exitosamente'), //en:\n${ubicacion.path}
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ));
        }
      } else {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
             content: Text('❌ Error del servidor al generar el Excel'), 
             backgroundColor: Colors.red
           ));
         }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Error al guardar el archivo: $e'), 
          backgroundColor: Colors.red
        ));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- ACCIONES DE FACTURA (COBRAR Y ANULAR) ---
  Future<void> _anularFactura(int id) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.put(Uri.parse('http://127.0.0.1:3000/api/facturas/anular/$id'));
      
      if (res.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Factura anulada con éxito y Nota de Crédito emitida'), backgroundColor: Colors.orange));
        _cargarDatos(); 
        AppEvents.dispararActualizacion();
      } else {
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
        await _cargarDatos(); 
        AppEvents.dispararActualizacion();
      } else {
         if (mounted) {
            // 🔥 PROTECCIÓN: Intentamos leer JSON, si es HTML atrapamos el error silenciosamente
            String errorMsg = 'Error en el servidor (Código: ${res.statusCode})';
            try {
              errorMsg = jsonDecode(res.body)['mensaje'] ?? errorMsg;
            } catch (_) {
              // Si falla el jsonDecode (porque es HTML), conservamos el errorMsg genérico
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Aviso: $errorMsg'), backgroundColor: Colors.red));
            setState(() => _isLoading = false);
         }
      }
    } catch (e) {
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error de conexión: $e'), backgroundColor: Colors.red));
          setState(() => _isLoading = false);
      }
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
    double totalVentasBs = 0; 
    int emitidas = 0;
    
    // 1. Aplicamos el filtro del buscador
    List<dynamic> facturasParaMostrar = _facturasFiltradas.where((f) {
      if (_searchQuery.isEmpty) return true; 
      
      String numero = (f['numero_factura'] ?? '').toLowerCase();
      String cliente = f['Cliente'] != null ? f['Cliente']['nombre'].toLowerCase() : '';
      
      return numero.contains(_searchQuery) || cliente.contains(_searchQuery);
    }).toList();

    // 2. Calculamos totales basados en la lista filtrada
    for (var f in facturasParaMostrar) {
      if (f['estado'] != 'ANULADA') {
        totalVentasUsd += double.parse(f['total_usd'].toString());
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
                      // SECCIÓN IZQUIERDA: Fechas, Menú, Recargar y Buscador
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('Mostrando: $_etiquetaPeriodo', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 16),
                            
                            // MENÚ DESPLEGABLE RESTAURADO
                            PopupMenuButton<String>(
                              onSelected: _setFiltroFecha,
                              icon: const Icon(Icons.filter_list_alt, color: Colors.blue),
                              tooltip: 'Opciones de fecha',
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'HOY', child: Text('Día de Hoy')),
                                const PopupMenuItem(value: 'MES', child: Text('Mes Actual')),
                                const PopupMenuItem(value: 'PERIODO', child: Text('Elegir Rango...')),
                              ],
                            ),
                            
                            // BOTÓN DE RECARGAR/LIMPIAR (Afuera del menú, como pediste)
                            IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.green),
                              tooltip: 'Limpiar Filtros y Recargar (Ver Todo)',
                              onPressed: _limpiarFiltrosYDatos,
                            ),
                            
                            const SizedBox(width: 24),
                            
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  labelText: 'Buscar Factura (Ej: F-000029) o Cliente',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value.toLowerCase();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),

                      // SECCIÓN DERECHA: Botones de exportar
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _generarReportePDF,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('PDF'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _descargarExcel, 
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
                      Expanded(child: Card(color: Colors.purple.shade50, child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Histórico (Bs)', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)), Text('Bs ${totalVentasBs.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // BOTONES DE FILTRO RÁPIDO DE ESTADO
                  Row(
                    children: [
                      const Text('Filtrar por estado: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      ChoiceChip(label: const Text('Todas'), selected: _filtroEstado == 'TODAS', onSelected: (_) => _aplicarFiltroEstado('TODAS')),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Pagadas'), selected: _filtroEstado == 'PAGADA', onSelected: (_) => _aplicarFiltroEstado('PAGADA'), selectedColor: Colors.green.shade200),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Por cobrar'), selected: _filtroEstado == 'PENDIENTE', onSelected: (_) => _aplicarFiltroEstado('PENDIENTE'), selectedColor: Colors.orange.shade200),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Anuladas'), selected: _filtroEstado == 'ANULADA', onSelected: (_) => _aplicarFiltroEstado('ANULADA'), selectedColor: Colors.red.shade200),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // TABLA (Se le pasa la lista filtrada)
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: _construirTabla(facturasParaMostrar),
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
                  DataColumn(label: Text('Condición', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))), // 🔥 MOVIDO AQUÍ
                  DataColumn(label: Text('Base BS', style: TextStyle(fontWeight: FontWeight.bold))), 
                  DataColumn(label: Text('Total USD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total BS', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: listaFacturas.map((factura) {
                  final isAnulada = factura['estado'] == 'ANULADA';
                  final isPendiente = factura['estado'] == 'PENDIENTE';
                  
                  final tasa = double.tryParse(factura['tasa_bcv'].toString()) ?? 1.0;
                  final subtotalUsd = double.tryParse(factura['subtotal_usd'].toString()) ?? 0.0;
                  final baseBs = subtotalUsd * tasa;
                  // Extraemos los días de crédito (si es null, por defecto es 0)
                  final diasCredito = int.tryParse(factura['dias_credito'].toString()) ?? 0;
                  // Si tiene días de crédito, sabemos que históricamente fue a Crédito. 
                  // Si no, es de Contado.
                  final condicion = diasCredito > 0 ? 'Crédito' : 'Contado';

                  Color badgeColor = Colors.green.shade100;
                  Color textColor = Colors.green.shade800;
                  if (isAnulada) { badgeColor = Colors.red.shade100; textColor = Colors.red.shade800; }
                  else if (isPendiente) { badgeColor = Colors.orange.shade100; textColor = Colors.orange.shade800; }

                  return DataRow(
                    cells: [
                      DataCell(Text(factura['numero_factura'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(_formatearFecha(factura['createdAt']))),
                      DataCell(Text(factura['Cliente'] != null ? factura['Cliente']['nombre'] : '-')),
                      
                      // Celdas de Condición y Estado juntas
                      DataCell(Text(condicion, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(12)),
                          child: Text(factura['estado'], style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ), // 🔥 MOVIDO AQUÍ

                      DataCell(Text('Bs ${baseBs.toStringAsFixed(2)}')),
                      DataCell(Text('\$${factura['total_usd']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                      DataCell(Text('Bs ${factura['total_bs'] ?? '0.00'}', style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_red_eye, color: Colors.blue),
                              tooltip: 'Ver Productos',
                              onPressed: () => _verDetallesProductos(factura),
                            ),
                            const SizedBox(width: 4),

                            IconButton(
                              icon: const Icon(Icons.print, color: Colors.indigo),
                              tooltip: 'Reimprimir Copia (No Fiscal)',
                              onPressed: () => _mostrarModalReimpresion(factura),
                            ),
                            const SizedBox(width: 4),

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