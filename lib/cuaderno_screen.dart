import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'app_events.dart';

class CuadernoScreen extends StatefulWidget {
  const CuadernoScreen({super.key});

  @override
  State<CuadernoScreen> createState() => _CuadernoScreenState();
}

class _CuadernoScreenState extends State<CuadernoScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _jornadaActual;
  
  Map<String, List<dynamic>> _notasPorCliente = {};
  Map<String, double> _deudaPorCliente = {};
  List<bool> _panelesAbiertos = [];

  double _tasaBcv = 0.0;
  double _totalDeudaEnLaCalle = 0.0;

  @override
  void initState() {
    super.initState();
    _inicializarCuaderno();
    AppEvents.refreshNotifier.addListener(_inicializarCuaderno);
  }

  @override
  void dispose() {
    AppEvents.refreshNotifier.removeListener(_inicializarCuaderno);
    super.dispose();
  }

  Future<void> _inicializarCuaderno() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final resJornada = await http.get(Uri.parse('http://127.0.0.1:3000/api/reportes/actual'));
      final bool cajaAbierta = resJornada.statusCode == 200;

      final resTasa = await http.get(Uri.parse('http://127.0.0.1:3000/api/tasas/actual'));
      final double tasa = double.parse(jsonDecode(resTasa.body)['tasa_bcv'].toString());

      final resNotas = await http.get(Uri.parse('http://127.0.0.1:3000/api/cuaderno'));
      final List<dynamic> notasData = jsonDecode(resNotas.body);

      double deudaTotal = 0.0;
      Map<String, List<dynamic>> agrupado = {};
      Map<String, double> deudaCliente = {};

      for (var nota in notasData) {
        String nombreCliente = nota['Cliente']['nombre'];
        
        if (!agrupado.containsKey(nombreCliente)) {
          agrupado[nombreCliente] = [];
          deudaCliente[nombreCliente] = 0.0;
        }
        
        agrupado[nombreCliente]!.add(nota);

        if (nota['estado'] == 'PENDIENTE') {
          double saldoNota = double.parse(nota['saldo_pendiente'].toString());
          deudaTotal += saldoNota;
          deudaCliente[nombreCliente] = (deudaCliente[nombreCliente] ?? 0) + saldoNota;
        }
      }

      if (mounted) {
        setState(() {
          _jornadaActual = cajaAbierta ? jsonDecode(resJornada.body)['jornada'] : null;
          _tasaBcv = tasa;
          _notasPorCliente = agrupado;
          _deudaPorCliente = deudaCliente;
          _totalDeudaEnLaCalle = deudaTotal;
          if (_panelesAbiertos.length != agrupado.length) {
             _panelesAbiertos = List.filled(agrupado.length, false);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatearFecha(String fechaIso) {
    final DateTime fecha = DateTime.parse(fechaIso).toLocal();
    return DateFormat('dd/MM/yyyy hh:mm a').format(fecha);
  }

  // ==========================================================
  // 1. DIÁLOGO ABONO GLOBAL CON CONVERSIÓN EN VIVO
  // ==========================================================
  void _mostrarDialogoAbonoGlobal(String nombreCliente, int clienteId, double deudaTotal) {
    final usdCtrl = TextEditingController();
    final bsCtrl = TextEditingController();
    String metodoPago = 'Efectivo';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Abonar a la cuenta de: $nombreCliente'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12), color: Colors.orange.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Deuda Total Pendiente:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('\$${deudaTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 18)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usdCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Abono en Divisas (USD)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                  onChanged: (val) {
                    double usd = double.tryParse(val) ?? 0.0;
                    bsCtrl.text = (usd * _tasaBcv).toStringAsFixed(2);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bsCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Abono en Bolívares (Bs)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.money)),
                  onChanged: (val) {
                    double bs = double.tryParse(val) ?? 0.0;
                    usdCtrl.text = (bs / _tasaBcv).toStringAsFixed(2);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Método de Pago', border: OutlineInputBorder()),
                  initialValue: metodoPago,
                  items: ['Efectivo', 'Pago Móvil', 'Zelle', 'Punto de Venta', 'Transferencia'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => setStateDialog(() => metodoPago = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                onPressed: () async {
                  double montoAbono = double.tryParse(usdCtrl.text) ?? 0.0;
                  if (montoAbono <= 0 || montoAbono > deudaTotal) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Monto inválido.')));
                    return;
                  }
                  Navigator.pop(ctx);
                  await _procesarAbonoGlobal(clienteId, montoAbono, metodoPago);
                },
                icon: const Icon(Icons.payments),
                label: const Text('Procesar Abono'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              )
            ],
          );
        }
      )
    );
  }

  Future<void> _procesarAbonoGlobal(int clienteId, double montoUsd, String metodo) async {
    setState(() => _isLoading = true);
    try {
      final bodyData = jsonEncode({"cliente_id": clienteId, "monto_usd": montoUsd, "metodo_pago": metodo});
      final res = await http.post(Uri.parse('http://127.0.0.1:3000/api/cuaderno/abono-global'), headers: {"Content-Type": "application/json"}, body: bodyData);
      
      if (res.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Abono procesado correctamente'), backgroundColor: Colors.green));
        AppEvents.dispararActualizacion();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error conectando: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================================
  // 2. DIÁLOGO FACTURACIÓN Y CONSOLIDACIÓN DE PERIODO
  // ==========================================================
  void _mostrarDialogoFacturar(String nombreCliente, int clienteId, List<dynamic> notasCliente) {
    if (_jornadaActual == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Debes abrir la caja en Inicio para emitir una Factura Fiscal.'), backgroundColor: Colors.red));
      return;
    }

    List<dynamic> notasPendientes = notasCliente.where((n) => n['estado'] == 'PENDIENTE').toList();
    
    // Por defecto, marcamos TODAS las notas pendientes como seleccionadas
    List<int> notasSeleccionadas = notasPendientes.map<int>((n) => n['id'] as int).toList();
    String metodoPago = 'Transferencia'; 

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          
          // Recalculamos en tiempo real basándonos SOLAMENTE en las notas chequeadas
          double subtotal = 0;
          List<Map<String, dynamic>> productosAgrupados = [];

          for(var nota in notasPendientes) {
            if (notasSeleccionadas.contains(nota['id'])) {
              final detalles = nota['DetalleNotas'] ?? nota['DetalleNota'] ?? nota['detalles_nota'] ?? [];
              for(var det in detalles) {
                 subtotal += double.parse(det['subtotal_usd'].toString());
                 productosAgrupados.add({
                   'producto_id': det['producto_id'],
                   'nombre': det['Producto'] != null ? det['Producto']['nombre'] : 'Producto eliminado',
                   'cantidad': det['cantidad'],
                   'precio_unitario_usd': det['precio_unitario_usd'],
                   'aplica_iva': true, // Al facturar SIEMPRE lleva IVA
                   'subtotal_usd': det['subtotal_usd']
                 });
              }
            }
          }

          double iva = subtotal * 0.16;
          double totalUsd = subtotal + iva;
          double totalBs = totalUsd * _tasaBcv;

          return AlertDialog(
            title: Text('Facturar Período - $nombreCliente'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('1. Selecciona las notas a incluir:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 5),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: ListView.builder(
                        itemCount: notasPendientes.length,
                        itemBuilder: (c, i) {
                          final nota = notasPendientes[i];
                          final id = nota['id'];
                          return CheckboxListTile(
                            dense: true,
                            title: Text('${nota['numero_nota']} - \$${nota['total_usd']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(_formatearFecha(nota['createdAt'])),
                            value: notasSeleccionadas.contains(id),
                            activeColor: Colors.blue,
                            onChanged: (bool? checked) {
                              setStateDialog(() {
                                if (checked == true) {
                                  notasSeleccionadas.add(id);
                                } else {
                                  notasSeleccionadas.remove(id);
                                }
                              });
                            },
                          );
                        }
                      )
                    ),
                    const SizedBox(height: 16),
                    Text('2. Productos consolidados (${productosAgrupados.length}):', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 5),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.grey.shade50),
                      child: productosAgrupados.isEmpty
                          ? const Center(child: Text('Ninguna nota seleccionada', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: productosAgrupados.length,
                              itemBuilder: (c, i) {
                                final p = productosAgrupados[i];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  title: Text(p['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('${p['cantidad']} unid. a \$${p['precio_unitario_usd']}'),
                                  trailing: Text('\$${p['subtotal_usd']}'),
                                );
                              }
                            )
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal:'), Text('\$${subtotal.toStringAsFixed(2)}')]),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('IVA (16%):', style: TextStyle(fontWeight: FontWeight.bold)), Text('\$${iva.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        const Text('TOTAL A FACTURAR:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                        Text('\$${totalUsd.toStringAsFixed(2)} / Bs ${totalBs.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16))
                      ]
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: metodoPago,
                      items: ['Efectivo', 'Pago Móvil', 'Zelle', 'Punto de Venta', 'Transferencia', 'Mixto'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (v) => setStateDialog(() => metodoPago = v!),
                      decoration: const InputDecoration(labelText: 'Método de Pago Oficial', border: OutlineInputBorder())
                    )
                  ]
                )
              ),
            ),
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: const Text('Generar Factura Fiscal'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                // Si desmarcó todas las notas, apagamos el botón de facturar
                onPressed: notasSeleccionadas.isEmpty ? null : () async {
                  Navigator.pop(ctx);
                  await _procesarConsolidacion(clienteId, notasSeleccionadas, subtotal, iva, totalUsd, totalBs, metodoPago, productosAgrupados);
                }
              )
            ]
          );
        }
      )
    );
  }

  Future<void> _procesarConsolidacion(int clienteId, List<int> notasIds, double subtotal, double iva, double totalUsd, double totalBs, String metodoPago, List<Map<String,dynamic>> productos) async {
    setState(() => _isLoading = true);
    try {
      final body = jsonEncode({
        "cliente_id": clienteId,
        "jornada_id": _jornadaActual!['id'],
        "notas_ids": notasIds,
        "metodo_pago": metodoPago,
        "subtotal_usd": subtotal,
        "iva_usd": iva,
        "total_usd": totalUsd,
        "total_bs": totalBs,
        "tasa_bcv": _tasaBcv,
        "productos": productos 
      });
      final res = await http.post(Uri.parse('http://127.0.0.1:3000/api/cuaderno/consolidar'), headers: {"Content-Type": "application/json"}, body: body);
      
      if(res.statusCode == 201) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Factura Fiscal Generada con Éxito'), backgroundColor: Colors.green));
        AppEvents.dispararActualizacion();
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error conectando: $e')));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  void _verDetallesProductos(Map<String, dynamic> nota) {
    final List<dynamic> detalles = nota['DetalleNotas'] ?? nota['DetalleNota'] ?? nota['detalles_nota'] ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Productos - Nota ${nota['numero_nota'] ?? ''}'),
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
                      leading: const Icon(Icons.shopping_bag, color: Colors.orange),
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

  @override
  Widget build(BuildContext context) {
    final listClientes = _notasPorCliente.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuaderno Digital (Estado de Cuentas)'),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _inicializarCuaderno)],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 4, color: Colors.orange.shade50, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Dinero en la Calle (Por Cobrar):', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('\$${_totalDeudaEnLaCalle.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Expanded(
                  child: _notasPorCliente.isEmpty
                    ? const Center(child: Text('El cuaderno está vacío.'))
                    : SingleChildScrollView(
                        child: ExpansionPanelList(
                          expansionCallback: (int index, bool isExpanded) {
                            setState(() => _panelesAbiertos[index] = isExpanded);
                          },
                          children: listClientes.asMap().entries.map<ExpansionPanel>((entry) {
                            int index = entry.key;
                            String clienteNombre = entry.value;
                            List<dynamic> notasDelCliente = _notasPorCliente[clienteNombre]!;
                            double deudaCliente = _deudaPorCliente[clienteNombre] ?? 0.0;
                            int clienteId = notasDelCliente.first['Cliente']['id'];

                            return ExpansionPanel(
                              headerBuilder: (BuildContext context, bool isExpanded) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person, color: Colors.blue, size: 30),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(clienteNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                            Text('${notasDelCliente.length} notas registradas', style: const TextStyle(color: Colors.grey)),
                                          ]
                                        )
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text('Deuda Total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          Text('\$${deudaCliente.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: deudaCliente > 0 ? Colors.orange : Colors.green)),
                                        ]
                                      ),
                                      // BOTONES GLOBALES
                                      if (deudaCliente > 0) ...[
                                        const SizedBox(width: 16),
                                        ElevatedButton.icon(
                                          onPressed: () => _mostrarDialogoAbonoGlobal(clienteNombre, clienteId, deudaCliente),
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const Text('Abonar'),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white)
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          onPressed: () => _mostrarDialogoFacturar(clienteNombre, clienteId, notasDelCliente),
                                          icon: const Icon(Icons.receipt_long, size: 16),
                                          label: const Text('Facturar'),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)
                                        ),
                                      ]
                                    ]
                                  )
                                );
                              },
                              body: Container(
                                color: Colors.grey.shade50,
                                width: double.infinity,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.resolveWith((states) => Colors.grey.shade200),
                                  columns: const [
                                    DataColumn(label: Text('N° Nota')), DataColumn(label: Text('Fecha')),
                                    DataColumn(label: Text('Total')), DataColumn(label: Text('Deuda Nota')),
                                    DataColumn(label: Text('Estado')), DataColumn(label: Text('Ver')),
                                  ],
                                  rows: notasDelCliente.map((nota) {
                                    bool isPendiente = nota['estado'] == 'PENDIENTE';
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(nota['numero_nota'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                                        DataCell(Text(_formatearFecha(nota['createdAt']))),
                                        DataCell(Text('\$${nota['total_usd']}')),
                                        DataCell(Text('\$${nota['saldo_pendiente']}', style: TextStyle(color: isPendiente ? Colors.orange : Colors.green, fontWeight: FontWeight.bold))),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: isPendiente ? Colors.orange.shade100 : Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                                            child: Text(nota['estado'], style: TextStyle(color: isPendiente ? Colors.orange.shade800 : Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                                          )
                                        ),
                                        DataCell(
                                          IconButton(icon: const Icon(Icons.remove_red_eye, color: Colors.blue), onPressed: () => _verDetallesProductos(nota))
                                        )
                                      ]
                                    );
                                  }).toList()
                                ),
                              ),
                              isExpanded: _panelesAbiertos[index],
                            );
                          }).toList(),
                        ),
                      ),
                )
              ],
            ),
          ),
    );
  }
}