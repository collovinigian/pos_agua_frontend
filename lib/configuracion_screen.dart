import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  bool _impresionActiva = false;
  String _modeloActual = 'HKA';
  String _puerto = 'COM1';
  final TextEditingController _copiasController = TextEditingController();

  final List<String> _modelosFiscales = ['HKA', 'Bixolon', 'PNP', 'Bematech', 'Epson', 'Vmax'];
  final List<String> _puertosDisponibles = ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'USB'];

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  Future<void> _cargarConfiguracion() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/configuracion'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _impresionActiva = data['impresion_fiscal_activa'] ?? false;
          _modeloActual = data['modelo_impresora'] ?? 'HKA';
          _puerto = data['puerto_impresora'] ?? 'COM1';
          _copiasController.text = (data['copias_adicionales'] ?? 0).toString();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _guardarCambios() async {
    setState(() => _isSaving = true);
    try {
      final response = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/configuracion'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "impresion_fiscal_activa": _impresionActiva,
          "modelo_impresora": _modeloActual,
          "puerto_impresora": _puerto,
          "copias_adicionales": int.tryParse(_copiasController.text) ?? 0
        })
      );

      if (response.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Configuración de impresora guardada'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error al guardar')));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Sistema'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(32.0),
            children: [
              const Text('Dispositivos e Impresiones', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 8),
              const Text('Configuración local - Afecta solo a este equipo', style: TextStyle(color: Colors.grey)),
              const Divider(height: 32),
              
              SwitchListTile(
                title: const Text('Activar Impresión Fiscal', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Habilita la comunicación con la impresora fiscal por el puerto serial al facturar.'),
                value: _impresionActiva,
                activeThumbColor: Colors.blue,
                onChanged: (val) => setState(() => _impresionActiva = val),
              ),
              const SizedBox(height: 24),

              // Contenedor de opciones bloqueable si el switch está apagado
              Opacity(
                opacity: _impresionActiva ? 1.0 : 0.5,
                child: AbsorbPointer(
                  absorbing: !_impresionActiva,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Modelos de Facturas e Impresoras Fiscales', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Modelo Actual', border: OutlineInputBorder(), prefixIcon: Icon(Icons.print)),
                        initialValue: _modeloActual,
                        items: _modelosFiscales.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: (val) => setState(() => _modeloActual = val!),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Puerto (Impresora)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.usb)),
                              initialValue: _puerto,
                              items: _puertosDisponibles.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                              onChanged: (val) => setState(() => _puerto = val!),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _copiasController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Copias adicionales', border: OutlineInputBorder(), prefixIcon: Icon(Icons.file_copy)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _guardarCambios,
                icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
                label: const Text('Guardar los Cambios', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}