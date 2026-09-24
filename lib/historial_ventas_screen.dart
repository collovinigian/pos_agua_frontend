import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'app_events.dart';

class HistorialVentasScreen extends StatefulWidget {
  const HistorialVentasScreen({super.key});

  @override
  State<HistorialVentasScreen> createState() => _HistorialVentasScreenState();
}

class _HistorialVentasScreenState extends State<HistorialVentasScreen> {
  bool _isLoading = true;
  List<dynamic> _facturas = [];
  List<dynamic> _facturasPendientes = [];

  @override
  void initState() {
    super.initState();
    _cargarFacturas();
    AppEvents.refreshNotifier.addListener(_cargarFacturas);
  }
  
  @override
    void dispose() {
      // ESTO APAGA EL OÍDO CUANDO CIERRAS LA PANTALLA
      AppEvents.refreshNotifier.removeListener(_cargarFacturas);
      super.dispose();
    }
  
  Future<void> _cargarFacturas() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/facturas'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        setState(() {
          _facturas = data;
          _facturasPendientes = data.where((f) => f['estado'] == 'PENDIENTE').toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- FUNCIÓN DE COBRO ---
  Future<void> _cobrarFactura(int id, String metodoPago) async {
    try {
      final response = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/facturas/cobrar/$id'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"metodo_pago": metodoPago}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Factura cobrada con éxito'), backgroundColor: Colors.green));
          _cargarFacturas(); 
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error al procesar el cobro')));
      }
    }
  }

  // --- NUEVA FUNCIÓN DE ANULACIÓN (NOTA DE CRÉDITO) ---
  Future<void> _anularFactura(int id) async {
    try {
      final response = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/facturas/anular/$id'),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Factura anulada y stock restaurado'), backgroundColor: Colors.orange));
          _cargarFacturas(); 
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${response.body}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error al anular factura')));
      }
    }
  }

  void _mostrarDialogoCobro(dynamic factura) {
    String metodoSeleccionado = 'Transferencia';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Cobrar Factura ${factura['numero_factura']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cliente: ${factura['Cliente'] != null ? factura['Cliente']['nombre'] : 'Desconocido'}'),
                const SizedBox(height: 10),
                Text('Total a cobrar: \$${factura['total_usd']} / Bs ${factura['total_bs']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Método de Pago Final', border: OutlineInputBorder()),
                  initialValue: metodoSeleccionado,
                  items: ['Efectivo', 'Pago Móvil', 'Zelle', 'Punto de Venta', 'Transferencia', 'Biopago', 'Mixto']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => setStateDialog(() => metodoSeleccionado = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _cobrarFactura(factura['id'], metodoSeleccionado);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: const Text('Confirmar Pago'),
              )
            ],
          );
        }
      ),
    );
  }

  // --- NUEVO DIÁLOGO DE CONFIRMACIÓN PARA ANULAR ---
  void _mostrarDialogoAnulacion(dynamic factura) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Factura', style: TextStyle(color: Colors.red)),
        content: Text('¿Estás seguro de que deseas anular la factura ${factura['numero_factura']}?\n\nLos productos se sumarán de vuelta al inventario y la factura quedará inactiva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _anularFactura(factura['id']);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sí, Anular Factura'),
          )
        ],
      ),
    );
  }

  String _formatearFecha(String fechaISO) {
    try {
      final fecha = DateTime.parse(fechaISO).toLocal();
      return DateFormat('dd/MM/yyyy hh:mm a').format(fecha);
    } catch (e) {
      return fechaISO;
    }
  }

  Widget _construirTabla(List<dynamic> listaFacturas, bool mostrarAccionCobrar) {
    if (listaFacturas.isEmpty) {
      return const Center(child: Text('No hay registros disponibles.', style: TextStyle(color: Colors.grey, fontSize: 16)));
    }

    // Contenedor con borde y esquinas redondeadas idéntico al de Inventario
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: LayoutBuilder(
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
                    final isPendiente = factura['estado'] == 'PENDIENTE';
                    final isAnulada = factura['estado'] == 'ANULADA';
                    
                    Color badgeColor = Colors.green.shade100;
                    Color textColor = Colors.green.shade800;
                    if (isPendiente) {
                      badgeColor = Colors.orange.shade100;
                      textColor = Colors.orange.shade800;
                    } else if (isAnulada) {
                      badgeColor = Colors.red.shade100;
                      textColor = Colors.red.shade800;
                    }

                    return DataRow(
                      cells: [
                        DataCell(Text(factura['numero_factura'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(_formatearFecha(factura['createdAt']))),
                        DataCell(Text(factura['Cliente'] != null ? factura['Cliente']['nombre'] : '-')),
                        DataCell(Text('\$${factura['total_usd']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                        DataCell(Text('Bs ${factura['total_bs']}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
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
                              if (isPendiente && mostrarAccionCobrar) ...[
                                ElevatedButton.icon(
                                  onPressed: () => _mostrarDialogoCobro(factura),
                                  icon: const Icon(Icons.attach_money, size: 16),
                                  label: const Text('Cobrar'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12)),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (!isAnulada)
                                IconButton(
                                  icon: const Icon(Icons.remove_shopping_cart, color: Colors.red),
                                  tooltip: 'Anular Factura',
                                  onPressed: () => _mostrarDialogoAnulacion(factura),
                                ),
                              if (!isPendiente)
                                Text(isAnulada ? 'Devolución' : (factura['metodo_pago'] ?? ''), style: TextStyle(color: isAnulada ? Colors.red : Colors.grey, fontSize: 12)),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Historial y Cuentas por Cobrar'),
          centerTitle: true,
          bottom: const TabBar(
            labelColor: Colors.blue,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'Todas las Ventas'),
              Tab(icon: Icon(Icons.warning_amber_rounded), text: 'Cuentas por Cobrar'),
            ],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarFacturas, tooltip: 'Actualizar')
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _construirTabla(_facturas, false),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _construirTabla(_facturasPendientes, true),
                  ),
                ],
              ),
      ),
    );
  }
}