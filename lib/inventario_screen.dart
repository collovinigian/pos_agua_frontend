import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'producto_screen.dart';
import 'app_events.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  List<dynamic> _productos = [];
  List<dynamic> _productosFiltrados = []; 
  
  bool _isLoading = true;
  double _tasaBcv = 0.0; 
  final TextEditingController _searchController = TextEditingController();

  int? _sortColumnIndex;
  bool _isAscending = true;

 @override
  void initState() {
    super.initState();
    _inicializarDatos();
    // 🔔 NUEVO: Escuchar el timbre para actualizar el stock automáticamente
    AppEvents.refreshNotifier.addListener(_inicializarDatos);
  }

  // 🔔 NUEVO: Apagar el oyente para no gastar memoria si cambias de módulo
  @override
  void dispose() {
    AppEvents.refreshNotifier.removeListener(_inicializarDatos);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _inicializarDatos() async {
    setState(() => _isLoading = true);
    await _obtenerTasaActual();
    await _cargarProductos();
    setState(() => _isLoading = false);
  }

  Future<void> _obtenerTasaActual() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/tasas/actual'));
      if (response.statusCode == 200) {
        _tasaBcv = double.parse(jsonDecode(response.body)['tasa_bcv'].toString());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error obteniendo tasa: $e'))
        );
      }
    }
  }

  Future<void> _cargarProductos() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/productos'));
      if (response.statusCode == 200) {
        _productos = jsonDecode(response.body);
        _filtrarProductos(_searchController.text); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  void _filtrarProductos(String query) {
    if (query.isEmpty) {
      setState(() => _productosFiltrados = List.from(_productos));
    } else {
      setState(() {
        _productosFiltrados = _productos.where((p) {
          final nombre = (p['nombre'] ?? '').toString().toLowerCase();
          final codigo = (p['codigo_producto'] ?? '').toString().toLowerCase();
          final search = query.toLowerCase();
          return nombre.contains(search) || codigo.contains(search);
        }).toList();
      });
    }
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _isAscending = ascending;

      _productosFiltrados.sort((a, b) {
        dynamic aValue;
        dynamic bValue;

        switch (columnIndex) {
          case 0: aValue = a['codigo_producto']; bValue = b['codigo_producto']; break;
          case 1: aValue = a['nombre']; bValue = b['nombre']; break;
          case 3: aValue = int.tryParse(a['cantidad'].toString()) ?? 0; bValue = int.tryParse(b['cantidad'].toString()) ?? 0; break;
          case 4: aValue = double.tryParse(a['precio_usd'].toString()) ?? 0.0; bValue = double.tryParse(b['precio_usd'].toString()) ?? 0.0; break;
          default: return 0;
        }

        if (aValue is String && bValue is String) {
          return ascending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
        } else if (aValue is num && bValue is num) {
          return ascending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
        }
        return 0;
      });
    });
  }

  Future<void> _eliminarProducto(int id) async {
    try {
      final response = await http.delete(Uri.parse('http://127.0.0.1:3000/api/productos/$id'));
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Producto eliminado'), backgroundColor: Colors.red));
          _cargarProductos(); 
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario de Productos'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistroProductoScreen()));
                _inicializarDatos(); 
              },
              icon: const Icon(Icons.add), label: const Text('Nuevo Producto'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            ),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _filtrarProductos,
                    decoration: InputDecoration(
                      hintText: 'Buscar por código o nombre...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filtrarProductos('');
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(12), 
                        border: Border.all(color: Colors.grey.shade300)
                      ),
                      child: _productosFiltrados.isEmpty
                          ? const Center(child: Text('No hay productos para mostrar.', style: TextStyle(color: Colors.grey, fontSize: 16)))
                          // AQUÍ ESTÁ LA MAGIA DEL LAYOUT BUILDER PARA ESTIRAR LA TABLA
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                      child: DataTable(
                                        sortColumnIndex: _sortColumnIndex,
                                        sortAscending: _isAscending,
                                        headingRowColor: WidgetStateProperty.resolveWith((states) => Colors.grey.shade100),
                                        columns: [
                                          DataColumn(label: const Text('Código', style: TextStyle(fontWeight: FontWeight.bold)), onSort: _onSort),
                                          DataColumn(label: const Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold)), onSort: _onSort),
                                          const DataColumn(label: Text('Detalles', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: const Text('Stock', style: TextStyle(fontWeight: FontWeight.bold)), onSort: _onSort, numeric: true),
                                          DataColumn(label: const Text('Precio (USD)', style: TextStyle(fontWeight: FontWeight.bold)), onSort: _onSort, numeric: true),
                                          const DataColumn(label: Text('Base (Bs)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                          const DataColumn(label: Text('Total Bs', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                          const DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                        rows: _productosFiltrados.map((producto) {
                                          
                                          double precioUsd = double.tryParse(producto['precio_usd'].toString()) ?? 0.0;
                                          double baseBs = precioUsd * _tasaBcv;
                                          bool aplicaIva = producto['aplica_iva'] ?? false;
                                          double totalBs = aplicaIva ? (baseBs * 1.16) : baseBs; 

                                          return DataRow(
                                            cells: [
                                              DataCell(Text(producto['codigo_producto'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                                              DataCell(Text(producto['nombre'] ?? '')),
                                              DataCell(Text(producto['detalles']?.toString().isNotEmpty == true ? producto['detalles'] : '-')),
                                              DataCell(Text(producto['cantidad'].toString(), style: const TextStyle(fontSize: 16))),
                                              DataCell(Text('\$${precioUsd.toStringAsFixed(2)}')),
                                              DataCell(Text('Bs ${baseBs.toStringAsFixed(2)}')),
                                              // AQUÍ AGREGAMOS EL (E) EN VERDE Y EL (IVA) EN AZUL
                                              DataCell(Text(
                                                'Bs ${totalBs.toStringAsFixed(2)}${aplicaIva ? ' (IVA)' : ' (E)'}', 
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold, 
                                                  color: aplicaIva ? Colors.blue : Colors.green.shade700
                                                )
                                              )),
                                              DataCell(Row(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                                    tooltip: 'Editar',
                                                    onPressed: () async {
                                                      await Navigator.push(context, MaterialPageRoute(builder: (context) => RegistroProductoScreen(productoAEditar: producto)));
                                                      _inicializarDatos();
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete, color: Colors.red),
                                                    tooltip: 'Eliminar',
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: const Text('Eliminar Producto'),
                                                          content: Text('¿Estás seguro de que deseas eliminar ${producto['nombre']}?'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(context), 
                                                              child: const Text('Cancelar')
                                                            ),
                                                            TextButton(
                                                              onPressed: () {
                                                                Navigator.pop(context); 
                                                                _eliminarProducto(producto['id']); 
                                                              },
                                                              child: const Text('Eliminar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              )),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}