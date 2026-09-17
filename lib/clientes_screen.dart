import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'registro_cliente_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  List<dynamic> _clientes = [];
  List<dynamic> _clientesFiltrados = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  // NUEVO: Variables para controlar el ordenamiento
  int? _sortColumnIndex;
  bool _isAscending = true;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/clientes'));
      if (response.statusCode == 200) {
        _clientes = jsonDecode(response.body);
        _filtrarClientes(_searchController.text);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filtrarClientes(String query) {
    if (query.isEmpty) {
      setState(() => _clientesFiltrados = List.from(_clientes));
    } else {
      setState(() {
        _clientesFiltrados = _clientes.where((c) {
          final nombre = (c['nombre'] ?? '').toString().toLowerCase();
          final documento = (c['numero_documento'] ?? '').toString().toLowerCase();
          final search = query.toLowerCase();
          return nombre.contains(search) || documento.contains(search);
        }).toList();
      });
    }
  }

  // NUEVO: Función para ordenar alfabéticamente
  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _isAscending = ascending;

      _clientesFiltrados.sort((a, b) {
        String aValue = '';
        String bValue = '';

        if (columnIndex == 0) {
          // Ordenamos por la combinación de V-1234, J-1234
          aValue = '${a['tipo_documento']}-${a['numero_documento']}';
          bValue = '${b['tipo_documento']}-${b['numero_documento']}';
        } else if (columnIndex == 1) {
          // Ordenamos por Nombre
          aValue = a['nombre'] ?? '';
          bValue = b['nombre'] ?? '';
        }

        return ascending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
      });
    });
  }

  Future<void> _eliminarCliente(int id) async {
    try {
      final response = await http.delete(Uri.parse('http://127.0.0.1:3000/api/clientes/$id'));
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Cliente eliminado'), backgroundColor: Colors.red));
          _cargarClientes();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error al eliminar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Directorio de Clientes'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistroClienteScreen()));
                _cargarClientes();
              },
              icon: const Icon(Icons.add), label: const Text('Nuevo Cliente'),
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
                    onChanged: _filtrarClientes,
                    decoration: InputDecoration(
                      hintText: 'Buscar por cédula/RIF o nombre...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _filtrarClientes(''); }),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                      child: _clientesFiltrados.isEmpty
                          ? const Center(child: Text('No hay clientes registrados.', style: TextStyle(color: Colors.grey, fontSize: 16)))
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
                                          DataColumn(label: const Text('Documento', style: TextStyle(fontWeight: FontWeight.bold)), onSort: _onSort),
                                          DataColumn(label: const Text('Nombre / Razón Social', style: TextStyle(fontWeight: FontWeight.bold)), onSort: _onSort),
                                          const DataColumn(label: Text('Correo', style: TextStyle(fontWeight: FontWeight.bold))),
                                          const DataColumn(label: Text('Teléfono', style: TextStyle(fontWeight: FontWeight.bold))),
                                          const DataColumn(label: Text('Dirección', style: TextStyle(fontWeight: FontWeight.bold))),
                                          const DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                        rows: _clientesFiltrados.map((cliente) {
                                          return DataRow(
                                            cells: [
                                              DataCell(Text('${cliente['tipo_documento']}-${cliente['numero_documento']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                              DataCell(Text(cliente['nombre'] ?? '')),
                                              DataCell(Text(cliente['correo']?.toString().isNotEmpty == true ? cliente['correo'] : '-')),
                                              DataCell(Text(cliente['telefono']?.toString().isNotEmpty == true ? cliente['telefono'] : '-')),
                                              DataCell(Text(cliente['direccion']?.toString().isNotEmpty == true ? cliente['direccion'] : '-')),
                                              DataCell(Row(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                                    tooltip: 'Editar',
                                                    onPressed: () async {
                                                      await Navigator.push(context, MaterialPageRoute(builder: (context) => RegistroClienteScreen(clienteAEditar: cliente)));
                                                      _cargarClientes();
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete, color: Colors.red),
                                                    tooltip: 'Eliminar',
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: const Text('Eliminar Cliente'),
                                                          content: Text('¿Estás seguro de eliminar a ${cliente['nombre']}?'),
                                                          actions: [
                                                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                                                            TextButton(
                                                              onPressed: () { Navigator.pop(context); _eliminarCliente(cliente['id']); },
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