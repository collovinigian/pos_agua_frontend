import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegistroProductoScreen extends StatefulWidget {
  final Map<String, dynamic>? productoAEditar;

  const RegistroProductoScreen({super.key, this.productoAEditar});

  @override
  State<RegistroProductoScreen> createState() => _RegistroProductoScreenState();
}

class _RegistroProductoScreenState extends State<RegistroProductoScreen> {
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _codigoBarrasController = TextEditingController();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _detallesController = TextEditingController(); // NUEVO
  final TextEditingController _cantidadController = TextEditingController(text: '0'); // NUEVO
  final TextEditingController _precioUsdController = TextEditingController();
  final TextEditingController _precioBsController = TextEditingController();
  
  bool _aplicaIva = true; // NUEVO: Por defecto sí aplica IVA (16%)
  bool _isLoading = false;
  double _tasaBcv = 0.0;
  bool _isTyping = false; 

  bool get _isEditing => widget.productoAEditar != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _codigoController.text = widget.productoAEditar!['codigo_producto'] ?? '';
      _codigoBarrasController.text = widget.productoAEditar!['codigo_barras'] ?? '';
      _nombreController.text = widget.productoAEditar!['nombre'] ?? '';
      _detallesController.text = widget.productoAEditar!['detalles'] ?? '';
      _cantidadController.text = (widget.productoAEditar!['cantidad'] ?? 0).toString();
      _precioUsdController.text = widget.productoAEditar!['precio_usd'].toString();
      _aplicaIva = widget.productoAEditar!['aplica_iva'] ?? true;
    }
    _obtenerTasaActual();
  }

  Future<void> _obtenerTasaActual() async {
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/tasas/actual'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _tasaBcv = double.parse(data['tasa_bcv'].toString()); 
          if (_isEditing && _precioUsdController.text.isNotEmpty) {
            _precioBsController.text = (double.parse(_precioUsdController.text) * _tasaBcv).toStringAsFixed(2);
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error de Tasa: $e')));
    }
  }

  void _calcularBs(String valorUsd) {
    if (_isTyping) return;
    if (valorUsd.isEmpty) {
      _isTyping = true; _precioBsController.clear(); _isTyping = false; return;
    }
    final usd = double.tryParse(valorUsd);
    if (usd != null && _tasaBcv > 0) {
      _isTyping = true; _precioBsController.text = (usd * _tasaBcv).toStringAsFixed(2); _isTyping = false;
    }
  }

  void _calcularUsd(String valorBs) {
    if (_isTyping) return;
    if (valorBs.isEmpty) {
      _isTyping = true; _precioUsdController.clear(); _isTyping = false; return;
    }
    final bs = double.tryParse(valorBs);
    if (bs != null && _tasaBcv > 0) {
      _isTyping = true; _precioUsdController.text = (bs / _tasaBcv).toStringAsFixed(2); _isTyping = false;
    }
  }

  Future<void> _guardarProducto() async {
    if (_codigoController.text.isEmpty || _nombreController.text.isEmpty || _precioUsdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Código, nombre y precio son obligatorios')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final url = _isEditing 
          ? Uri.parse('http://127.0.0.1:3000/api/productos/${widget.productoAEditar!['id']}')
          : Uri.parse('http://127.0.0.1:3000/api/productos');

      final bodyData = jsonEncode({
        "codigo_producto": _codigoController.text.toUpperCase(),
        "codigo_barras": _codigoBarrasController.text.isEmpty ? null : _codigoBarrasController.text,
        "nombre": _nombreController.text,
        "detalles": _detallesController.text, // GUARDAMOS DETALLES
        "cantidad": int.tryParse(_cantidadController.text) ?? 0, // GUARDAMOS CANTIDAD
        "precio_usd": double.parse(_precioUsdController.text),
        "aplica_iva": _aplicaIva // GUARDAMOS IVA
      });

      final response = _isEditing
          ? await http.put(url, headers: {"Content-Type": "application/json"}, body: bodyData)
          : await http.post(url, headers: {"Content-Type": "application/json"}, body: bodyData);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditing ? '✅ Actualizado' : '✅ Guardado'), backgroundColor: Colors.green));
          if (_isEditing) {
            Navigator.pop(context);
          } else {
            _codigoController.clear(); _codigoBarrasController.clear(); _nombreController.clear();
            _detallesController.clear(); _cantidadController.text = '0';
            _precioUsdController.clear(); _precioBsController.clear();
          }
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: ${response.body}')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Error conectando.')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Producto' : 'Nuevo Producto'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500), // Lo hice un poco más ancho
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tasaBcv > 0 ? 'Tasa Activa: $_tasaBcv Bs' : 'Cargando tasa...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                // --- SECCIÓN 1: IDENTIFICACIÓN ---
                Row(
                  children: [
                    Expanded(child: TextField(controller: _codigoController, decoration: const InputDecoration(labelText: 'Código SKU*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code)))),
                    const SizedBox(width: 16),
                    Expanded(child: TextField(controller: _codigoBarrasController, decoration: const InputDecoration(labelText: 'Cód. Barras', border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code_scanner)))),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre del Producto*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.water_drop))),
                const SizedBox(height: 16),
                TextField(controller: _detallesController, maxLines: 2, decoration: const InputDecoration(labelText: 'Detalles / Descripción (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description))),
                const SizedBox(height: 16),
                
                // --- SECCIÓN 2: INVENTARIO Y PRECIO ---
                Row(
                  children: [
                    Expanded(child: TextField(controller: _cantidadController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock (Cantidad)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.inventory)))),
                    const SizedBox(width: 16),
                    Expanded(child: TextField(controller: _precioUsdController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: _calcularBs, decoration: const InputDecoration(labelText: 'Precio USD*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)))),
                    const SizedBox(width: 16),
                    Expanded(child: TextField(controller: _precioBsController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: _calcularUsd, decoration: const InputDecoration(labelText: 'Precio Bs', border: OutlineInputBorder(), prefixIcon: Text('Bs ', style: TextStyle(fontWeight: FontWeight.bold)), prefixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 0)))),
                  ],
                ),
                const SizedBox(height: 16),
                
                // --- SECCIÓN 3: IMPUESTOS ---
                Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                  child: SwitchListTile(
                    title: const Text('Aplica IVA (16%)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Marcar si el producto debe sumar IVA al facturar.'),
                    value: _aplicaIva,
                    onChanged: (bool valor) => setState(() => _aplicaIva = valor),
                  ),
                ),
                const SizedBox(height: 32),
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _guardarProducto,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                  child: _isLoading ? const CircularProgressIndicator() : Text(_isEditing ? 'Actualizar Producto' : 'Guardar Producto', style: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}