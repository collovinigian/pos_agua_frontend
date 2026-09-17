import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegistroClienteScreen extends StatefulWidget {
  final Map<String, dynamic>? clienteAEditar;
  const RegistroClienteScreen({super.key, this.clienteAEditar});

  @override
  State<RegistroClienteScreen> createState() => _RegistroClienteScreenState();
}

class _RegistroClienteScreenState extends State<RegistroClienteScreen> {
  final TextEditingController _documentoController = TextEditingController();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _correoController = TextEditingController(); // NUEVO
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  
  String _tipoDocumento = 'V'; 
  bool _isLoading = false;

  bool get _isEditing => widget.clienteAEditar != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _tipoDocumento = widget.clienteAEditar!['tipo_documento'] ?? 'V';
      _documentoController.text = widget.clienteAEditar!['numero_documento'] ?? '';
      _nombreController.text = widget.clienteAEditar!['nombre'] ?? '';
      _correoController.text = widget.clienteAEditar!['correo'] ?? ''; // NUEVO
      _telefonoController.text = widget.clienteAEditar!['telefono'] ?? '';
      _direccionController.text = widget.clienteAEditar!['direccion'] ?? '';
    }
  }

  Future<void> _guardarCliente() async {
    if (_documentoController.text.isEmpty || _nombreController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ El documento y nombre son obligatorios')));
      return;
    }
    setState(() => _isLoading = true);
    
    try {
      final url = _isEditing 
          ? Uri.parse('http://127.0.0.1:3000/api/clientes/${widget.clienteAEditar!['id']}')
          : Uri.parse('http://127.0.0.1:3000/api/clientes');

      final bodyData = jsonEncode({
        "tipo_documento": _tipoDocumento,
        "numero_documento": _documentoController.text,
        "nombre": _nombreController.text,
        "correo": _correoController.text, // NUEVO
        "telefono": _telefonoController.text,
        "direccion": _direccionController.text,
      });

      final response = _isEditing
          ? await http.put(url, headers: {"Content-Type": "application/json"}, body: bodyData)
          : await http.post(url, headers: {"Content-Type": "application/json"}, body: bodyData);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditing ? '✅ Cliente actualizado' : '✅ Cliente registrado'), backgroundColor: Colors.green));
          if (_isEditing) {
            Navigator.pop(context);
          } else {
            _documentoController.clear(); _nombreController.clear(); _correoController.clear(); _telefonoController.clear(); _direccionController.clear();
          }
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${response.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error conectando al servidor.')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Cliente' : 'Nuevo Cliente'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_add_alt_1, size: 64, color: Colors.blue),
                const SizedBox(height: 24),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: DropdownButtonFormField<String>(
                        value: _tipoDocumento,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: ['V', 'E', 'J', 'G'].map((tipo) => DropdownMenuItem(value: tipo, child: Text(tipo))).toList(),
                        onChanged: (val) => setState(() => _tipoDocumento = val!),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _documentoController, 
                        decoration: const InputDecoration(labelText: 'Número de Cédula o RIF*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))
                      )
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre o Razón Social*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business))),
                const SizedBox(height: 16),
                TextField(controller: _correoController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo Electrónico (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))), // NUEVO CAMPO VISUAL
                const SizedBox(height: 16),
                TextField(controller: _telefonoController, decoration: const InputDecoration(labelText: 'Teléfono (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                const SizedBox(height: 16),
                TextField(controller: _direccionController, maxLines: 2, decoration: const InputDecoration(labelText: 'Dirección (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.map))),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _guardarCliente,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                  child: _isLoading ? const CircularProgressIndicator() : Text(_isEditing ? 'Actualizar Cliente' : 'Guardar Cliente', style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}