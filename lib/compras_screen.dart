import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_events.dart';
import 'producto_screen.dart';

enum TipoRenglon { producto, servicio }

class ComprasScreen extends StatefulWidget {
  const ComprasScreen({super.key});

  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends State<ComprasScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TipoRenglon _tipoRenglon = TipoRenglon.producto;

  // Datos Fiscales del Agente de Retención (Nuestra Empresa)
  static const Map<String, String> agenteRetencion = {
    'razon_social': 'AGUA GRAND, C.A.',
    'rif': 'J-408854619',
    'rif_seniat': 'J408854619',
    'direccion': 'AV RAUL LEONI LOCAL NRO 3 ZONA INDUSTRIAL LOS MONTONES BARCELONA ANZOATEGUI ZONA POSTAL 6001'
  };

  // Datos globales compartidos
  bool _isLoading = true;
  double _tasaBcv = 0.0;
  List<dynamic> _proveedores = [];
  List<dynamic> _productos = [];
  List<dynamic> _comprasOriginales = [];
  List<dynamic> _comprasFiltradas = [];

  // ==========================================
  // ESTADO PESTAÑA 1: REGISTRAR COMPRA / NOTA
  // ==========================================
  final TextEditingController _searchProveedorController = TextEditingController();
  final TextEditingController _numeroFacturaController = TextEditingController();
  final TextEditingController _numeroControlController = TextEditingController();
  final TextEditingController _facturaAfectadaController = TextEditingController();
  final TextEditingController _tasaBcvController = TextEditingController();
  final TextEditingController _diasCreditoController = TextEditingController(text: '0');

  // Renglón actual y cálculo bidireccional
  final TextEditingController _searchProductoController = TextEditingController();
  final TextEditingController _descripcionItemController = TextEditingController();
  final TextEditingController _cantidadController = TextEditingController(text: '1');
  final TextEditingController _costoUnitarioController = TextEditingController();
  final TextEditingController _costoUnitarioBsController = TextEditingController();
  final TextEditingController _nuevoPrecioVentaController = TextEditingController();
  bool _isTypingCosto = false;

  Map<String, dynamic>? _proveedorSeleccionado;
  String _tipoDocumentoFiscal = 'FACTURA'; // FACTURA, NOTA_CREDITO, NOTA_DEBITO
  DateTime _fechaEmision = DateTime.now();
  String _metodoPago = 'Efectivo';
  bool _itemAplicaIva = false;
  Map<String, dynamic>? _productoRenglonSeleccionado;
  bool _guardandoCompra = false;

  // Retenciones Fiscales
  bool _aplicaRetencionIva = false;
  int _porcentajeRetIva = 75; // 75 o 100
  bool _aplicaRetencionIslr = false;
  String _conceptoIslrSeleccionado = '053';
  final TextEditingController _codigoConceptoIslrController = TextEditingController(text: '053');
  final TextEditingController _conceptoIslrController = TextEditingController(text: 'Transporte de Carga / Fletes');
  final TextEditingController _porcentajeRetIslrController = TextEditingController(text: '3.00');
  final TextEditingController _sustraendoIslrBsController = TextEditingController(text: '0.00');

  // Carrito de compra
  final List<Map<String, dynamic>> _renglonesCompra = [];

  // ==========================================
  // ESTADO PESTAÑA 2: LIBRO DE COMPRAS Y CXP
  // ==========================================
  final TextEditingController _searchComprasController = TextEditingController();
  String _searchComprasQuery = '';
  DateTime? _fechaInicio = DateTime.now();
  DateTime? _fechaFin = DateTime.now();
  String _filtroEstado = 'TODAS'; // TODAS, PAGADA, PENDIENTE, ANULADA
  String _etiquetaPeriodo = 'Hoy';

  // ==========================================
  // ESTADO PESTAÑA 3: PROVEEDORES
  // ==========================================
  final TextEditingController _searchProveedoresTabController = TextEditingController();
  List<dynamic> _proveedoresTabFiltrados = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarDatosIniciales();
    AppEvents.refreshNotifier.addListener(_cargarDatosIniciales);
  }

  @override
  void dispose() {
    AppEvents.refreshNotifier.removeListener(_cargarDatosIniciales);
    _tabController.dispose();

    _searchProveedorController.dispose();
    _numeroFacturaController.dispose();
    _numeroControlController.dispose();
    _facturaAfectadaController.dispose();
    _tasaBcvController.dispose();
    _diasCreditoController.dispose();

    _searchProductoController.dispose();
    _descripcionItemController.dispose();
    _cantidadController.dispose();
    _costoUnitarioController.dispose();
    _costoUnitarioBsController.dispose();
    _nuevoPrecioVentaController.dispose();

    _codigoConceptoIslrController.dispose();
    _conceptoIslrController.dispose();
    _porcentajeRetIslrController.dispose();
    _sustraendoIslrBsController.dispose();

    _searchComprasController.dispose();
    _searchProveedoresTabController.dispose();
    super.dispose();
  }

  // =========================================================================
  // CARGA DE DATOS CENTRALIZADA
  // =========================================================================
  Future<void> _cargarDatosIniciales() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Tasa BCV
      final resTasa = await http.get(Uri.parse('http://127.0.0.1:3000/api/tasas/actual'));
      if (resTasa.statusCode == 200) {
        final dataTasa = jsonDecode(resTasa.body);
        _tasaBcv = double.tryParse(dataTasa['tasa_bcv'].toString()) ?? 0.0;
        if (_tasaBcvController.text.isEmpty || double.tryParse(_tasaBcvController.text) == 0.0) {
          _tasaBcvController.text = _tasaBcv.toStringAsFixed(2);
        }
      }

      // 2. Proveedores
      final resProv = await http.get(Uri.parse('http://127.0.0.1:3000/api/proveedores'));
      if (resProv.statusCode == 200) {
        _proveedores = jsonDecode(resProv.body);
        _filtrarProveedoresTab(_searchProveedoresTabController.text);
      }

      // 3. Productos (Catálogo)
      final resProd = await http.get(Uri.parse('http://127.0.0.1:3000/api/productos'));
      if (resProd.statusCode == 200) {
        _productos = jsonDecode(resProd.body);
      }

      // 4. Compras (Historial / Libro)
      await _cargarCompras();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos del módulo: $e'), backgroundColor: Colors.red.shade700)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarCompras() async {
    try {
      String queryParams = '';
      if (_fechaInicio != null && _fechaFin != null) {
        String inicioStr = "${DateFormat('yyyy-MM-dd').format(_fechaInicio!)}T00:00:00";
        String finStr = "${DateFormat('yyyy-MM-dd').format(_fechaFin!)}T23:59:59";
        queryParams = '?fecha_inicio=$inicioStr&fecha_fin=$finStr';
      }

      final resCompras = await http.get(Uri.parse('http://127.0.0.1:3000/api/compras$queryParams'));
      if (resCompras.statusCode == 200) {
        _comprasOriginales = jsonDecode(resCompras.body);
        _aplicarFiltroEstadoCompras(_filtroEstado);
      }
    } catch (e) {
      debugPrint("Error cargando compras: $e");
    }
  }

  // =========================================================================
  // CÁLCULO BIDIRECCIONAL ($ / Bs)
  // =========================================================================
  void _onCostoUsdChanged(String val) {
    if (_isTypingCosto) return;
    _isTypingCosto = true;
    final usd = double.tryParse(val.replaceAll(',', '.'));
    final tasa = double.tryParse(_tasaBcvController.text.replaceAll(',', '.')) ?? _tasaBcv;
    if (usd != null && tasa > 0) {
      _costoUnitarioBsController.text = (usd * tasa).toStringAsFixed(2);
    } else {
      _costoUnitarioBsController.clear();
    }
    _isTypingCosto = false;
    setState(() {});
  }

  void _onCostoBsChanged(String val) {
    if (_isTypingCosto) return;
    _isTypingCosto = true;
    final bs = double.tryParse(val.replaceAll(',', '.'));
    final tasa = double.tryParse(_tasaBcvController.text.replaceAll(',', '.')) ?? _tasaBcv;
    if (bs != null && tasa > 0) {
      _costoUnitarioController.text = (bs / tasa).toStringAsFixed(4);
    } else {
      _costoUnitarioController.clear();
    }
    _isTypingCosto = false;
    setState(() {});
  }

  void _actualizarConversionPorCambioTasa() {
    final tasa = double.tryParse(_tasaBcvController.text.replaceAll(',', '.')) ?? _tasaBcv;
    if (!_isTypingCosto && _costoUnitarioBsController.text.isNotEmpty) {
      final bs = double.tryParse(_costoUnitarioBsController.text.replaceAll(',', '.'));
      if (bs != null && tasa > 0) {
        _costoUnitarioController.text = (bs / tasa).toStringAsFixed(4);
      }
    } else if (!_isTypingCosto && _costoUnitarioController.text.isNotEmpty) {
      final usd = double.tryParse(_costoUnitarioController.text.replaceAll(',', '.'));
      if (usd != null && tasa > 0) {
        _costoUnitarioBsController.text = (usd * tasa).toStringAsFixed(2);
      }
    }
    setState(() {});
  }

  // =========================================================================
  // PESTAÑA 1: LÓGICA DE REGISTRO DE COMPRA / NOTAS
  // =========================================================================

  void _buscarProveedorInteligente() {
    String textoBuscado = _searchProveedorController.text.trim().toLowerCase();
    if (textoBuscado.isEmpty) return;

    String textoLimpio = textoBuscado.replaceAll(RegExp(r'[^a-z0-9]'), '');

    List<dynamic> coincidencias = _proveedores.where((p) {
      String nombre = (p['nombre'] ?? '').toString().toLowerCase();
      String docCompleto = '${p['tipo_documento']}${p['numero_documento']}'.toLowerCase();

      String nombreLimpio = nombre.replaceAll(RegExp(r'[^a-z0-9]'), '');
      String docCompletoLimpio = docCompleto.replaceAll(RegExp(r'[^a-z0-9]'), '');

      bool matchDoc = textoLimpio.isNotEmpty && docCompletoLimpio.contains(textoLimpio);
      bool matchNombre = nombre.contains(textoBuscado) || (textoLimpio.isNotEmpty && nombreLimpio.contains(textoLimpio));

      return matchNombre || matchDoc;
    }).toList();

    if (coincidencias.isEmpty) {
      _mostrarDialogoRegistroRapidoProveedor(textoBuscado);
    } else if (coincidencias.length == 1) {
      _seleccionarProveedor(coincidencias.first);
    } else {
      _mostrarDialogoSeleccionarProveedor(coincidencias);
    }
  }

  void _seleccionarProveedor(dynamic proveedor) {
    setState(() {
      _proveedorSeleccionado = proveedor;
      _searchProveedorController.text = proveedor['nombre'] ?? '';

      int diasHabituales = proveedor['dias_credito_habitual'] ?? 0;
      if (diasHabituales > 0) {
        _metodoPago = 'Crédito';
        _diasCreditoController.text = diasHabituales.toString();
      }

      // Configuración automática de Retención de IVA del proveedor
      int retIvaProv = proveedor['porcentaje_retencion_iva'] ?? 75;
      if (retIvaProv > 0) {
        _aplicaRetencionIva = true;
        _porcentajeRetIva = (retIvaProv == 100) ? 100 : 75;
      } else {
        _aplicaRetencionIva = false;
      }

      // Configuración automática de Retención de ISLR del proveedor
      double retIslrProv = (proveedor['porcentaje_retencion_islr'] as num?)?.toDouble() ?? 0.0;
      if (retIslrProv > 0) {
        _aplicaRetencionIslr = true;
        _porcentajeRetIslrController.text = retIslrProv.toStringAsFixed(2);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Proveedor seleccionado: ${proveedor['nombre']} (${proveedor['tipo_documento']}-${proveedor['numero_documento']})'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _mostrarDialogoSeleccionarProveedor(List<dynamic> lista) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coincidencias de Proveedores', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: lista.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final prov = lista[index];
              return ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.business, color: Colors.white)),
                title: Text(prov['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('RIF: ${prov['tipo_documento']}-${prov['numero_documento']} | Ret. IVA: ${prov['porcentaje_retencion_iva'] ?? 75}%'),
                onTap: () {
                  Navigator.pop(ctx);
                  _seleccionarProveedor(prov);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))
        ],
      )
    );
  }

  void _mostrarDialogoRegistroRapidoProveedor([String initialValue = '']) {
    String tipoDoc = 'J';
    int retIvaVal = 75;
    final TextEditingController numDocCtrl = TextEditingController();
    final TextEditingController nombreCtrl = TextEditingController();
    final TextEditingController tlfCtrl = TextEditingController();
    final TextEditingController correoCtrl = TextEditingController();
    final TextEditingController dirCtrl = TextEditingController();
    final TextEditingController diasCredCtrl = TextEditingController(text: '0');
    final TextEditingController retIslrCtrl = TextEditingController(text: '0.00');

    String limpia = initialValue.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (RegExp(r'^[jgvJGV]').hasMatch(limpia) && limpia.length > 2) {
      tipoDoc = limpia[0].toUpperCase();
      numDocCtrl.text = limpia.substring(1);
    } else if (RegExp(r'^[0-9]+$').hasMatch(limpia)) {
      numDocCtrl.text = limpia;
    } else {
      nombreCtrl.text = initialValue;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setStateModal) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_add, color: Colors.blue),
                SizedBox(width: 8),
                Text('Registro Rápido de Proveedor', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 85,
                          child: DropdownButtonFormField<String>(
                            initialValue: tipoDoc,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                            items: ['J', 'G', 'V', 'E'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) => setStateModal(() => tipoDoc = val!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: numDocCtrl,
                            decoration: const InputDecoration(labelText: 'N° Documento / RIF *', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Razón Social / Nombre Completo *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: tlfCtrl,
                            decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: correoCtrl,
                            decoration: const InputDecoration(labelText: 'Correo Electrónico', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dirCtrl,
                      decoration: const InputDecoration(labelText: 'Dirección Fiscal', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: diasCredCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Días Crédito Habitual', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: retIvaVal,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '% Retención IVA *', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('0% (No aplica)')),
                              DropdownMenuItem(value: 75, child: Text('75% (Ordinario)')),
                              DropdownMenuItem(value: 100, child: Text('100% (Especial)')),
                            ],
                            onChanged: (val) => setStateModal(() => retIvaVal = val!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: retIslrCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: '% Ret. ISLR Habitual', suffixText: '%', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                onPressed: () async {
                  if (numDocCtrl.text.trim().isEmpty || nombreCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ RIF y Nombre son obligatorios'), backgroundColor: Colors.orange)
                    );
                    return;
                  }

                  try {
                    final body = jsonEncode({
                      "tipo_documento": tipoDoc,
                      "numero_documento": numDocCtrl.text.trim(),
                      "nombre": nombreCtrl.text.trim(),
                      "telefono": tlfCtrl.text.trim(),
                      "correo": correoCtrl.text.trim(),
                      "direccion": dirCtrl.text.trim(),
                      "dias_credito_habitual": int.tryParse(diasCredCtrl.text.trim()) ?? 0,
                      "porcentaje_retencion_iva": retIvaVal,
                      "porcentaje_retencion_islr": double.tryParse(retIslrCtrl.text.trim()) ?? 0.0
                    });

                    final res = await http.post(
                      Uri.parse('http://127.0.0.1:3000/api/proveedores'),
                      headers: {'Content-Type': 'application/json'},
                      body: body
                    );

                    if (res.statusCode == 201 || res.statusCode == 200) {
                      final data = jsonDecode(res.body)['data'];
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _cargarDatosIniciales();
                      _seleccionarProveedor(data);
                      AppEvents.dispararActualizacion();
                    } else {
                      String msg = 'Error registrando proveedor';
                      try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red)
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('❌ Error de conexión: $e'), backgroundColor: Colors.red)
                      );
                    }
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Guardar y Seleccionar'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              )
            ],
          );
        }
      )
    );
  }

  void _seleccionarProductoParaRenglon(Map<String, dynamic> prod) {
    setState(() {
      _productoRenglonSeleccionado = prod;
      _searchProductoController.text = '${prod['codigo_producto']} - ${prod['nombre']}';
      _descripcionItemController.text = prod['nombre'] ?? '';
      _itemAplicaIva = prod['aplica_iva'] ?? false;
      _costoUnitarioController.clear();
      _costoUnitarioBsController.clear();
      _nuevoPrecioVentaController.clear();
    });
  }

  void _agregarRenglonAlCarrito() {
    final cant = int.tryParse(_cantidadController.text) ?? 0;
    final tasa = double.tryParse(_tasaBcvController.text.replaceAll(',', '.')) ?? _tasaBcv;
    final tasaVal = tasa > 0 ? tasa : 1.0;

    double costoBs = double.tryParse(_costoUnitarioBsController.text.replaceAll(',', '.')) ?? 0.0;
    double costoUsd = double.tryParse(_costoUnitarioController.text.replaceAll(',', '.')) ?? 0.0;

    if (costoBs > 0 && costoUsd == 0) {
      costoUsd = double.parse((costoBs / tasaVal).toStringAsFixed(4));
    } else if (costoUsd > 0 && costoBs == 0) {
      costoBs = double.parse((costoUsd * tasaVal).toStringAsFixed(2));
    }

    final desc = _descripcionItemController.text.trim();

    if (_tipoRenglon == TipoRenglon.producto && _productoRenglonSeleccionado == null && desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Debe seleccionar un producto del catálogo o cambiar a Servicio / Gasto'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Debe especificar una descripción del renglón'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (cant <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ La cantidad debe ser mayor a 0'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (costoBs < 0 || costoUsd < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ El costo no puede ser negativo'), backgroundColor: Colors.orange)
      );
      return;
    }

    final subtotalBs = double.parse((cant * costoBs).toStringAsFixed(2));
    final subtotalUsd = double.parse((cant * costoUsd).toStringAsFixed(2));
    final nuevoPrecioVenta = _tipoRenglon == TipoRenglon.producto
        ? double.tryParse(_nuevoPrecioVentaController.text.replaceAll(',', '.'))
        : null;

    setState(() {
      _renglonesCompra.add({
        'producto_id': _tipoRenglon == TipoRenglon.producto && _productoRenglonSeleccionado != null
            ? _productoRenglonSeleccionado!['id']
            : null,
        'codigo_producto': _tipoRenglon == TipoRenglon.producto && _productoRenglonSeleccionado != null
            ? _productoRenglonSeleccionado!['codigo_producto']
            : 'SERVICIO/GASTO',
        'descripcion': desc,
        'cantidad': cant,
        'costo_unitario_bs': costoBs,
        'costo_unitario_usd': costoUsd,
        'aplica_iva': _itemAplicaIva,
        'subtotal_bs': subtotalBs,
        'subtotal_usd': subtotalUsd,
        'nuevo_precio_usd': nuevoPrecioVenta,
        'precio_venta_actual': (_tipoRenglon == TipoRenglon.producto && _productoRenglonSeleccionado != null)
            ? (double.tryParse(_productoRenglonSeleccionado!['precio_usd'].toString()) ?? 0.0)
            : null
      });

      // Limpiar campos de renglón
      _productoRenglonSeleccionado = null;
      _searchProductoController.clear();
      _descripcionItemController.clear();
      _cantidadController.text = '1';
      _costoUnitarioController.clear();
      _costoUnitarioBsController.clear();
      _nuevoPrecioVentaController.clear();
      _itemAplicaIva = false;
    });
  }

  void _eliminarRenglon(int index) {
    setState(() {
      _renglonesCompra.removeAt(index);
    });
  }

  // =========================================================================
  // CÁLCULO DE TOTALES FISCALES Y RETENCIONES (BASE EN BOLÍVARES)
  // =========================================================================
  Map<String, double> _calcularTotalesCompra() {
    double exentoBs = 0.0;
    double baseBs = 0.0;
    double tasa = double.tryParse(_tasaBcvController.text.replaceAll(',', '.')) ?? _tasaBcv;
    if (tasa <= 0) tasa = 1.0;

    for (final item in _renglonesCompra) {
      final double subBs = (item['subtotal_bs'] as num?)?.toDouble() ?? 
          (((item['subtotal_usd'] as num?)?.toDouble() ?? 0.0) * tasa);
      final llevaIva = item['aplica_iva'] == true;

      if (llevaIva) {
        baseBs += subBs;
      } else {
        exentoBs += subBs;
      }
    }

    baseBs = double.parse(baseBs.toStringAsFixed(2));
    exentoBs = double.parse(exentoBs.toStringAsFixed(2));

    final ivaBs = double.parse((baseBs * 0.16).toStringAsFixed(2));
    final totalBs = double.parse((baseBs + exentoBs + ivaBs).toStringAsFixed(2));

    // Retención de IVA (75% o 100%) calculada en Bs
    double ivaRetenidoBs = 0.0;
    if (_aplicaRetencionIva && ivaBs > 0) {
      final factorIva = _porcentajeRetIva / 100.0;
      ivaRetenidoBs = double.parse((ivaBs * factorIva).toStringAsFixed(2));
    }

    // Retención de ISLR calculada directamente en Bs (sin sustraendo manual)
    double islrRetenidoBs = 0.0;
    if (_aplicaRetencionIslr && baseBs > 0) {
      final porcIslr = double.tryParse(_porcentajeRetIslrController.text.replaceAll(',', '.')) ?? 0.0;
      islrRetenidoBs = double.parse((baseBs * (porcIslr / 100.0)).toStringAsFixed(2));
      if (islrRetenidoBs < 0) islrRetenidoBs = 0.0;
    }

    final netoPagarBs = math.max(0.0, double.parse((totalBs - ivaRetenidoBs - islrRetenidoBs).toStringAsFixed(2)));

    // Totales en Dólares (Solo Referencia contable dividida por tasa BCV)
    final exentoUsd = double.parse((exentoBs / tasa).toStringAsFixed(2));
    final baseUsd = double.parse((baseBs / tasa).toStringAsFixed(2));
    final ivaUsd = double.parse((ivaBs / tasa).toStringAsFixed(2));
    final totalUsd = double.parse((totalBs / tasa).toStringAsFixed(2));
    final ivaRetenidoUsd = double.parse((ivaRetenidoBs / tasa).toStringAsFixed(2));
    final islrRetenidoUsd = double.parse((islrRetenidoBs / tasa).toStringAsFixed(2));
    final netoPagarUsd = double.parse((netoPagarBs / tasa).toStringAsFixed(2));

    return {
      'exento_bs': exentoBs,
      'base_bs': baseBs,
      'iva_bs': ivaBs,
      'total_bs': totalBs,
      'iva_retenido_bs': ivaRetenidoBs,
      'islr_retenido_bs': islrRetenidoBs,
      'neto_pagar_bs': netoPagarBs,

      'exento_usd': exentoUsd,
      'base_usd': baseUsd,
      'iva_usd': ivaUsd,
      'total_usd': totalUsd,
      'iva_retenido_usd': ivaRetenidoUsd,
      'islr_retenido_usd': islrRetenidoUsd,
      'neto_pagar_usd': netoPagarUsd,
    };
  }

  void _seleccionarConceptoIslr(String codigo) {
    setState(() {
      _conceptoIslrSeleccionado = codigo;
      _codigoConceptoIslrController.text = codigo;
      switch (codigo) {
        case '053':
          _conceptoIslrController.text = 'Transporte de Carga / Fletes (3%)';
          _porcentajeRetIslrController.text = '3.00';
          break;
        case '014':
          _conceptoIslrController.text = 'Ejecución de Obras y Servicios / Contratistas (2%)';
          _porcentajeRetIslrController.text = '2.00';
          break;
        case '004':
          _conceptoIslrController.text = 'Honorarios Profesionales (3%)';
          _porcentajeRetIslrController.text = '3.00';
          break;
        case '029':
          _conceptoIslrController.text = 'Publicidad y Propaganda (3%)';
          _porcentajeRetIslrController.text = '3.00';
          break;
        case 'OTRO':
          _conceptoIslrController.text = 'Concepto Personalizado';
          break;
      }
    });
  }

  Future<void> _guardarCompra() async {
    if (_proveedorSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Debe seleccionar o registrar un Proveedor'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (_numeroFacturaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ El N° de Factura / Documento es obligatorio'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (_numeroControlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ El N° de Control fiscal es obligatorio según normativa SENIAT'), backgroundColor: Colors.orange)
      );
      return;
    }

    if ((_tipoDocumentoFiscal == 'NOTA_CREDITO' || _tipoDocumentoFiscal == 'NOTA_DEBITO') &&
        _facturaAfectadaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Para Notas de Débito o Crédito es obligatorio indicar la Factura Afectada'), backgroundColor: Colors.orange)
      );
      return;
    }

    if (_renglonesCompra.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Debe agregar al menos un renglón a la compra'), backgroundColor: Colors.orange)
      );
      return;
    }

    final tasa = double.tryParse(_tasaBcvController.text.replaceAll(',', '.')) ?? _tasaBcv;
    if (tasa <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Ingrese una Tasa BCV válida'), backgroundColor: Colors.orange)
      );
      return;
    }

    final totales = _calcularTotalesCompra();
    final diasCred = int.tryParse(_diasCreditoController.text) ?? 0;

    setState(() => _guardandoCompra = true);

    try {
      final body = jsonEncode({
        "proveedor_id": _proveedorSeleccionado!['id'],
        "tipo_documento_fiscal": _tipoDocumentoFiscal,
        "numero_factura": _numeroFacturaController.text.trim(),
        "numero_control": _numeroControlController.text.trim(),
        "factura_afectada": (_tipoDocumentoFiscal != 'FACTURA') ? _facturaAfectadaController.text.trim() : null,
        "fecha_emision": DateFormat('yyyy-MM-dd').format(_fechaEmision),
        "fecha_recepcion": DateTime.now().toIso8601String(),
        "tasa_bcv": tasa,
        "monto_exento_bs": totales['exento_bs'],
        "base_imponible_bs": totales['base_bs'],
        "iva_bs": totales['iva_bs'],
        "total_bs": totales['total_bs'],
        "monto_exento_usd": totales['exento_usd'],
        "base_imponible_usd": totales['base_usd'],
        "iva_usd": totales['iva_usd'],
        "total_usd": totales['total_usd'],
        "dias_credito": (_metodoPago == 'Crédito' || diasCred > 0) ? diasCred : 0,
        "metodo_pago": _metodoPago,

        // Retenciones
        "aplica_retencion_iva": _aplicaRetencionIva,
        "porcentaje_ret_iva": _aplicaRetencionIva ? _porcentajeRetIva : 0,
        "iva_retenido_usd": totales['iva_retenido_usd'],
        "iva_retenido_bs": totales['iva_retenido_bs'],

        "aplica_retencion_islr": _aplicaRetencionIslr,
        "codigo_concepto_islr": _aplicaRetencionIslr ? _codigoConceptoIslrController.text.trim() : null,
        "concepto_islr": _aplicaRetencionIslr ? _conceptoIslrController.text.trim() : null,
        "porcentaje_ret_islr": _aplicaRetencionIslr ? (double.tryParse(_porcentajeRetIslrController.text.replaceAll(',', '.')) ?? 0.0) : 0,
        "sustraendo_islr_bs": 0.0,
        "islr_retenido_usd": totales['islr_retenido_usd'],
        "islr_retenido_bs": totales['islr_retenido_bs'],

        "neto_pagar_usd": totales['neto_pagar_usd'],
        "neto_pagar_bs": totales['neto_pagar_bs'],

        "detalles": _renglonesCompra.map((item) => {
          "producto_id": item['producto_id'],
          "descripcion": item['descripcion'],
          "cantidad": item['cantidad'],
          "costo_unitario_bs": item['costo_unitario_bs'],
          "costo_unitario_usd": item['costo_unitario_usd'],
          "aplica_iva": item['aplica_iva'],
          "subtotal_bs": item['subtotal_bs'],
          "subtotal_usd": item['subtotal_usd'],
          "nuevo_precio_usd": item['nuevo_precio_usd']
        }).toList()
      });

      final res = await http.post(
        Uri.parse('http://127.0.0.1:3000/api/compras'),
        headers: {'Content-Type': 'application/json'},
        body: body
      );

      if (res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $_tipoDocumentoFiscal registrada con éxito. Inventario y retenciones procesados.'),
              backgroundColor: Colors.green.shade700
            )
          );
        }

        // Limpiar formulario completo
        setState(() {
          _proveedorSeleccionado = null;
          _searchProveedorController.clear();
          _numeroFacturaController.clear();
          _numeroControlController.clear();
          _facturaAfectadaController.clear();
          _diasCreditoController.text = '0';
          _metodoPago = 'Efectivo';
          _tipoDocumentoFiscal = 'FACTURA';
          _fechaEmision = DateTime.now();
          _renglonesCompra.clear();
          _aplicaRetencionIva = false;
          _aplicaRetencionIslr = false;
          _costoUnitarioBsController.clear();
          _sustraendoIslrBsController.text = '0.00';
        });

        await _cargarDatosIniciales();
        AppEvents.dispararActualizacion();
        _tabController.animateTo(1);

      } else {
        String msg = 'Error al registrar compra';
        try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red.shade700)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error de conexión: $e'), backgroundColor: Colors.red.shade700)
        );
      }
    } finally {
      if (mounted) setState(() => _guardandoCompra = false);
    }
  }

  // =========================================================================
  // PESTAÑA 2: LÓGICA DE HISTORIAL, LIBRO SENIAT, EXPORTACIONES
  // =========================================================================

  void _aplicarFiltroEstadoCompras(String estado) {
    setState(() {
      _filtroEstado = estado;
      if (estado == 'TODAS') {
        _comprasFiltradas = List.from(_comprasOriginales);
      } else {
        _comprasFiltradas = _comprasOriginales.where((c) => c['estado'] == estado).toList();
      }
    });
  }

  void _setFiltroFechaCompras(String tipo) {
    final now = DateTime.now();
    setState(() {
      if (tipo == 'HOY') {
        _fechaInicio = now;
        _fechaFin = now;
        _etiquetaPeriodo = 'Hoy';
      } else if (tipo == 'MES') {
        _fechaInicio = DateTime(now.year, now.month, 1);
        _fechaFin = DateTime(now.year, now.month + 1, 0);
        _etiquetaPeriodo = 'Este Mes';
      }
    });

    if (tipo != 'PERIODO') {
      _cargarCompras();
    } else {
      _seleccionarRangoFechasCompras();
    }
  }

  Future<void> _seleccionarRangoFechasCompras() async {
    final DateTimeRange? rango = await showDateRangePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.input,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Selecciona el rango de fechas para el Libro de Compras',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      initialDateRange: _fechaInicio != null && _fechaFin != null
          ? DateTimeRange(start: _fechaInicio!, end: _fechaFin!)
          : DateTimeRange(start: DateTime.now(), end: DateTime.now()),
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: Colors.blue.shade800,
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
        _fechaFin = rango.end.add(const Duration(hours: 23, minutes: 59, seconds: 59));
        _etiquetaPeriodo = '${DateFormat('dd/MM/yy').format(rango.start)} al ${DateFormat('dd/MM/yy').format(rango.end)}';
      });
      _cargarCompras();
    }
  }

  void _limpiarFiltrosCompras() {
    setState(() {
      _searchComprasController.clear();
      _searchComprasQuery = '';
      _fechaInicio = null;
      _fechaFin = null;
      _etiquetaPeriodo = 'Histórico Completo';
    });
    _cargarCompras();
  }

  Future<void> _descargarExcelCompras() async {
    final FileSaveLocation? ubicacion = await getSaveLocation(
      suggestedName: 'Libro_Compras_SENIAT_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Archivos Excel', extensions: ['xlsx']),
      ],
    );

    if (ubicacion == null) return;

    setState(() => _isLoading = true);

    try {
      String urlStr = 'http://127.0.0.1:3000/api/compras/exportar-excel';
      if (_fechaInicio != null && _fechaFin != null) {
        String inicioStr = "${DateFormat('yyyy-MM-dd').format(_fechaInicio!)}T00:00:00";
        String finStr = "${DateFormat('yyyy-MM-dd').format(_fechaFin!)}T23:59:59";
        urlStr += '?fecha_inicio=$inicioStr&fecha_fin=$finStr';
      }

      final res = await http.get(Uri.parse(urlStr));

      if (res.statusCode == 200) {
        final archivoFisico = File(ubicacion.path);
        await archivoFisico.writeAsBytes(res.bodyBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📊 Libro de Compras exportado a Excel en: ${ubicacion.path}'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        String msg = 'Error generando Excel';
        try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _descargarTxtIva() async {
    final FileSaveLocation? ubicacion = await getSaveLocation(
      suggestedName: 'Retenciones_IVA_${DateFormat('yyyyMM').format(_fechaInicio ?? DateTime.now())}.txt',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Archivos de Texto TXT', extensions: ['txt']),
      ],
    );

    if (ubicacion == null) return;
    setState(() => _isLoading = true);

    try {
      String urlStr = 'http://127.0.0.1:3000/api/compras/exportar-txt-iva';
      if (_fechaInicio != null && _fechaFin != null) {
        String inicioStr = "${DateFormat('yyyy-MM-dd').format(_fechaInicio!)}T00:00:00";
        String finStr = "${DateFormat('yyyy-MM-dd').format(_fechaFin!)}T23:59:59";
        urlStr += '?fecha_inicio=$inicioStr&fecha_fin=$finStr';
      }

      final res = await http.get(Uri.parse(urlStr));
      if (res.statusCode == 200) {
        final archivoFisico = File(ubicacion.path);
        await archivoFisico.writeAsString(res.body);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📄 Archivo TXT de IVA guardado en: ${ubicacion.path}'), backgroundColor: Colors.green.shade700)
          );
        }
      } else {
        String msg = 'Error exportando TXT de IVA';
        try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _descargarXmlIslr() async {
    final FileSaveLocation? ubicacion = await getSaveLocation(
      suggestedName: 'Retenciones_ISLR_${DateFormat('yyyyMM').format(_fechaInicio ?? DateTime.now())}.xml',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Archivos XML', extensions: ['xml']),
      ],
    );

    if (ubicacion == null) return;
    setState(() => _isLoading = true);

    try {
      String urlStr = 'http://127.0.0.1:3000/api/compras/exportar-xml-islr';
      if (_fechaInicio != null && _fechaFin != null) {
        String inicioStr = "${DateFormat('yyyy-MM-dd').format(_fechaInicio!)}T00:00:00";
        String finStr = "${DateFormat('yyyy-MM-dd').format(_fechaFin!)}T23:59:59";
        urlStr += '?fecha_inicio=$inicioStr&fecha_fin=$finStr';
      }

      final res = await http.get(Uri.parse(urlStr));
      if (res.statusCode == 200) {
        final archivoFisico = File(ubicacion.path);
        await archivoFisico.writeAsString(res.body);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📄 Archivo XML de ISLR guardado en: ${ubicacion.path}'), backgroundColor: Colors.green.shade700)
          );
        }
      } else {
        String msg = 'Error exportando XML de ISLR';
        try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generarReportePDFCompras() async {
    final comprasParaPdf = _obtenerComprasFiltradasParaMostrar();

    if (comprasParaPdf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ No hay registros de compras para exportar en el período'))
      );
      return;
    }

    final pdf = pw.Document();

    double totalComprasBs = 0;
    double totalExentoBs = 0;
    double totalBaseBs = 0;
    double totalIvaBs = 0;
    double totalIvaRetBs = 0;
    double totalIslrRetBs = 0;
    double totalNetoBs = 0;
    double totalUsd = 0;

    for (final c in comprasParaPdf) {
      if (c['estado'] != 'ANULADA') {
        final esNC = c['tipo_documento_fiscal'] == 'NOTA_CREDITO';
        final mult = esNC ? -1.0 : 1.0;
        final tasa = (double.tryParse(c['tasa_bcv'].toString()) ?? 1.0);

        final exBs = (double.tryParse(c['monto_exento_bs']?.toString() ?? '') ??
            ((double.tryParse(c['monto_exento_usd']?.toString() ?? '') ?? 0.0) * tasa)) * mult;
        final bBs = (double.tryParse(c['base_imponible_bs']?.toString() ?? '') ??
            ((double.tryParse(c['base_imponible_usd']?.toString() ?? '') ?? 0.0) * tasa)) * mult;
        final iBs = (double.tryParse(c['iva_bs']?.toString() ?? '') ??
            ((double.tryParse(c['iva_usd']?.toString() ?? '') ?? 0.0) * tasa)) * mult;
        final tBs = (double.tryParse(c['total_bs'].toString()) ?? 0.0) * mult;
        final irBs = (double.tryParse(c['iva_retenido_bs'].toString()) ?? 0.0) * mult;
        final isBs = (double.tryParse(c['islr_retenido_bs'].toString()) ?? 0.0) * mult;
        final nBs = (double.tryParse(c['neto_pagar_bs'].toString()) ?? (tBs - irBs - isBs)) * mult;
        final tUsd = (double.tryParse(c['total_usd'].toString()) ?? 0.0) * mult;

        totalExentoBs += exBs;
        totalBaseBs += bBs;
        totalIvaBs += iBs;
        totalComprasBs += tBs;
        totalIvaRetBs += irBs;
        totalIslrRetBs += isBs;
        totalNetoBs += nBs;
        totalUsd += tUsd;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('REPÚBLICA BOLIVARIANA DE VENEZUELA', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    pw.Text('LIBRO DE COMPRAS FISCAL (SENIAT) - ${agenteRetencion['razon_social']}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('RIF: ${agenteRetencion['rif']} | Agente de Retención', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ]
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Emisión: ${DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Período: $_etiquetaPeriodo', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Filtro: $_filtroEstado', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ]
                )
              ]
            )
          ),
          pw.SizedBox(height: 8),

          pw.TableHelper.fromTextArray(
            headers: [
              'N°',
              'Fecha',
              'RIF',
              'Razón Social',
              'Tipo',
              'N° Factura',
              'N° Control',
              'Cond.',
              'Total Bs',
              'Exento Bs',
              'Base 16% Bs',
              'IVA 16% Bs',
              'Ret. IVA Bs',
              'Ret. ISLR Bs',
              'Neto a Pagar Bs'
            ],
            data: comprasParaPdf.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final c = entry.value;
              final esNC = c['tipo_documento_fiscal'] == 'NOTA_CREDITO';
              final esAnulada = c['estado'] == 'ANULADA';
              final mult = esNC ? -1.0 : 1.0;
              final tasa = (double.tryParse(c['tasa_bcv'].toString()) ?? 1.0);

              double exBs = (double.tryParse(c['monto_exento_bs']?.toString() ?? '') ??
                  ((double.tryParse(c['monto_exento_usd']?.toString() ?? '') ?? 0.0) * tasa)) * mult;
              double bBs = (double.tryParse(c['base_imponible_bs']?.toString() ?? '') ??
                  ((double.tryParse(c['base_imponible_usd']?.toString() ?? '') ?? 0.0) * tasa)) * mult;
              double iBs = (double.tryParse(c['iva_bs']?.toString() ?? '') ??
                  ((double.tryParse(c['iva_usd']?.toString() ?? '') ?? 0.0) * tasa)) * mult;
              double tBs = (double.tryParse(c['total_bs'].toString()) ?? 0.0) * mult;
              double irBs = (double.tryParse(c['iva_retenido_bs'].toString()) ?? 0.0) * mult;
              double isBs = (double.tryParse(c['islr_retenido_bs'].toString()) ?? 0.0) * mult;
              double nBs = (double.tryParse(c['neto_pagar_bs'].toString()) ?? (tBs - irBs - isBs)) * mult;

              if (esAnulada) {
                exBs = 0; bBs = 0; iBs = 0; tBs = 0; irBs = 0; isBs = 0; nBs = 0;
              }

              final prov = c['Proveedor'];
              final rif = prov != null ? '${prov['tipo_documento']}-${prov['numero_documento']}' : 'N/A';
              final nombre = prov != null ? prov['nombre'] : 'Desconocido';
              final diasCred = c['dias_credito'] ?? 0;
              final cond = diasCred > 0 ? 'Créd.' : 'Cont.';

              String tipoDocAbrev = 'FAC';
              if (c['tipo_documento_fiscal'] == 'NOTA_CREDITO') tipoDocAbrev = 'NC';
              if (c['tipo_documento_fiscal'] == 'NOTA_DEBITO') tipoDocAbrev = 'ND';

              return [
                index.toString(),
                c['fecha_emision'] ?? '',
                rif,
                nombre.length > 18 ? '${nombre.substring(0, 16)}..' : nombre,
                tipoDocAbrev,
                c['numero_factura'] ?? '',
                c['numero_control'] ?? '',
                cond,
                tBs.toStringAsFixed(2),
                exBs.toStringAsFixed(2),
                bBs.toStringAsFixed(2),
                iBs.toStringAsFixed(2),
                irBs.toStringAsFixed(2),
                isBs.toStringAsFixed(2),
                nBs.toStringAsFixed(2)
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: pw.Alignment.center,
            cellAlignments: {
              3: pw.Alignment.centerLeft,
              8: pw.Alignment.centerRight,
              9: pw.Alignment.centerRight,
              10: pw.Alignment.centerRight,
              11: pw.Alignment.centerRight,
              12: pw.Alignment.centerRight,
              13: pw.Alignment.centerRight,
              14: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 10),

          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTALES FISCALES:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.blue900)),
                pw.Text('Exento: Bs ${totalExentoBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text('Base 16%: Bs ${totalBaseBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text('IVA 16%: Bs ${totalIvaBs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5)),
                pw.Text('Total Bs: Bs ${totalComprasBs.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text('Ret. IVA: Bs ${totalIvaRetBs.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange900)),
                pw.Text('Ret. ISLR: Bs ${totalIslrRetBs.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                pw.Text('Neto a Pagar: Bs ${totalNetoBs.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                pw.Text('Total (\$): \$${totalUsd.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              ]
            )
          )
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Libro_Compras_SENIAT_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf'
    );
  }

  // =========================================================================
  // IMPRESIÓN OFICIAL DE COMPROBANTES DE RETENCIÓN (PDF)
  // =========================================================================
  String _formatearMontoBs(double monto) {
    final partes = monto.toStringAsFixed(2).split('.');
    final entero = partes[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => '.',
    );
    return '$entero,${partes[1]}';
  }

  pw.Widget _buildCellComprobante(
    String texto, {
    bool isHeader = false,
    bool isBold = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
    double? fontSize,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 3.5),
      alignment: alignment,
      child: pw.Text(
        texto,
        textAlign: alignment == pw.Alignment.centerRight
            ? pw.TextAlign.right
            : alignment == pw.Alignment.center
                ? pw.TextAlign.center
                : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: fontSize ?? (isHeader ? 7.2 : 7.5),
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Future<void> _imprimirComprobanteRetIva(Map<String, dynamic> compra) async {
    final pdf = pw.Document();
    final prov = compra['Proveedor'];
    final tasa = double.tryParse(compra['tasa_bcv'].toString()) ?? 1.0;
    final fechaDoc = DateTime.tryParse(compra['fecha_emision']?.toString().split('T')[0] ?? '') ?? DateTime.now();

    final baseBs = double.tryParse(compra['base_imponible_bs']?.toString() ?? '') ??
        ((double.tryParse(compra['base_imponible_usd']?.toString() ?? '') ?? 0.0) * tasa);
    final exentoBs = double.tryParse(compra['monto_exento_bs']?.toString() ?? '') ??
        ((double.tryParse(compra['monto_exento_usd']?.toString() ?? '') ?? 0.0) * tasa);
    final ivaBs = double.tryParse(compra['iva_bs']?.toString() ?? '') ??
        ((double.tryParse(compra['iva_usd']?.toString() ?? '') ?? 0.0) * tasa);
    final calcTotalBs = double.tryParse(compra['total_bs']?.toString() ?? '') ?? 0.0;
    final totalBs = calcTotalBs > 0 ? calcTotalBs : (baseBs + exentoBs + ivaBs);
    final ivaRetBs = double.tryParse(compra['iva_retenido_bs'].toString()) ?? 0.0;
    final totalNetoPagado = totalBs - ivaRetBs;

    // Formateo de fecha del documento
    String fechaDocStr = DateFormat('dd/MM/yyyy').format(fechaDoc);

    // Tipo de Transacción
    final tipoDoc = (compra['tipo_documento_fiscal'] ?? 'FACTURA').toString().toUpperCase();
    String tipoTransaccion = '01- Reg';
    if (tipoDoc.contains('DEBITO') || tipoDoc == '02' || tipoDoc == 'ND') {
      tipoTransaccion = '02- Comp';
    } else if (tipoDoc.contains('CREDITO') || tipoDoc == '03' || tipoDoc == 'NC') {
      tipoTransaccion = '03- Anul';
    }

    final numFactura = (compra['numero_factura'] ?? '').toString();
    final numControl = (compra['numero_control'] ?? '').toString();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Membrete Agente de Retención (Conservado intacto)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      agenteRetencion['razon_social']!,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                    ),
                    pw.Text('RIF: ${agenteRetencion['rif']}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.SizedBox(
                      width: 450,
                      child: pw.Text('Dirección: ${agenteRetencion['direccion']}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    )
                  ]
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue900, width: 1.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    color: PdfColors.blue50
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('COMPROBANTE DE RETENCIÓN DE I.V.A.', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.SizedBox(height: 4),
                      pw.Text('N° Comprobante: ${compra['comprobante_ret_iva'] ?? 'S/N'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      pw.SizedBox(height: 2),
                      pw.Text('Fecha Emisión: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Período Fiscal: ${fechaDoc.year} / ${fechaDoc.month.toString().padLeft(2, '0')}', style: const pw.TextStyle(fontSize: 9)),
                    ]
                  )
                )
              ]
            ),
            pw.SizedBox(height: 10),
            pw.Text('(Ley IVA - Art. 11 / Providencia Administrativa SENIAT N° SNAT/2015/0049)', style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            pw.SizedBox(height: 12),

            // Cuadro Sujeto Retenido / Beneficiario (Conservado intacto)
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                color: PdfColors.grey100
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('NOMBRE O RAZÓN SOCIAL DEL SUJETO RETENIDO:', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                        pw.SizedBox(height: 2),
                        pw.Text(prov != null ? prov['nombre'] : 'DESCONOCIDO', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      ]
                    )
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('REGISTRO DE INFORMACIÓN FISCAL (RIF):', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                        pw.SizedBox(height: 2),
                        pw.Text(prov != null ? '${prov['tipo_documento']}-${prov['numero_documento']}' : 'N/A', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      ]
                    )
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('DIRECCIÓN FISCAL:', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                        pw.SizedBox(height: 2),
                        pw.Text(prov != null && prov['direccion'] != null ? prov['direccion'] : 'N/A', style: const pw.TextStyle(fontSize: 9)),
                      ]
                    )
                  ),
                ],
              )
            ),
            pw.SizedBox(height: 14),

            // Super-Encabezado Superior (agrupado sobre columnas 6, 7, 8 y 9)
            pw.Row(
              children: [
                pw.SizedBox(width: 445), // columnas 0..5 (60 + 90 + 75 + 60 + 80 + 80)
                pw.Container(
                  width: 201, // columnas 6..8 (78 + 45 + 78)
                  height: 18,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.black, width: 0.5),
                      left: pw.BorderSide(color: PdfColors.black, width: 0.5),
                      right: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    ),
                  ),
                  child: pw.Text(
                    'Compras Internas o IMPORTACIONES',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Container(
                  width: 82, // columna 9
                  height: 18,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                    border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.black, width: 0.5),
                      right: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    ),
                  ),
                ),
              ],
            ),

            // Tabla Principal de Retención de I.V.A. (10 Columnas)
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FixedColumnWidth(60), // Fecha del Documento
                1: pw.FixedColumnWidth(90), // Número del Documento
                2: pw.FixedColumnWidth(75), // Núm. Control del Documento
                3: pw.FixedColumnWidth(60), // Tipo de Transacción
                4: pw.FixedColumnWidth(80), // Total compras Incluyendo IVA
                5: pw.FixedColumnWidth(80), // Compras sin Derecho a Crédito IVA
                6: pw.FixedColumnWidth(78), // Base Imponible
                7: pw.FixedColumnWidth(45), // Alícuota %
                8: pw.FixedColumnWidth(78), // Impuesto IVA
                9: pw.FixedColumnWidth(82), // IVA Retenido
              },
              children: [
                // Cabecera Principal
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _buildCellComprobante('Fecha del\nDocumento', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Número del Documento', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Núm. Control del\nDocumento', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Tipo de\nTransación', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Total compras\nIncluyendo IVA', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Compras sin Derecho a\nCrédito IVA', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Base Imponible', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Alicuota\n%', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Impuesto IVA', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('IVA Retenido', isHeader: true, alignment: pw.Alignment.center),
                  ],
                ),
                // Fila de Datos
                pw.TableRow(
                  children: [
                    _buildCellComprobante(fechaDocStr, alignment: pw.Alignment.center),
                    _buildCellComprobante(numFactura, alignment: pw.Alignment.center),
                    _buildCellComprobante(numControl, alignment: pw.Alignment.center),
                    _buildCellComprobante(tipoTransaccion, alignment: pw.Alignment.center),
                    _buildCellComprobante(_formatearMontoBs(totalBs), alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(_formatearMontoBs(exentoBs), alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(_formatearMontoBs(baseBs), alignment: pw.Alignment.centerRight),
                    _buildCellComprobante('16%', alignment: pw.Alignment.center),
                    _buildCellComprobante(_formatearMontoBs(ivaBs), alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(_formatearMontoBs(ivaRetBs), alignment: pw.Alignment.centerRight),
                  ],
                ),
                // Fila de Totales Integrada
                pw.TableRow(
                  children: [
                    _buildCellComprobante('', alignment: pw.Alignment.center),
                    _buildCellComprobante('', alignment: pw.Alignment.center),
                    _buildCellComprobante('', alignment: pw.Alignment.center),
                    _buildCellComprobante('Total', isBold: true, alignment: pw.Alignment.center),
                    _buildCellComprobante(_formatearMontoBs(totalBs), isBold: true, alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(_formatearMontoBs(exentoBs), isBold: true, alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(_formatearMontoBs(baseBs), isBold: true, alignment: pw.Alignment.centerRight),
                    _buildCellComprobante('', alignment: pw.Alignment.center),
                    _buildCellComprobante(_formatearMontoBs(ivaBs), isBold: true, alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(_formatearMontoBs(ivaRetBs), isBold: true, alignment: pw.Alignment.centerRight),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Recuadro Inferior "TOTAL PAGADO" (alineado a la derecha, ancho de cols 6..9)
            pw.Row(
              children: [
                pw.SizedBox(width: 445), // columnas 0..5
                pw.Container(
                  width: 283, // columnas 6..9 (78 + 45 + 78 + 82)
                  height: 22,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey300,
                    border: pw.Border.all(color: PdfColors.black, width: 0.5),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL PAGADO',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                      ),
                      pw.Text(
                        _formatearMontoBs(totalNetoPagado),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Spacer(),

            // Recuadros de Firma y Sello
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Container(
                  width: 300,
                  height: 80,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('POR EL AGENTE DE RETENCIÓN', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Firma Autorizada y Sello', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))
                    ]
                  )
                ),
                pw.Container(
                  width: 300,
                  height: 80,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('POR EL PROVEEDOR (SUJETO RETENIDO)', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Firma, Sello y Fecha de Recepción', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))
                    ]
                  )
                ),
              ],
            )
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Comprobante_Ret_IVA_${compra['comprobante_ret_iva'] ?? compra['numero_factura']}.pdf'
    );
  }

  Future<void> _imprimirComprobanteRetIslr(Map<String, dynamic> compra) async {
    final pdf = pw.Document();
    final prov = compra['Proveedor'];
    final tasa = double.tryParse(compra['tasa_bcv'].toString()) ?? 1.0;
    final fEmision = DateTime.tryParse(compra['fecha_emision']?.toString().split('T')[0] ?? '') ?? DateTime.now();
    final fRecepcion = DateTime.tryParse(compra['fecha_recepcion']?.toString().split('T')[0] ?? '');
    final fRetencion = DateTime.tryParse(compra['createdAt']?.toString().split('T')[0] ?? '') ?? DateTime.now();

    final baseBs = double.tryParse(compra['base_imponible_bs']?.toString() ?? '') ??
        ((double.tryParse(compra['base_imponible_usd']?.toString() ?? '') ?? 0.0) * tasa);
    final islrRetBs = double.tryParse(compra['islr_retenido_bs'].toString()) ?? 0.0;
    final porcRet = compra['porcentaje_ret_islr'] ?? 0;

    // Fechas formateadas
    final fechaFacturaStr = DateFormat('dd/MM/yyyy').format(fEmision);
    final fechaPagoStr = DateFormat('dd/MM/yyyy').format(fRecepcion ?? fEmision);
    final fechaRetencionStr = DateFormat('dd/MM/yyyy').format(fRecepcion ?? fRetencion);

    // Tipos de documento
    final tipoDoc = (compra['tipo_documento_fiscal'] ?? 'FACTURA').toString().toUpperCase();
    final esFactura = tipoDoc == 'FACTURA' || tipoDoc == 'FAC';
    final esND = tipoDoc.contains('DEBITO') || tipoDoc == 'ND';
    final esNC = tipoDoc.contains('CREDITO') || tipoDoc == 'NC';

    final numFactura = esFactura ? (compra['numero_factura'] ?? '') : '-';
    final numControl = (compra['numero_control'] ?? '').toString();
    final numND = esND ? (compra['numero_factura'] ?? '-') : '-';
    final numNC = esNC ? (compra['numero_factura'] ?? '-') : '-';

    // Tarifa
    String tarifaRetStr = '$porcRet%';
    if (porcRet is num) {
      if (porcRet == porcRet.toInt()) {
        tarifaRetStr = '${porcRet.toInt()}%';
      } else {
        tarifaRetStr = '${porcRet.toStringAsFixed(2)}%';
      }
    }

    // Concepto
    final conceptoIslr = (compra['concepto_islr'] != null && compra['concepto_islr'].toString().isNotEmpty)
        ? compra['concepto_islr'].toString()
        : 'Ejecución de obras y prestación de servicios en Venezuela pagadas a:';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Membrete Agente de Retención (Conservado intacto)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      agenteRetencion['razon_social']!,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                    ),
                    pw.Text('RIF: ${agenteRetencion['rif']}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.SizedBox(
                      width: 450,
                      child: pw.Text('Dirección: ${agenteRetencion['direccion']}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    )
                  ]
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue900, width: 1.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    color: PdfColors.blue50
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('COMPROBANTE DE RETENCIÓN DE I.S.L.R.', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.SizedBox(height: 4),
                      pw.Text('N°: ${compra['comprobante_ret_islr'] ?? 'S/N'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      pw.SizedBox(height: 2),
                      pw.Text('Fecha: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Período: ${fEmision.year} / ${fEmision.month.toString().padLeft(2, '0')}', style: const pw.TextStyle(fontSize: 9)),
                    ]
                  )
                )
              ]
            ),
            pw.SizedBox(height: 8),
            pw.Text('(Decreto N° 1808 / Reglamento de Retenciones de la Ley de Impuesto Sobre la Renta)', style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            pw.SizedBox(height: 12),

            // Beneficiario / Sujeto Retenido (Conservado intacto)
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                color: PdfColors.grey100
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BENEFICIARIO DEL PAGO (SUJETO RETENIDO):', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Nombre: ${prov != null ? prov['nombre'] : 'DESCONOCIDO'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('RIF: ${prov != null ? '${prov['tipo_documento']}-${prov['numero_documento']}' : 'N/A'}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ]
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Dirección: ${prov != null && prov['direccion'] != null ? prov['direccion'] : 'N/A'}', style: const pw.TextStyle(fontSize: 9)),
                ],
              )
            ),
            pw.SizedBox(height: 14),

            // Tabla Principal de Retención de I.S.L.R. (11 Columnas)
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FixedColumnWidth(54),  // Fecha de la Factura
                1: pw.FixedColumnWidth(88),  // Nro. Factura
                2: pw.FixedColumnWidth(66),  // Nro. Control
                3: pw.FixedColumnWidth(50),  // Nro. Nota de Débito
                4: pw.FixedColumnWidth(50),  // Nro. Nota de Crédito
                5: pw.FixedColumnWidth(54),  // Fecha Pago de Factura
                6: pw.FixedColumnWidth(58),  // Fecha de la Retención
                7: pw.FixedColumnWidth(66),  // Base Imponible
                8: pw.FixedColumnWidth(44),  // Tarifa de retención
                9: pw.FixedColumnWidth(138), // Tipo de Actividad
                10: pw.FixedColumnWidth(60), // Impuesto Retenido
              },
              children: [
                // Cabecera en gris claro
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _buildCellComprobante('Fecha de la\nFactura', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Nro. Factura', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Nro. Control', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Nro. Nota de\nDébito', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Nro. Nota de\nCrédito', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Fecha Pago de\nFactura', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Fecha de la\nRetención', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Base\nImponible', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Tarifa de\nretención', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Tipo de Actividad', isHeader: true, alignment: pw.Alignment.center),
                    _buildCellComprobante('Impuesto\nRetenido', isHeader: true, alignment: pw.Alignment.center),
                  ],
                ),
                // Fila de Datos
                pw.TableRow(
                  children: [
                    _buildCellComprobante(fechaFacturaStr, alignment: pw.Alignment.center),
                    _buildCellComprobante(numFactura, alignment: pw.Alignment.center),
                    _buildCellComprobante(numControl, alignment: pw.Alignment.center),
                    _buildCellComprobante(numND, alignment: pw.Alignment.center),
                    _buildCellComprobante(numNC, alignment: pw.Alignment.center),
                    _buildCellComprobante(fechaPagoStr, alignment: pw.Alignment.center),
                    _buildCellComprobante(fechaRetencionStr, alignment: pw.Alignment.center),
                    _buildCellComprobante(_formatearMontoBs(baseBs), alignment: pw.Alignment.centerRight),
                    _buildCellComprobante(tarifaRetStr, alignment: pw.Alignment.center),
                    _buildCellComprobante(conceptoIslr, alignment: pw.Alignment.centerLeft),
                    _buildCellComprobante(_formatearMontoBs(islrRetBs), alignment: pw.Alignment.centerRight),
                  ],
                ),
              ],
            ),

            // Barra de "Total General" Inferior (desde columna 6 hasta el borde derecho)
            pw.Row(
              children: [
                pw.SizedBox(width: 362), // columnas 0..5 (54 + 88 + 66 + 50 + 50 + 54 = 362)
                pw.Container(
                  width: 366, // columnas 6..10 (58 + 66 + 44 + 138 + 60 = 366)
                  height: 20,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                    border: pw.Border(
                      left: pw.BorderSide(color: PdfColors.black, width: 0.5),
                      right: pw.BorderSide(color: PdfColors.black, width: 0.5),
                      bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
                    ),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 58,
                        alignment: pw.Alignment.centerLeft,
                        padding: const pw.EdgeInsets.only(left: 4),
                        child: pw.Text(
                          'Total General:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
                        ),
                      ),
                      pw.Container(
                        width: 66,
                        alignment: pw.Alignment.centerRight,
                        padding: const pw.EdgeInsets.only(right: 3),
                        child: pw.Text(
                          _formatearMontoBs(baseBs),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
                        ),
                      ),
                      pw.SizedBox(width: 44 + 138), // columnas 8 y 9
                      pw.Container(
                        width: 60,
                        alignment: pw.Alignment.centerRight,
                        padding: const pw.EdgeInsets.only(right: 3),
                        child: pw.Text(
                          _formatearMontoBs(islrRetBs),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Spacer(),

            // Firmas
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Container(
                  width: 300,
                  height: 80,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('POR EL AGENTE DE RETENCIÓN', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Firma y Sello (AGUA GRAND, C.A.)', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))
                    ]
                  )
                ),
                pw.Container(
                  width: 300,
                  height: 80,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600)),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('BENEFICIARIO DEL PAGO', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Firma, Sello y Fecha', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))
                    ]
                  )
                ),
              ],
            )
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Comprobante_Ret_ISLR_${compra['comprobante_ret_islr'] ?? compra['numero_factura']}.pdf'
    );
  }

  List<dynamic> _obtenerComprasFiltradasParaMostrar() {
    return _comprasFiltradas.where((c) {
      if (_searchComprasQuery.isEmpty) return true;
      final numFac = (c['numero_factura'] ?? '').toString().toLowerCase();
      final numCtrl = (c['numero_control'] ?? '').toString().toLowerCase();
      final prov = c['Proveedor'];
      final provNombre = prov != null ? (prov['nombre'] ?? '').toString().toLowerCase() : '';
      final provDoc = prov != null ? '${prov['tipo_documento']}${prov['numero_documento']}'.toLowerCase() : '';

      return numFac.contains(_searchComprasQuery) ||
             numCtrl.contains(_searchComprasQuery) ||
             provNombre.contains(_searchComprasQuery) ||
             provDoc.contains(_searchComprasQuery);
    }).toList();
  }

  void _verDetallesCompra(Map<String, dynamic> compra) {
    final detalles = compra['DetalleCompras'] as List? ?? [];
    final prov = compra['Proveedor'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              compra['tipo_documento_fiscal'] == 'FACTURA' ? Icons.receipt : Icons.assignment_return,
              color: Colors.blue
            ),
            const SizedBox(width: 8),
            Text('${compra['tipo_documento_fiscal']}: ${compra['numero_factura']}'),
          ],
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('N° Control: ${compra['numero_control'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('Fecha Emisión: ${compra['fecha_emision'] ?? '-'}'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Proveedor: ${prov != null ? prov['nombre'] : 'Desconocido'} (${prov != null ? '${prov['tipo_documento']}-${prov['numero_documento']}' : ''})'),
                          Text('Tasa BCV: ${compra['tasa_bcv']} Bs/\$'),
                        ],
                      ),
                      if (compra['factura_afectada'] != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Factura Afectada: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            Text('${compra['factura_afectada']}'),
                          ],
                        )
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Condición: ${(compra['dias_credito'] ?? 0) > 0 ? 'Crédito (${compra['dias_credito']} días)' : 'Contado'}'),
                          Text('Estado: ${compra['estado']}', style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: compra['estado'] == 'PAGADA' ? Colors.green : (compra['estado'] == 'PENDIENTE' ? Colors.orange : Colors.red)
                          )),
                        ],
                      ),
                      if (compra['aplica_retencion_iva'] == true || compra['aplica_retencion_islr'] == true) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (compra['aplica_retencion_iva'] == true)
                              Text('Ret. IVA: Bs ${compra['iva_retenido_bs']} (${compra['comprobante_ret_iva'] ?? ''})', style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                            if (compra['aplica_retencion_islr'] == true)
                              Text('Ret. ISLR: Bs ${compra['islr_retenido_bs']} (${compra['comprobante_ret_islr'] ?? ''})', style: const TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.bold)),
                          ],
                        )
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Renglones de la Compra / Ajuste:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),

                detalles.isEmpty
                    ? const Padding(padding: EdgeInsets.all(16.0), child: Text('No hay renglones registrados'))
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: detalles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = detalles[index];
                          final prod = item['Producto'];
                          final desc = prod != null ? prod['nombre'] : item['descripcion'];
                          final cant = item['cantidad'] ?? 1;
                          final tasa = double.tryParse(compra['tasa_bcv'].toString()) ?? 1.0;
                          final cUsd = double.tryParse(item['costo_unitario_usd']?.toString() ?? '') ?? 0.0;
                          final cBs = double.tryParse(item['costo_unitario_bs']?.toString() ?? '') ?? (cUsd * tasa);
                          final subUsd = double.tryParse(item['subtotal_usd']?.toString() ?? '') ?? 0.0;
                          final subBs = double.tryParse(item['subtotal_bs']?.toString() ?? '') ?? (subUsd * tasa);
                          final llevaIva = item['aplica_iva'] == true;

                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: llevaIva ? Colors.blue.shade100 : Colors.green.shade100,
                              child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(desc ?? 'Item sin descripción', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('$cant unid. x Bs ${_formatearMontoBs(cBs)} (Ref: \$${cUsd.toStringAsFixed(2)}) | ${llevaIva ? 'IVA 16%' : 'Exento'}'),
                            trailing: Text('Bs ${_formatearMontoBs(subBs)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          );
                        },
                      ),

                Builder(
                  builder: (context) {
                    final tasaDoc = double.tryParse(compra['tasa_bcv'].toString()) ?? 1.0;
                    final exentoBs = double.tryParse(compra['monto_exento_bs']?.toString() ?? '') ??
                        ((double.tryParse(compra['monto_exento_usd']?.toString() ?? '') ?? 0.0) * tasaDoc);
                    final baseBs = double.tryParse(compra['base_imponible_bs']?.toString() ?? '') ??
                        ((double.tryParse(compra['base_imponible_usd']?.toString() ?? '') ?? 0.0) * tasaDoc);
                    final ivaBs = double.tryParse(compra['iva_bs']?.toString() ?? '') ??
                        ((double.tryParse(compra['iva_usd']?.toString() ?? '') ?? 0.0) * tasaDoc);
                    final exentoUsd = double.tryParse(compra['monto_exento_usd']?.toString() ?? '') ?? (exentoBs / tasaDoc);
                    final baseUsd = double.tryParse(compra['base_imponible_usd']?.toString() ?? '') ?? (baseBs / tasaDoc);
                    final ivaUsd = double.tryParse(compra['iva_usd']?.toString() ?? '') ?? (ivaBs / tasaDoc);
                    final totalBs = double.tryParse(compra['total_bs']?.toString() ?? '') ?? (baseBs + exentoBs + ivaBs);
                    final totalUsd = double.tryParse(compra['total_usd']?.toString() ?? '') ?? (totalBs / tasaDoc);
                    final netoBs = double.tryParse((compra['neto_pagar_bs'] ?? compra['total_bs']).toString()) ?? 0.0;
                    final netoUsd = double.tryParse((compra['neto_pagar_usd'] ?? compra['total_usd']).toString()) ?? (netoBs / tasaDoc);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Exento: Bs ${_formatearMontoBs(exentoBs)} (Ref: \$${exentoUsd.toStringAsFixed(2)})'),
                            Text('Base 16%: Bs ${_formatearMontoBs(baseBs)} (Ref: \$${baseUsd.toStringAsFixed(2)})'),
                            Text('IVA 16%: Bs ${_formatearMontoBs(ivaBs)} (Ref: \$${ivaUsd.toStringAsFixed(2)})'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Factura: Bs ${_formatearMontoBs(totalBs)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('(Ref: \$${totalUsd.toStringAsFixed(2)})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('NETO A PAGAR: Bs ${_formatearMontoBs(netoBs)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green.shade900)),
                              Text('(Ref: \$${netoUsd.toStringAsFixed(2)})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900)),
                            ],
                          ),
                        )
                      ],
                    );
                  },
                )
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))
        ],
      )
    );
  }

  void _mostrarDialogoPagarCompra(Map<String, dynamic> compra) {
    String metodo = 'Transferencia';
    final netoUsd = compra['neto_pagar_usd'] ?? compra['total_usd'];
    final netoBs = compra['neto_pagar_bs'] ?? compra['total_bs'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          return AlertDialog(
            title: Text('Pagar Cuenta Pendiente - ${compra['numero_factura']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Proveedor: ${compra['Proveedor'] != null ? compra['Proveedor']['nombre'] : '-'}'),
                const SizedBox(height: 8),
                Text('Neto Real a pagar: \$$netoUsd (Bs $netoBs)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: metodo,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Método de Pago Efectuado', border: OutlineInputBorder()),
                  items: ['Transferencia', 'Pago Móvil', 'Efectivo', 'Zelle', 'Divisa'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => setStateModal(() => metodo = val!),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _procesarPagoCompra(compra['id'], metodo);
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Confirmar Pago'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              )
            ],
          );
        }
      )
    );
  }

  Future<void> _procesarPagoCompra(int id, String metodo) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/compras/$id/pagar'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"metodo_pago": metodo})
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Pago de compra registrado con éxito'), backgroundColor: Colors.green)
          );
        }
        await _cargarDatosIniciales();
        AppEvents.dispararActualizacion();
      } else {
        String msg = 'Error procesando pago';
        try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarDialogoAnularCompra(Map<String, dynamic> compra) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Anular ${compra['tipo_documento_fiscal']}: ${compra['numero_factura']}'),
        content: const Text(
          '¿Está seguro de anular este documento de compra?\n\n'
          '⚠️ Al anular:\n'
          '- Si fue una FACTURA, el stock de los productos se RESTARÁ automáticamente del inventario.\n'
          '- Si fue una NOTA DE CRÉDITO, el stock devuelto se SUMARÁ de vuelta al almacén.\n'
          '- El documento quedará registrado como ANULADO en el Libro de Compras SENIAT.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _anularCompra(compra['id']);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sí, Anular y Revertir Stock'),
          )
        ],
      )
    );
  }

  Future<void> _anularCompra(int id) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.put(Uri.parse('http://127.0.0.1:3000/api/compras/anular/$id'));

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Compra anulada e inventario revertido correctamente'), backgroundColor: Colors.green)
          );
        }
        await _cargarDatosIniciales();
        AppEvents.dispararActualizacion();
      } else {
        String msg = 'Error anulando compra';
        try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =========================================================================
  // PESTAÑA 3: LÓGICA DE PROVEEDORES
  // =========================================================================

  void _filtrarProveedoresTab(String query) {
    if (query.trim().isEmpty) {
      setState(() => _proveedoresTabFiltrados = List.from(_proveedores));
    } else {
      final q = query.toLowerCase();
      setState(() {
        _proveedoresTabFiltrados = _proveedores.where((p) {
          final nom = (p['nombre'] ?? '').toString().toLowerCase();
          final doc = '${p['tipo_documento']}${p['numero_documento']}'.toLowerCase();
          return nom.contains(q) || doc.contains(q);
        }).toList();
      });
    }
  }

  void _mostrarDialogoEditarProveedor(Map<String, dynamic> prov) {
    String tipoDoc = prov['tipo_documento'] ?? 'J';
    int retIvaVal = prov['porcentaje_retencion_iva'] ?? 75;
    final TextEditingController numDocCtrl = TextEditingController(text: prov['numero_documento'] ?? '');
    final TextEditingController nombreCtrl = TextEditingController(text: prov['nombre'] ?? '');
    final TextEditingController tlfCtrl = TextEditingController(text: prov['telefono'] ?? '');
    final TextEditingController correoCtrl = TextEditingController(text: prov['correo'] ?? '');
    final TextEditingController dirCtrl = TextEditingController(text: prov['direccion'] ?? '');
    final TextEditingController diasCredCtrl = TextEditingController(text: (prov['dias_credito_habitual'] ?? 0).toString());
    final TextEditingController retIslrCtrl = TextEditingController(text: (prov['porcentaje_retencion_islr'] ?? '0.00').toString());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setStateModal) {
          return AlertDialog(
            title: const Text('Editar Proveedor', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 85,
                          child: DropdownButtonFormField<String>(
                            initialValue: tipoDoc,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                            items: ['J', 'G', 'V', 'E'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) => setStateModal(() => tipoDoc = val!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: numDocCtrl,
                            decoration: const InputDecoration(labelText: 'N° Documento / RIF *', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Razón Social / Nombre Completo *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: tlfCtrl, decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: correoCtrl, decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: dirCtrl, decoration: const InputDecoration(labelText: 'Dirección Fiscal', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: diasCredCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días Crédito', border: OutlineInputBorder()))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: retIvaVal,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '% Ret. IVA *', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('0% (No aplica)')),
                              DropdownMenuItem(value: 75, child: Text('75% (Ordinario)')),
                              DropdownMenuItem(value: 100, child: Text('100% (Especial)')),
                            ],
                            onChanged: (val) => setStateModal(() => retIvaVal = val!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: retIslrCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '% Ret. ISLR', suffixText: '%', border: OutlineInputBorder()))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final body = jsonEncode({
                      "tipo_documento": tipoDoc,
                      "numero_documento": numDocCtrl.text.trim(),
                      "nombre": nombreCtrl.text.trim(),
                      "telefono": tlfCtrl.text.trim(),
                      "correo": correoCtrl.text.trim(),
                      "direccion": dirCtrl.text.trim(),
                      "dias_credito_habitual": int.tryParse(diasCredCtrl.text.trim()) ?? 0,
                      "porcentaje_retencion_iva": retIvaVal,
                      "porcentaje_retencion_islr": double.tryParse(retIslrCtrl.text.trim()) ?? 0.0
                    });

                    final res = await http.put(
                      Uri.parse('http://127.0.0.1:3000/api/proveedores/${prov['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: body
                    );

                    if (res.statusCode == 200) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _cargarDatosIniciales();
                      AppEvents.dispararActualizacion();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Proveedor actualizado'), backgroundColor: Colors.green));
                      }
                    } else {
                      String msg = 'Error actualizando proveedor';
                      try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('Guardar Cambios'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              )
            ],
          );
        }
      )
    );
  }

  void _eliminarProveedor(Map<String, dynamic> prov) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar Proveedor: ${prov['nombre']}'),
        content: const Text('¿Está seguro de eliminar este proveedor? Si tiene compras históricas se conservará el registro sin saldo pendiente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (ctx.mounted) Navigator.pop(ctx);
              try {
                final res = await http.delete(Uri.parse('http://127.0.0.1:3000/api/proveedores/${prov['id']}'));
                if (res.statusCode == 200) {
                  await _cargarDatosIniciales();
                  AppEvents.dispararActualizacion();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Proveedor eliminado'), backgroundColor: Colors.green));
                  }
                } else {
                  String msg = 'No se pudo eliminar el proveedor';
                  try { msg = jsonDecode(res.body)['mensaje'] ?? msg; } catch (_) {}
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sí, Eliminar'),
          )
        ],
      )
    );
  }

  // =========================================================================
  // CONSTRUCCIÓN VISUAL PRINCIPAL (WIDGET BUILD)
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Módulo de Compras, Proveedores y Retenciones', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey.shade700,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Registrar Compra / Nota'),
            Tab(icon: Icon(Icons.auto_stories), text: 'Libro de Compras y CxP'),
            Tab(icon: Icon(Icons.business_outlined), text: 'Directorio de Proveedores'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _construirPestanaRegistrarCompra(),
                _construirPestanaLibroCompras(),
                _construirPestanaProveedores(),
              ],
            ),
    );
  }

  // =========================================================================
  // VISTA PESTAÑA 1: FORMULARIO DE REGISTRO
  // =========================================================================
  Widget _construirPestanaRegistrarCompra() {
    final totales = _calcularTotalesCompra();
    final diasCred = int.tryParse(_diasCreditoController.text) ?? 0;
    final fechaVencimiento = _fechaEmision.add(Duration(days: diasCred));

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. CABECERA: SELECCIÓN DE PROVEEDOR Y DATOS FISCALES (FULL WIDTH)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.business, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('1. Datos del Proveedor y Documento Fiscal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Buscador Inteligente de Proveedor
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchProveedorController,
                              decoration: InputDecoration(
                                labelText: 'Buscar Proveedor (RIF o Razón Social)',
                                hintText: 'Ej: J-12345678 o Distribuidora Polar',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _proveedorSeleccionado != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _proveedorSeleccionado = null;
                                            _searchProveedorController.clear();
                                          });
                                        },
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.arrow_forward, color: Colors.blue),
                                        onPressed: _buscarProveedorInteligente,
                                      ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _buscarProveedorInteligente(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => _mostrarDialogoRegistroRapidoProveedor(_searchProveedorController.text),
                            icon: const Icon(Icons.person_add),
                            label: const Text('+ Nuevo Proveedor'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                          ),
                        ],
                      ),

                      if (_proveedorSeleccionado != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200)
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Proveedor: ${_proveedorSeleccionado!['nombre']} | RIF: ${_proveedorSeleccionado!['tipo_documento']}-${_proveedorSeleccionado!['numero_documento']} | Ret. IVA: ${_proveedorSeleccionado!['porcentaje_retencion_iva'] ?? 75}% | Ret. ISLR: ${_proveedorSeleccionado!['porcentaje_retencion_islr'] ?? 0}% | Crédito: ${_proveedorSeleccionado!['dias_credito_habitual'] ?? 0} d',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Campos Fiscales en Fila Completa (FULL-WIDTH con Expanded)
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(_tipoDocumentoFiscal),
                              initialValue: _tipoDocumentoFiscal,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Tipo Documento *',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'FACTURA', child: Text('FACTURA', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'NOTA_CREDITO', child: Text('NOTA CRÉDITO (NC)', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'NOTA_DEBITO', child: Text('NOTA DÉBITO (ND)', overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (val) {
                                setState(() => _tipoDocumentoFiscal = val!);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _numeroFacturaController,
                              decoration: const InputDecoration(labelText: 'N° Factura *', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _numeroControlController,
                              decoration: const InputDecoration(labelText: 'N° Control *', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (_tipoDocumentoFiscal != 'FACTURA') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _facturaAfectadaController,
                                decoration: const InputDecoration(
                                  labelText: 'Factura Afectada *',
                                  hintText: 'Ej: 000145',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _fechaEmision,
                                  firstDate: DateTime(2023),
                                  lastDate: DateTime.now().add(const Duration(days: 30)),
                                );
                                if (picked != null) setState(() => _fechaEmision = picked);
                              },
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(DateFormat('dd/MM/yyyy').format(_fechaEmision), overflow: TextOverflow.ellipsis),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _tasaBcvController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Tasa BCV (Bs/\$)',
                                suffixText: 'Bs',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => _actualizarConversionPorCambioTasa(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 2. CARGA DE RENGLONES Y CONVERSIÓN BIDIRECCIONAL ($ / Bs)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.add_shopping_cart, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('2. Carga de Renglones (Mercancía / Gastos)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          if (_tipoRenglon == TipoRenglon.producto)
                            ElevatedButton.icon(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistroProductoScreen()));
                                _cargarDatosIniciales();
                              },
                              icon: const Icon(Icons.add_box, size: 18),
                              label: const Text('Crear Producto Nuevo'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                            )
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Selector de Tipo de Renglón: Producto vs Servicio/Gasto
                      SegmentedButton<TipoRenglon>(
                        segments: const [
                          ButtonSegment(
                            value: TipoRenglon.producto,
                            icon: Icon(Icons.inventory_2_outlined),
                            label: Text('📦 Producto (Suma Stock)'),
                          ),
                          ButtonSegment(
                            value: TipoRenglon.servicio,
                            icon: Icon(Icons.build_circle_outlined),
                            label: Text('🛠️ Servicio / Gasto (No mueve Stock)'),
                          ),
                        ],
                        selected: {_tipoRenglon},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _tipoRenglon = newSelection.first;
                            if (_tipoRenglon == TipoRenglon.servicio) {
                              _productoRenglonSeleccionado = null;
                              _searchProductoController.clear();
                              _nuevoPrecioVentaController.clear();
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),

                      // Campos según tipo de renglón
                      if (_tipoRenglon == TipoRenglon.producto) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Autocomplete<Map<String, dynamic>>(
                                displayStringForOption: (item) => '${item['codigo_producto']} - ${item['nombre']} (Stock: ${item['cantidad'] ?? 0})',
                                optionsBuilder: (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return const Iterable<Map<String, dynamic>>.empty();
                                  }
                                  return _productos.cast<Map<String, dynamic>>().where((p) {
                                    final nom = (p['nombre'] ?? '').toString().toLowerCase();
                                    final cod = (p['codigo_producto'] ?? '').toString().toLowerCase();
                                    return nom.contains(textEditingValue.text.toLowerCase()) || cod.contains(textEditingValue.text.toLowerCase());
                                  });
                                },
                                onSelected: _seleccionarProductoParaRenglon,
                                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                                  return TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    onEditingComplete: onEditingComplete,
                                    decoration: InputDecoration(
                                      labelText: 'Buscar en Catálogo de Productos',
                                      hintText: 'Escriba nombre o código...',
                                      prefixIcon: const Icon(Icons.search),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      isDense: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _descripcionItemController,
                                decoration: const InputDecoration(
                                  labelText: 'Descripción del Renglón *',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: _descripcionItemController,
                          decoration: const InputDecoration(
                            labelText: 'Descripción del Servicio o Gasto *',
                            hintText: 'Ej: Internet fibra óptica mes Octubre, Flete de materiales, Electricidad, Mantenimiento...',
                            prefixIcon: Icon(Icons.description_outlined),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),

                      // Cantidad, Costo Unit. (Bs)* primero, Ref. Unit. ($) segundo, IVA y Nuevo P. Venta
                      Wrap(
                        spacing: 14,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: _cantidadController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Cantidad *', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          SizedBox(
                            width: 165,
                            child: TextField(
                              controller: _costoUnitarioBsController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Costo Unit. (Bs)*', prefixText: 'Bs ', border: OutlineInputBorder(), isDense: true),
                              onChanged: _onCostoBsChanged,
                            ),
                          ),
                          SizedBox(
                            width: 145,
                            child: TextField(
                              controller: _costoUnitarioController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Ref. Unit. (\$)', prefixText: '\$ ', border: OutlineInputBorder(), isDense: true),
                              onChanged: _onCostoUsdChanged,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: _itemAplicaIva,
                                onChanged: (val) => setState(() => _itemAplicaIva = val),
                                activeThumbColor: Colors.blue,
                              ),
                              const Text('Aplica IVA (16%)', style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          if (_tipoRenglon == TipoRenglon.producto && _productoRenglonSeleccionado != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade300)),
                              child: Text(
                                'Precio Venta: \$${_productoRenglonSeleccionado!['precio_usd']}',
                                style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: TextField(
                                controller: _nuevoPrecioVentaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Nuevo P. Venta (\$)',
                                  hintText: 'Opcional si subió',
                                  prefixText: '\$ ',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                          ElevatedButton.icon(
                            onPressed: _agregarRenglonAlCarrito,
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar Renglón'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                          )
                        ],
                      ),

                      if (_tipoRenglon == TipoRenglon.producto &&
                          _productoRenglonSeleccionado != null &&
                          _costoUnitarioController.text.isNotEmpty &&
                          (double.tryParse(_costoUnitarioController.text.replaceAll(',', '.')) ?? 0) >= (double.tryParse(_productoRenglonSeleccionado!['precio_usd'].toString()) ?? 0)) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade300)),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚠️ ALERTA DE MARGEN: El costo unitario ingresado (\$${_costoUnitarioController.text}) iguala o supera el precio de venta actual (\$${_productoRenglonSeleccionado!['precio_usd']}). Se recomienda actualizar el precio de venta.',
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Tabla de Renglones Agregados (FULL-WIDTH 100% con ConstrainedBox)
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: _renglonesCompra.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(28.0),
                                child: Center(child: Text('No hay renglones agregados todavía.', style: TextStyle(color: Colors.grey, fontSize: 14))),
                              )
                            : LayoutBuilder(
                                builder: (context, tableConstraints) {
                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: tableConstraints.maxWidth),
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.resolveWith((_) => Colors.blue.shade50),
                                        columns: const [
                                          DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Descripción', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Cant.', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Costo Unit. (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Ref. Unit. (\$)', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('IVA 16%', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Subtotal (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Subtotal (\$)', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Nuevo P. Venta', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                        rows: _renglonesCompra.asMap().entries.map((entry) {
                                          final idx = entry.key;
                                          final item = entry.value;
                                          final cBs = (item['costo_unitario_bs'] as num?)?.toDouble() ?? 0.0;
                                          final cUsd = (item['costo_unitario_usd'] as num?)?.toDouble() ?? 0.0;
                                          final subBs = (item['subtotal_bs'] as num?)?.toDouble() ?? 0.0;
                                          final subUsd = (item['subtotal_usd'] as num?)?.toDouble() ?? 0.0;

                                          return DataRow(
                                            cells: [
                                              DataCell(Text('${idx + 1}')),
                                              DataCell(Text(item['descripcion'] ?? '')),
                                              DataCell(Text('${item['cantidad']}')),
                                              DataCell(Text('Bs ${cBs.toStringAsFixed(2)}')),
                                              DataCell(Text('\$${cUsd.toStringAsFixed(2)}')),
                                              DataCell(Chip(
                                                label: Text(item['aplica_iva'] ? '16%' : 'Exento', style: const TextStyle(fontSize: 10)),
                                                backgroundColor: item['aplica_iva'] ? Colors.blue.shade100 : Colors.green.shade100,
                                              )),
                                              DataCell(Text('Bs ${subBs.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                              DataCell(Text('\$${subUsd.toStringAsFixed(2)}')),
                                              DataCell(
                                                item['producto_id'] == null
                                                    ? Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.grey.shade200,
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: const Text('Servicio / Gasto', style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold)),
                                                      )
                                                    : Text(item['nuevo_precio_usd'] != null ? '\$${item['nuevo_precio_usd']}' : '-')
                                              ),
                                              DataCell(IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.red),
                                                onPressed: () => _eliminarRenglon(idx),
                                              )),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 3. PANEL DE RETENCIONES FISCALES SENIAT (IVA E ISLR)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.deepOrange),
                          SizedBox(width: 8),
                          Text('3. Retenciones Fiscales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // FILA RETENCIÓN DE IVA
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200)
                        ),
                        child: Row(
                          children: [
                            Switch(
                              value: _aplicaRetencionIva,
                              onChanged: (val) => setState(() => _aplicaRetencionIva = val),
                              activeThumbColor: Colors.deepOrange,
                            ),
                            const Text('Aplicar Retención de IVA', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 24),
                            if (_aplicaRetencionIva) ...[
                              const Text('% Retención: '),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('75% (Ordinario)'),
                                selected: _porcentajeRetIva == 75,
                                onSelected: (_) => setState(() => _porcentajeRetIva = 75),
                                selectedColor: Colors.orange.shade300,
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('100% (Especial)'),
                                selected: _porcentajeRetIva == 100,
                                onSelected: (_) => setState(() => _porcentajeRetIva = 100),
                                selectedColor: Colors.orange.shade300,
                              ),
                              const Spacer(),
                              Text(
                                'IVA Retenido: Bs ${_formatearMontoBs(totales['iva_retenido_bs']!)} (Ref: \$${totales['iva_retenido_usd']!.toStringAsFixed(2)})',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                              ),
                            ]
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // FILA RETENCIÓN DE ISLR
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.shade200)
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Switch(
                                  value: _aplicaRetencionIslr,
                                  onChanged: (val) => setState(() => _aplicaRetencionIslr = val),
                                  activeThumbColor: Colors.purple,
                                ),
                                const Text('Aplicar Retención de ISLR', style: TextStyle(fontWeight: FontWeight.bold)),
                                const Spacer(),
                                if (_aplicaRetencionIslr)
                                  Text(
                                    'ISLR Retenido: Bs ${_formatearMontoBs(totales['islr_retenido_bs']!)} (Ref: \$${totales['islr_retenido_usd']!.toStringAsFixed(2)})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple),
                                  ),
                              ],
                            ),
                            if (_aplicaRetencionIslr) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _conceptoIslrSeleccionado,
                                      isExpanded: true,
                                      decoration: const InputDecoration(labelText: 'Concepto ISLR *', border: OutlineInputBorder(), isDense: true),
                                      items: const [
                                        DropdownMenuItem(value: '053', child: Text('053 - Transporte de Carga / Fletes (3%)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: '014', child: Text('014 - Contratistas y Servicios (2%)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: '004', child: Text('004 - Honorarios Profesionales (3%)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: '029', child: Text('029 - Publicidad y Propaganda (3%)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'OTRO', child: Text('Personalizado', overflow: TextOverflow.ellipsis)),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) _seleccionarConceptoIslr(val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: _porcentajeRetIslrController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: '% Ret. ISLR *', suffixText: '%', border: OutlineInputBorder(), isDense: true),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              )
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 4. RESUMEN FINANCIERO Y CIERRE CON NETO REAL A PAGAR
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.monetization_on, color: Colors.green),
                          SizedBox(width: 8),
                          Text('4. Resumen Fiscal, Condiciones de Pago y Cierre', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Columna Izquierda: Método de Pago y Crédito
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  key: ValueKey(_metodoPago),
                                  initialValue: _metodoPago,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Condición / Método de Pago *', border: OutlineInputBorder()),
                                  items: ['Efectivo', 'Transferencia', 'Pago Móvil', 'Zelle', 'Divisa', 'Crédito']
                                      .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _metodoPago = val!;
                                      if (_metodoPago != 'Crédito') {
                                        _diasCreditoController.text = '0';
                                      } else if (_diasCreditoController.text == '0') {
                                        _diasCreditoController.text = '15';
                                      }
                                    });
                                  },
                                ),
                                if (_metodoPago == 'Crédito') ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _diasCreditoController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(labelText: 'Días de Crédito *', suffixText: 'días', border: OutlineInputBorder()),
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Fecha de Vencimiento:', style: TextStyle(fontSize: 11, color: Colors.brown)),
                                            Text(DateFormat('dd/MM/yyyy').format(fechaVencimiento), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange)),
                                          ],
                                        ),
                                      )
                                    ],
                                  )
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(width: 32),

                          // Columna Derecha: Totales con Desglose de Retenciones (Bolívares como moneda principal)
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300)
                              ),
                              child: Column(
                                children: [
                                  _filaTotal('Compras Exentas:', 'Bs ${_formatearMontoBs(totales['exento_bs']!)}', '\$${totales['exento_usd']!.toStringAsFixed(2)}'),
                                  const SizedBox(height: 4),
                                  _filaTotal('Base Imponible (16%):', 'Bs ${_formatearMontoBs(totales['base_bs']!)}', '\$${totales['base_usd']!.toStringAsFixed(2)}'),
                                  const SizedBox(height: 4),
                                  _filaTotal('Crédito Fiscal IVA (16%):', 'Bs ${_formatearMontoBs(totales['iva_bs']!)}', '\$${totales['iva_usd']!.toStringAsFixed(2)}'),
                                  const Divider(height: 12),
                                  _filaTotal('TOTAL FACTURA:', 'Bs ${_formatearMontoBs(totales['total_bs']!)}', '\$${totales['total_usd']!.toStringAsFixed(2)}', isBold: true),
                                  if (_aplicaRetencionIva) ...[
                                    const SizedBox(height: 4),
                                    _filaTotal('(-) Retención IVA ($_porcentajeRetIva%):', '-Bs ${_formatearMontoBs(totales['iva_retenido_bs']!)}', '-\$${totales['iva_retenido_usd']!.toStringAsFixed(2)}', color: Colors.deepOrange),
                                  ],
                                  if (_aplicaRetencionIslr) ...[
                                    const SizedBox(height: 4),
                                    _filaTotal('(-) Retención ISLR:', '-Bs ${_formatearMontoBs(totales['islr_retenido_bs']!)}', '-\$${totales['islr_retenido_usd']!.toStringAsFixed(2)}', color: Colors.purple),
                                  ],
                                  const Divider(height: 16),
                                  _filaTotal(
                                    'NETO A PAGAR PROVEEDOR:',
                                    'Bs ${_formatearMontoBs(totales['neto_pagar_bs']!)}',
                                    '\$${totales['neto_pagar_usd']!.toStringAsFixed(2)}',
                                    isBold: true,
                                    color: Colors.green.shade900
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _guardandoCompra ? null : _guardarCompra,
                          icon: _guardandoCompra ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
                          label: Text(_guardandoCompra ? 'Guardando en Base de Datos...' : 'Guardar y Procesar Compra / Retenciones', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            elevation: 4
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filaTotal(String titulo, String montoBs, String montoUsd, {bool isBold = false, Color? color}) {
    final c = color ?? (isBold ? Colors.blue.shade900 : Colors.black87);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(titulo, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 14 : 12.5, color: c)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(montoBs, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, fontSize: isBold ? 15 : 12.5, color: c)),
            Text('(Ref: $montoUsd)', style: TextStyle(fontSize: isBold ? 12 : 10.5, color: Colors.grey.shade700)),
          ],
        )
      ],
    );
  }

  // =========================================================================
  // VISTA PESTAÑA 2: LIBRO DE COMPRAS FISCAL SENIAT Y CUENTAS POR PAGAR
  // =========================================================================
  Widget _construirPestanaLibroCompras() {
    final comprasParaMostrar = _obtenerComprasFiltradasParaMostrar();

    double totalComprasUsd = 0;
    double totalComprasBs = 0;
    double totalIvaCreditoBs = 0;
    double totalRetenidoBs = 0;
    double totalPorPagarUsd = 0;

    for (final c in comprasParaMostrar) {
      if (c['estado'] != 'ANULADA') {
        final esNC = c['tipo_documento_fiscal'] == 'NOTA_CREDITO';
        final mult = esNC ? -1.0 : 1.0;
        final tasa = (double.tryParse(c['tasa_bcv'].toString()) ?? 1.0);

        totalComprasUsd += (double.tryParse(c['total_usd'].toString()) ?? 0.0) * mult;
        totalComprasBs += (double.tryParse(c['total_bs'].toString()) ?? 0.0) * mult;
        final ivaValBs = double.tryParse(c['iva_bs']?.toString() ?? '') ??
            ((double.tryParse(c['iva_usd']?.toString() ?? '') ?? 0.0) * tasa);
        totalIvaCreditoBs += ivaValBs * mult;

        final ivaRet = (double.tryParse(c['iva_retenido_bs'].toString()) ?? 0.0) * mult;
        final islrRet = (double.tryParse(c['islr_retenido_bs'].toString()) ?? 0.0) * mult;
        totalRetenidoBs += (ivaRet + islrRet);

        if (c['estado'] == 'PENDIENTE') {
          totalPorPagarUsd += (double.tryParse(c['neto_pagar_usd'].toString()) ?? (double.tryParse(c['total_usd'].toString()) ?? 0.0));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BARRA SUPERIOR: Filtros y Botones Exportar (PDF, Excel, TXT IVA, XML ISLR)
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('Período: $_etiquetaPeriodo', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      onSelected: _setFiltroFechaCompras,
                      icon: const Icon(Icons.filter_list_alt, color: Colors.blue),
                      tooltip: 'Opciones de fecha',
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'HOY', child: Text('Día de Hoy')),
                        PopupMenuItem(value: 'MES', child: Text('Mes Actual')),
                        PopupMenuItem(value: 'PERIODO', child: Text('Elegir Rango...')),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.green),
                      tooltip: 'Limpiar Filtros y Recargar (Ver Todo)',
                      onPressed: _limpiarFiltrosCompras,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _searchComprasController,
                        decoration: InputDecoration(
                          labelText: 'Buscar por N° Factura, Control o Proveedor',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        onChanged: (val) {
                          setState(() => _searchComprasQuery = val.toLowerCase());
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Botones de Exportar
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _generarReportePDFCompras,
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('PDF'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _descargarExcelCompras,
                    icon: const Icon(Icons.table_view, size: 16),
                    label: const Text('Excel'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _descargarTxtIva,
                    icon: const Icon(Icons.description, size: 16),
                    label: const Text('TXT IVA'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _descargarXmlIslr,
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('XML ISLR'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                  ),
                ],
              )
            ],
          ),

          const SizedBox(height: 16),

          // DASHBOARD DE TOTALES
          Row(
            children: [
              Expanded(
                child: _tarjetaMetrica(
                  'Total Compras (Bs / \$)',
                  'Bs ${totalComprasBs.toStringAsFixed(2)} (\$${totalComprasUsd.toStringAsFixed(2)})',
                  Colors.blue.shade50,
                  Colors.blue.shade800,
                  Icons.shopping_bag
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tarjetaMetrica(
                  'Crédito Fiscal IVA (Bs)',
                  'Bs ${totalIvaCreditoBs.toStringAsFixed(2)}',
                  Colors.teal.shade50,
                  Colors.teal.shade800,
                  Icons.account_balance
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tarjetaMetrica(
                  'Total Retenido IVA + ISLR (Bs)',
                  'Bs ${totalRetenidoBs.toStringAsFixed(2)}',
                  Colors.deepOrange.shade50,
                  Colors.deepOrange.shade900,
                  Icons.shield
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tarjetaMetrica(
                  'Cuentas por Pagar Netas (USD)',
                  '\$${totalPorPagarUsd.toStringAsFixed(2)}',
                  Colors.orange.shade50,
                  Colors.deepOrange.shade800,
                  Icons.pending_actions
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // CHIPS DE FILTRO DE ESTADO
          Row(
            children: [
              const Text('Filtrar estado:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              ChoiceChip(label: const Text('Todas'), selected: _filtroEstado == 'TODAS', onSelected: (_) => _aplicarFiltroEstadoCompras('TODAS')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Pagadas'), selected: _filtroEstado == 'PAGADA', onSelected: (_) => _aplicarFiltroEstadoCompras('PAGADA'), selectedColor: Colors.green.shade200),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Por Pagar (Pendientes)'), selected: _filtroEstado == 'PENDIENTE', onSelected: (_) => _aplicarFiltroEstadoCompras('PENDIENTE'), selectedColor: Colors.orange.shade200),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Anuladas'), selected: _filtroEstado == 'ANULADA', onSelected: (_) => _aplicarFiltroEstadoCompras('ANULADA'), selectedColor: Colors.red.shade200),
            ],
          ),

          const SizedBox(height: 14),

          // TABLA DE DATOS RESPONSIVE (SIN RENDERFLEX OVERFLOW)
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300)
              ),
              child: comprasParaMostrar.isEmpty
                  ? const Center(child: Text('No hay documentos de compras que coincidan con los filtros.', style: TextStyle(color: Colors.grey, fontSize: 15)))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.resolveWith((_) => Colors.blue.shade50),
                                columns: const [
                                  DataColumn(label: Text('Fecha Emisión', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('N° Factura', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('N° Control', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Proveedor', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Condición', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Estado', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Base (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('IVA (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Ret. IVA (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Ret. ISLR (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Total Factura (Bs)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Neto a Pagar', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: comprasParaMostrar.map((compra) {
                                  final prov = compra['Proveedor'];
                                  final rifNombre = prov != null ? '${prov['tipo_documento']}-${prov['numero_documento']} ${prov['nombre']}' : 'Desconocido';
                                  final diasCred = compra['dias_credito'] ?? 0;
                                  final condicion = diasCred > 0 ? 'Crédito' : 'Contado';
                                  final esNC = compra['tipo_documento_fiscal'] == 'NOTA_CREDITO';
                                  final mult = esNC ? -1.0 : 1.0;
                                  final tasa = (double.tryParse(compra['tasa_bcv'].toString()) ?? 1.0);

                                  final baseBs = (double.tryParse(compra['base_imponible_bs']?.toString() ?? '') ?? ((double.tryParse(compra['base_imponible_usd'].toString()) ?? 0.0) * tasa)) * mult;
                                  final ivaBs = (double.tryParse(compra['iva_bs']?.toString() ?? '') ?? ((double.tryParse(compra['iva_usd'].toString()) ?? 0.0) * tasa)) * mult;
                                  final totalBs = (double.tryParse(compra['total_bs'].toString()) ?? 0.0) * mult;
                                  final retIvaBs = (double.tryParse(compra['iva_retenido_bs'].toString()) ?? 0.0) * mult;
                                  final retIslrBs = (double.tryParse(compra['islr_retenido_bs'].toString()) ?? 0.0) * mult;
                                  final netoPagarBs = (double.tryParse(compra['neto_pagar_bs'].toString()) ?? (totalBs - retIvaBs - retIslrBs)) * mult;
                                  final netoPagarUsd = (double.tryParse(compra['neto_pagar_usd'].toString()) ?? 0.0) * mult;

                                  Widget widgetEstado;
                                  if (compra['estado'] == 'PENDIENTE') {
                                    final fechaEmisionDoc = DateTime.tryParse(compra['fecha_emision']) ?? DateTime.now();
                                    final fechaVenc = fechaEmisionDoc.add(Duration(days: diasCred));
                                    final diasRestantes = fechaVenc.difference(DateTime.now()).inDays;

                                    Color semaforoColor = Colors.orange;
                                    String textoVenc = 'Vence en $diasRestantes d';
                                    if (diasRestantes < 0) {
                                      semaforoColor = Colors.red;
                                      textoVenc = 'VENCIDA (${diasRestantes.abs()} d)';
                                    } else if (diasRestantes <= 3) {
                                      semaforoColor = Colors.deepOrange;
                                      textoVenc = 'Por vencer ($diasRestantes d)';
                                    }

                                    widgetEstado = Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: semaforoColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: semaforoColor)),
                                          child: Text('PENDIENTE', style: TextStyle(color: semaforoColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                        ),
                                        Text(textoVenc, style: TextStyle(fontSize: 10, color: semaforoColor, fontWeight: FontWeight.w600)),
                                      ],
                                    );
                                  } else if (compra['estado'] == 'PAGADA') {
                                    widgetEstado = Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green)),
                                      child: const Text('PAGADA', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                                    );
                                  } else {
                                    widgetEstado = Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red)),
                                      child: const Text('ANULADA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                                    );
                                  }

                                  Color tipoColor = Colors.blue;
                                  if (compra['tipo_documento_fiscal'] == 'NOTA_CREDITO') tipoColor = Colors.red.shade700;
                                  if (compra['tipo_documento_fiscal'] == 'NOTA_DEBITO') tipoColor = Colors.purple.shade700;

                                  final tieneRetIva = compra['aplica_retencion_iva'] == true && compra['comprobante_ret_iva'] != null;
                                  final tieneRetIslr = compra['aplica_retencion_islr'] == true && compra['comprobante_ret_islr'] != null;

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(compra['fecha_emision'] ?? '')),
                                      DataCell(Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: tipoColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                                        child: Text(compra['tipo_documento_fiscal'] ?? 'FAC', style: TextStyle(color: tipoColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                      )),
                                      DataCell(Text(compra['numero_factura'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                                      DataCell(Text(compra['numero_control'] ?? '')),
                                      DataCell(SizedBox(
                                        width: 170,
                                        child: Text(rifNombre, overflow: TextOverflow.ellipsis),
                                      )),
                                      DataCell(Text(condicion)),
                                      DataCell(widgetEstado),
                                      DataCell(Text(baseBs.toStringAsFixed(2))),
                                      DataCell(Text(ivaBs.toStringAsFixed(2))),
                                      DataCell(Text(retIvaBs > 0 ? 'Bs ${retIvaBs.toStringAsFixed(2)}' : '-', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600))),
                                      DataCell(Text(retIslrBs > 0 ? 'Bs ${retIslrBs.toStringAsFixed(2)}' : '-', style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.w600))),
                                      DataCell(Text(totalBs.toStringAsFixed(2))),
                                      DataCell(Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Bs ${netoPagarBs.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: esNC ? Colors.red : Colors.green.shade900)),
                                          Text('\$${netoPagarUsd.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                        ],
                                      )),
                                      DataCell(Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.visibility, color: Colors.blue, size: 20),
                                            tooltip: 'Ver Detalles',
                                            onPressed: () => _verDetallesCompra(compra),
                                          ),
                                          if (tieneRetIva)
                                            IconButton(
                                              icon: const Icon(Icons.picture_as_pdf, color: Colors.deepOrange, size: 20),
                                              tooltip: 'Imprimir Comprobante Ret. IVA',
                                              onPressed: () => _imprimirComprobanteRetIva(compra),
                                            ),
                                          if (tieneRetIslr)
                                            IconButton(
                                              icon: const Icon(Icons.print, color: Colors.purple, size: 20),
                                              tooltip: 'Imprimir Comprobante Ret. ISLR',
                                              onPressed: () => _imprimirComprobanteRetIslr(compra),
                                            ),
                                          if (compra['estado'] == 'PENDIENTE')
                                            IconButton(
                                              icon: const Icon(Icons.payment, color: Colors.green, size: 20),
                                              tooltip: 'Saldar Cuenta',
                                              onPressed: () => _mostrarDialogoPagarCompra(compra),
                                            ),
                                          if (compra['estado'] != 'ANULADA')
                                            IconButton(
                                              icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                                              tooltip: 'Anular Documento',
                                              onPressed: () => _mostrarDialogoAnularCompra(compra),
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
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaMetrica(String titulo, String valor, Color bgColor, Color textColor, IconData icono) {
    return Card(
      elevation: 1,
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: textColor.withValues(alpha: 0.15),
              child: Icon(icono, color: textColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(titulo, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(valor, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textColor)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // VISTA PESTAÑA 3: DIRECTORIO DE PROVEEDORES
  // =========================================================================
  Widget _construirPestanaProveedores() {
    double deudaTotalUsd = 0;
    double deudaTotalBs = 0;
    for (final p in _proveedores) {
      deudaTotalUsd += (p['total_pendiente_usd'] as num?)?.toDouble() ?? 0.0;
      deudaTotalBs += (p['total_pendiente_bs'] as num?)?.toDouble() ?? 0.0;
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchProveedoresTabController,
                  decoration: InputDecoration(
                    labelText: 'Buscar Proveedor por RIF o Nombre...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchProveedoresTabController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchProveedoresTabController.clear();
                              _filtrarProveedoresTab('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  onChanged: _filtrarProveedoresTab,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _mostrarDialogoRegistroRapidoProveedor(''),
                icon: const Icon(Icons.add_business),
                label: const Text('Nuevo Proveedor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _tarjetaMetrica(
                  'Proveedores Registrados',
                  '${_proveedores.length}',
                  Colors.blue.shade50,
                  Colors.blue.shade800,
                  Icons.business
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tarjetaMetrica(
                  'Deuda Cuentas por Pagar (\$)',
                  '\$${deudaTotalUsd.toStringAsFixed(2)}',
                  Colors.orange.shade50,
                  Colors.deepOrange.shade800,
                  Icons.receipt
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _tarjetaMetrica(
                  'Deuda Cuentas por Pagar (Bs)',
                  'Bs ${deudaTotalBs.toStringAsFixed(2)}',
                  Colors.purple.shade50,
                  Colors.purple.shade800,
                  Icons.account_balance_wallet
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300)
              ),
              child: _proveedoresTabFiltrados.isEmpty
                  ? const Center(child: Text('No hay proveedores registrados o no coinciden con la búsqueda.', style: TextStyle(color: Colors.grey)))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.resolveWith((_) => Colors.blue.shade50),
                                columns: const [
                                  DataColumn(label: Text('RIF / Documento', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Razón Social / Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Teléfono', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Correo', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Ret. IVA %', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Ret. ISLR %', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Crédito Habitual', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Deuda Pendiente (\$)', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Acciones', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: _proveedoresTabFiltrados.map((prov) {
                                  final deudaUsd = (prov['total_pendiente_usd'] as num?)?.toDouble() ?? 0.0;
                                  return DataRow(
                                    cells: [
                                      DataCell(Text('${prov['tipo_documento']}-${prov['numero_documento']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                      DataCell(Text(prov['nombre'] ?? '')),
                                      DataCell(Text(prov['telefono'] ?? '-')),
                                      DataCell(Text(prov['correo'] ?? '-')),
                                      DataCell(Text('${prov['porcentaje_retencion_iva'] ?? 75}%')),
                                      DataCell(Text('${prov['porcentaje_retencion_islr'] ?? 0}%')),
                                      DataCell(Text('${prov['dias_credito_habitual'] ?? 0} días')),
                                      DataCell(
                                        deudaUsd > 0
                                            ? Chip(
                                                label: Text('\$${deudaUsd.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                                backgroundColor: Colors.deepOrange,
                                              )
                                            : const Text('\$0.00', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      ),
                                      DataCell(Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.blue),
                                            tooltip: 'Editar Proveedor',
                                            onPressed: () => _mostrarDialogoEditarProveedor(prov),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            tooltip: 'Eliminar Proveedor',
                                            onPressed: () => _eliminarProveedor(prov),
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
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
