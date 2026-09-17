import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  bool _isLoading = true;
  
  Map<String, dynamic>? _jornadaActual;
  double _tasaBcv = 0.0;
  List<dynamic> _clientes = [];
  List<dynamic> _productos = [];
  List<dynamic> _productosFiltrados = [];
  
  // Variables del Carrito y Venta actual
  Map<String, dynamic>? _clienteSeleccionado;
  String _metodoPago = 'Efectivo';
  List<Map<String, dynamic>> _carrito = [];
  
  // NUEVO: Lista para guardar pedidos en espera
  List<Map<String, dynamic>> _pedidosEnEspera = [];

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _documentoClienteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _inicializarPOS();
  }

  Future<void> _inicializarPOS() async {
    setState(() => _isLoading = true);
    try {
      final resJornada = await http.get(Uri.parse('http://127.0.0.1:3000/api/jornadas/actual'));
      final dataJornada = jsonDecode(resJornada.body);
      if (dataJornada['abierta'] == true) _jornadaActual = dataJornada['data'];

      final resTasa = await http.get(Uri.parse('http://127.0.0.1:3000/api/tasas/actual'));
      _tasaBcv = double.parse(jsonDecode(resTasa.body)['tasa_bcv'].toString());

      final resClientes = await http.get(Uri.parse('http://127.0.0.1:3000/api/clientes'));
      _clientes = jsonDecode(resClientes.body);

      final resProductos = await http.get(Uri.parse('http://127.0.0.1:3000/api/productos'));
      final todosLosProductos = jsonDecode(resProductos.body) as List;
      _productos = todosLosProductos.where((p) => (p['cantidad'] ?? 0) > 0).toList();
      _productosFiltrados = List.from(_productos);

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error conectando: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- NUEVAS FUNCIONES DE LA FACTURA ---
  void _limpiarFactura() {
    setState(() {
      _carrito.clear();
      _clienteSeleccionado = null;
      _documentoClienteController.clear();
      _metodoPago = 'Efectivo';
    });
  }

  void _guardarPedidoEnEspera() {
    if (_carrito.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ No hay productos para guardar')));
      return;
    }
    setState(() {
      _pedidosEnEspera.add({
        'cliente': _clienteSeleccionado,
        'carrito': List.from(_carrito), // Clonamos la lista
        'hora': DateTime.now()
      });
    });
    _limpiarFactura();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏸️ Pedido guardado en espera'), backgroundColor: Colors.orange));
  }

  void _mostrarPedidosEnEspera() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pedidos en Espera'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: _pedidosEnEspera.isEmpty
              ? const Center(child: Text('No hay pedidos en espera'))
              : ListView.builder(
                  itemCount: _pedidosEnEspera.length,
                  itemBuilder: (context, index) {
                    final pedido = _pedidosEnEspera[index];
                    final cliente = pedido['cliente'];
                    final nombreCliente = cliente != null ? cliente['nombre'] : 'Cliente sin registrar';
                    final itemsCount = (pedido['carrito'] as List).length;

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long, color: Colors.blue),
                        title: Text(nombreCliente, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$itemsCount productos | ${pedido['hora'].hour}:${pedido['hora'].minute.toString().padLeft(2, '0')}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, color: Colors.green),
                              tooltip: 'Recuperar',
                              onPressed: () {
                                setState(() {
                                  _clienteSeleccionado = pedido['cliente'];
                                  if (_clienteSeleccionado == null) {
                                    _documentoClienteController.clear();
                                  }
                                  _carrito = List.from(pedido['carrito']);
                                  _pedidosEnEspera.removeAt(index);
                                });
                                Navigator.pop(ctx);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Eliminar',
                              onPressed: () {
                                setState(() => _pedidosEnEspera.removeAt(index));
                                Navigator.pop(ctx);
                                _mostrarPedidosEnEspera(); // Recarga la lista
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      )
    );
  }

  // --- LÓGICA DE BÚSQUEDA Y REGISTRO ---
  void _buscarCliente() {
    String docBusqueda = _documentoClienteController.text.trim().toLowerCase();
    if (docBusqueda.isEmpty) return;

    var clienteEncontrado = _clientes.firstWhere(
      (c) => c['numero_documento'].toString().toLowerCase() == docBusqueda || 
             '${c['tipo_documento']}-${c['numero_documento']}'.toLowerCase().contains(docBusqueda),
      orElse: () => null
    );

    if (clienteEncontrado != null) {
      setState(() { _clienteSeleccionado = clienteEncontrado; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Cliente: ${clienteEncontrado['nombre']}'), backgroundColor: Colors.green, duration: const Duration(seconds: 1)));
    } else {
      _mostrarRegistroRapido(docBusqueda);
    }
  }

  void _mostrarRegistroRapido(String documentoPrevio) {
    final docCtrl = TextEditingController(text: documentoPrevio);
    final nomCtrl = TextEditingController();
    final correoCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final dirCtrl = TextEditingController();
    String tipoDoc = 'V';
    bool guardando = false;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Registro Rápido de Cliente'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(width: 80, child: DropdownButtonFormField<String>(value: tipoDoc, decoration: const InputDecoration(border: OutlineInputBorder()), items: ['V','E','J','G'].map((t)=>DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (val) => setStateDialog(() => tipoDoc = val!))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: docCtrl, decoration: const InputDecoration(labelText: 'Documento*', border: OutlineInputBorder()))),
                    ]
                  ),
                  const SizedBox(height: 16), TextField(controller: nomCtrl, decoration: const InputDecoration(labelText: 'Nombre o Razón Social*', border: OutlineInputBorder())),
                  const SizedBox(height: 16), TextField(controller: correoCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo Electrónico', border: OutlineInputBorder())),
                  const SizedBox(height: 16), TextField(controller: telCtrl, decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder())),
                  const SizedBox(height: 16), TextField(controller: dirCtrl, decoration: const InputDecoration(labelText: 'Dirección', border: OutlineInputBorder())),
                ]
              ),
            ),
            actions: [
              TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: guardando ? null : () async {
                  if(docCtrl.text.isEmpty || nomCtrl.text.isEmpty) return;
                  setStateDialog(() => guardando = true);
                  try {
                    final response = await http.post(Uri.parse('http://127.0.0.1:3000/api/clientes'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({"tipo_documento": tipoDoc, "numero_documento": docCtrl.text, "nombre": nomCtrl.text, "correo": correoCtrl.text, "telefono": telCtrl.text, "direccion": dirCtrl.text}));
                    if (response.statusCode == 201) {
                       final nuevoCliente = jsonDecode(response.body)['data'];
                       setState(() { _clientes.add(nuevoCliente); _clienteSeleccionado = nuevoCliente; });
                       if (mounted) Navigator.pop(ctx);
                    }
                  } catch (e) { setStateDialog(() => guardando = false); }
                },
                child: guardando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white)) : const Text('Guardar')
              )
            ]
          );
        }
      )
    );
  }

  // --- LÓGICA DEL CARRITO Y CATÁLOGO ---
  void _filtrarProductos(String query) {
    if (query.isEmpty) setState(() => _productosFiltrados = List.from(_productos));
    else setState(() => _productosFiltrados = _productos.where((p) => (p['nombre'] ?? '').toString().toLowerCase().contains(query.toLowerCase()) || (p['codigo_producto'] ?? '').toString().toLowerCase().contains(query.toLowerCase())).toList());
  }

  void _agregarAlCarrito(dynamic producto) {
    setState(() {
      int index = _carrito.indexWhere((item) => item['producto_id'] == producto['id']);
      if (index != -1) {
        if (_carrito[index]['cantidad'] < producto['cantidad']) {
          _carrito[index]['cantidad']++;
          _carrito[index]['subtotal_usd'] = _carrito[index]['cantidad'] * _carrito[index]['precio_unitario_usd'];
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Stock máximo alcanzado (${producto['cantidad']})')));
        }
      } else {
        double precioUsd = double.tryParse(producto['precio_usd'].toString()) ?? 0.0;
        _carrito.add({'producto_id': producto['id'], 'nombre': producto['nombre'], 'cantidad': 1, 'precio_unitario_usd': precioUsd, 'aplica_iva': producto['aplica_iva'], 'subtotal_usd': precioUsd, 'stock_maximo': producto['cantidad']});
      }
    });
  }

  void _modificarCantidad(int index, int delta) {
    setState(() {
      int nuevaCantidad = _carrito[index]['cantidad'] + delta;
      if (nuevaCantidad > 0 && nuevaCantidad <= _carrito[index]['stock_maximo']) {
        _carrito[index]['cantidad'] = nuevaCantidad;
        _carrito[index]['subtotal_usd'] = nuevaCantidad * _carrito[index]['precio_unitario_usd'];
      } else if (nuevaCantidad == 0) {
        _carrito.removeAt(index);
      }
    });
  }

  // NUEVO: Modificar cantidad ingresando el número
  void _editarCantidadManual(int index) {
    final ctrl = TextEditingController(text: _carrito[index]['cantidad'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cantidad para ${_carrito[index]['nombre']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Stock disponible: ${_carrito[index]['stock_maximo']}'
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              int val = int.tryParse(ctrl.text) ?? 0;
              if (val > 0 && val <= _carrito[index]['stock_maximo']) {
                setState(() {
                  _carrito[index]['cantidad'] = val;
                  _carrito[index]['subtotal_usd'] = val * _carrito[index]['precio_unitario_usd'];
                });
                Navigator.pop(ctx);
              } else if (val == 0) {
                setState(() => _carrito.removeAt(index));
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ Inválido. Stock máximo: ${_carrito[index]['stock_maximo']}')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Aplicar')
          )
        ],
      )
    );
  }

  Map<String, double> _calcularTotales() {
    double subtotal = 0, iva = 0;
    for (var item in _carrito) {
      subtotal += item['subtotal_usd'];
      if (item['aplica_iva'] == true) iva += item['subtotal_usd'] * 0.16;
    }
    return {'subtotal_usd': subtotal, 'iva_usd': iva, 'total_usd': subtotal + iva, 'total_bs': (subtotal + iva) * _tasaBcv};
  }

  Future<void> _procesarVenta() async {
    if (_clienteSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Selecciona o busca un cliente primero')));
      return;
    }
    if (_carrito.isEmpty) return;

    // NUEVO: Lógica de Crédito
    int diasCredito = 0;
    if (_metodoPago == 'Crédito') {
      final inputDias = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Factura a Crédito'),
            content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Días de plazo para pagar', border: OutlineInputBorder())),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), child: const Text('Aceptar'))
            ]
          );
        }
      );
      if (inputDias == null || inputDias.isEmpty) return; // Si cancela el popup, no procesa la venta
      diasCredito = int.tryParse(inputDias) ?? 0;
    }

    setState(() => _isLoading = true);
    try {
      final totales = _calcularTotales();
      final bodyData = jsonEncode({
        "cliente_id": _clienteSeleccionado!['id'],
        "jornada_id": _jornadaActual!['id'],
        "metodo_pago": _metodoPago,
        "dias_credito": diasCredito, // Lo mandamos al backend
        "subtotal_usd": totales['subtotal_usd'],
        "iva_usd": totales['iva_usd'],
        "total_usd": totales['total_usd'],
        "total_bs": totales['total_bs'],
        "tasa_bcv": _tasaBcv,
        "productos": _carrito.map((item) => {
          "producto_id": item['producto_id'], "cantidad": item['cantidad'],
          "precio_unitario_usd": item['precio_unitario_usd'], "aplica_iva": item['aplica_iva'], "subtotal_usd": item['subtotal_usd']
        }).toList()
      });

      final response = await http.post(Uri.parse('http://127.0.0.1:3000/api/facturas'), headers: {"Content-Type": "application/json"}, body: bodyData);

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ ¡Factura Procesada con Éxito!'), backgroundColor: Colors.green));
          _limpiarFactura();
          _inicializarPOS(); 
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${response.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error conectando al servidor')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_jornadaActual == null) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 100, color: Colors.grey), SizedBox(height: 20), Text('La Caja está Cerrada', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), Text('Ve a Inicio para abrir la jornada del día.', style: TextStyle(fontSize: 16, color: Colors.grey))]));
    }

    final totales = _calcularTotales();

    return Scaffold(
      body: Row(
        children: [
          // ================= LADO IZQUIERDO: CATÁLOGO =================
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Catálogo de Productos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.refresh, color: Colors.blue), onPressed: _inicializarPOS, tooltip: 'Actualizar Catálogo'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: _searchController, onChanged: _filtrarProductos, decoration: InputDecoration(hintText: 'Buscar por código o nombre...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _productosFiltrados.isEmpty 
                      ? const Center(child: Text('No hay productos disponibles.'))
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 3/2, crossAxisSpacing: 10, mainAxisSpacing: 10),
                          itemCount: _productosFiltrados.length,
                          itemBuilder: (context, index) {
                            final p = _productosFiltrados[index];
                            return InkWell(
                              onTap: () => _agregarAlCarrito(p),
                              child: Card(
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(p['codigo_producto'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                      Text(p['nombre'] ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const Spacer(),
                                      Text('Stock: ${p['cantidad']}', style: TextStyle(color: Colors.grey.shade700)),
                                      Text('\$${p['precio_usd']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  )
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),

          // ================= LADO DERECHO: LA FACTURA =================
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  // CABECERA CON BOTONES NUEVOS
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.blue.shade50,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Facturación', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                if (_pedidosEnEspera.isNotEmpty)
                                  IconButton(icon: const Icon(Icons.list_alt, color: Colors.blue), tooltip: 'Ver Espera', onPressed: _mostrarPedidosEnEspera),
                                IconButton(icon: const Icon(Icons.pause_circle_outline, color: Colors.orange), tooltip: 'Pausar/Guardar', onPressed: _guardarPedidoEnEspera),
                                IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), tooltip: 'Limpiar Todo', onPressed: _limpiarFactura),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // CLIENTE
                        if (_clienteSeleccionado != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                            child: Row(
                              children: [
                                const Icon(Icons.person, color: Colors.blue), const SizedBox(width: 10),
                                Expanded(child: Text('${_clienteSeleccionado!['tipo_documento']}-${_clienteSeleccionado!['numero_documento']} | ${_clienteSeleccionado!['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() { _clienteSeleccionado = null; _documentoClienteController.clear(); }))
                              ],
                            ),
                          )
                        ] else ...[
                          TextField(
                            controller: _documentoClienteController,
                            decoration: InputDecoration(labelText: 'Cédula o RIF del Cliente', hintText: 'Ej: 27111222', filled: true, fillColor: Colors.white, border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.blue), onPressed: _buscarCliente)),
                            onSubmitted: (_) => _buscarCliente(), 
                          )
                        ]
                      ],
                    ),
                  ),

                  // LISTA DEL CARRITO (Con cantidad clickeable)
                  Expanded(
                    child: _carrito.isEmpty
                        ? const Center(child: Text('Agrega productos aquí', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _carrito.length,
                            itemBuilder: (context, index) {
                              final item = _carrito[index];
                              return ListTile(
                                title: Text(item['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('\$${item['precio_unitario_usd'].toStringAsFixed(2)} c/u ${item['aplica_iva'] ? '(IVA)' : '(E)'}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _modificarCantidad(index, -1)),
                                    
                                    // NUEVO: Hacer la cantidad clickeable para escribir el número
                                    InkWell(
                                      onTap: () => _editarCantidadManual(index),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                        child: Text('${item['cantidad']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      ),
                                    ),

                                    IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), onPressed: () => _modificarCantidad(index, 1)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // TOTALES EN MONEDA DUAL
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(0, -5))]),
                    child: Column(
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal:', style: TextStyle(color: Colors.grey)), Text('\$${totales['subtotal_usd']!.toStringAsFixed(2)} / Bs ${(totales['subtotal_usd']! * _tasaBcv).toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey))]),
                        const SizedBox(height: 8),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('IVA (16%):', style: TextStyle(color: Colors.grey)), Text('\$${totales['iva_usd']!.toStringAsFixed(2)} / Bs ${(totales['iva_usd']! * _tasaBcv).toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey))]),
                        const Divider(),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL USD:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('\$${totales['total_usd']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green))]),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL BS:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('Bs ${totales['total_bs']!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue))]),
                        const SizedBox(height: 16),
                        
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Método de Pago', border: OutlineInputBorder()),
                          value: _metodoPago,
                          items: ['Efectivo', 'Pago Móvil', 'Zelle', 'Punto de Venta', 'Transferencia', 'Biopago', 'Mixto', 'Crédito']
                              .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (val) => setState(() => _metodoPago = val!),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton.icon(
                            onPressed: (_carrito.isEmpty || _clienteSeleccionado == null) ? null : _procesarVenta,
                            icon: const Icon(Icons.point_of_sale), label: const Text('PROCESAR FACTURA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          ),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}