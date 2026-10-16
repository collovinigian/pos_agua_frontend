import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';
import 'dart:convert';
import 'app_events.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  bool _isLoading = true;
  bool _isSavingEmpresa = false;
  bool _isSavingImpresora = false;

  // Controladores de Identidad de Empresa
  final TextEditingController _razonSocialController = TextEditingController();
  final TextEditingController _rifController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  String? _logoBase64;

  // Variables de Impresora Fiscal
  bool _impresionActiva = false;
  String _modeloActual = 'HKA';
  String _puerto = 'COM1';
  final TextEditingController _copiasController = TextEditingController();

  final List<String> _modelosFiscales = ['HKA', 'Bixolon', 'PNP', 'Bematech', 'Epson', 'Vmax'];
  final List<String> _puertosDisponibles = ['COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'USB'];

  @override
  void initState() {
    super.initState();
    // Pre-poblar con valores actuales del configNotifier
    final currentConfig = AppEvents.configNotifier.value;
    _razonSocialController.text = currentConfig.razonSocial;
    _rifController.text = currentConfig.rif;
    _telefonoController.text = currentConfig.telefono;
    _direccionController.text = currentConfig.direccion;
    _logoBase64 = currentConfig.logoBase64;

    _cargarConfiguracion();
  }

  @override
  void dispose() {
    _razonSocialController.dispose();
    _rifController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _copiasController.dispose();
    super.dispose();
  }

  Future<void> _cargarConfiguracion() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:3000/api/configuracion'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            // Empresa
            _razonSocialController.text = data['razon_social'] ?? 'MI EMPRESA, C.A.';
            _rifController.text = data['rif'] ?? 'J-00000000-0';
            _telefonoController.text = data['telefono'] ?? '';
            _direccionController.text = data['direccion'] ?? 'DIRECCIÓN FISCAL DE LA EMPRESA';
            _logoBase64 = data['logo_base64'];

            // Impresora
            _impresionActiva = data['impresion_fiscal_activa'] ?? false;
            final modelo = data['modelo_impresora'] ?? 'HKA';
            _modeloActual = _modelosFiscales.contains(modelo) ? modelo : _modelosFiscales.first;
            final puerto = data['puerto_impresora'] ?? 'COM1';
            _puerto = _puertosDisponibles.contains(puerto) ? puerto : _puertosDisponibles.first;
            _copiasController.text = (data['copias_adicionales'] ?? 0).toString();
          });

          // Sincronizar tema con configNotifier
          final String colorKey = data['color_tema'] ?? 'blue';
          final Color seedColor = AppEvents.coloresDisponibles[colorKey] ?? Colors.blue;
          final String modoTema = data['tema_modo'] ?? 'light';

          AppEvents.configNotifier.value = ConfigData(
            razonSocial: _razonSocialController.text,
            rif: _rifController.text,
            direccion: _direccionController.text,
            telefono: _telefonoController.text,
            logoBase64: _logoBase64,
            themeMode: modoTema == 'dark' ? ThemeMode.dark : ThemeMode.light,
            seedColor: seedColor,
            colorTemaKey: colorKey,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al cargar configuración: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _seleccionarLogo() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'Imágenes',
        extensions: ['png', 'jpg', 'jpeg'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file != null) {
        final bytes = await file.readAsBytes();
        final base64String = base64Encode(bytes);
        if (mounted) {
          setState(() {
            _logoBase64 = base64String;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📷 Logo seleccionado. Presiona "Guardar Datos de Empresa" para confirmar.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al seleccionar imagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _quitarLogo() {
    setState(() {
      _logoBase64 = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logo quitado. Presiona "Guardar Datos de Empresa" para guardar el cambio.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _guardarDatosEmpresa() async {
    setState(() => _isSavingEmpresa = true);
    try {
      final response = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/configuracion'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "razon_social": _razonSocialController.text.trim(),
          "rif": _rifController.text.trim(),
          "direccion": _direccionController.text.trim(),
          "telefono": _telefonoController.text.trim(),
          "logo_base64": _logoBase64,
        }),
      );

      if (response.statusCode == 200) {
        AppEvents.configNotifier.value = AppEvents.configNotifier.value.copyWith(
          razonSocial: _razonSocialController.text.trim(),
          rif: _rifController.text.trim(),
          direccion: _direccionController.text.trim(),
          telefono: _telefonoController.text.trim(),
          logoBase64: _logoBase64,
          clearLogo: _logoBase64 == null,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Datos de empresa guardados correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error del servidor: ${response.body}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al guardar datos de empresa: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingEmpresa = false);
      }
    }
  }

  Future<void> _cambiarModoTema(ThemeMode modo) async {
    AppEvents.configNotifier.value = AppEvents.configNotifier.value.copyWith(themeMode: modo);
    try {
      await http.put(
        Uri.parse('http://127.0.0.1:3000/api/configuracion'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tema_modo": modo == ThemeMode.dark ? 'dark' : 'light',
        }),
      );
    } catch (e) {
      debugPrint('Error al guardar modo de tema en servidor: $e');
    }
  }

  Future<void> _cambiarColorTema(String colorKey, Color seedColor) async {
    AppEvents.configNotifier.value = AppEvents.configNotifier.value.copyWith(
      seedColor: seedColor,
      colorTemaKey: colorKey,
    );
    try {
      await http.put(
        Uri.parse('http://127.0.0.1:3000/api/configuracion'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "color_tema": colorKey,
        }),
      );
    } catch (e) {
      debugPrint('Error al guardar color de tema en servidor: $e');
    }
  }

  Future<void> _guardarConfiguracionImpresora() async {
    setState(() => _isSavingImpresora = true);
    try {
      final response = await http.put(
        Uri.parse('http://127.0.0.1:3000/api/configuracion'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "impresion_fiscal_activa": _impresionActiva,
          "modelo_impresora": _modeloActual,
          "puerto_impresora": _puerto,
          "copias_adicionales": int.tryParse(_copiasController.text) ?? 0,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Configuración de impresora guardada'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error del servidor: ${response.body}'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al guardar configuración de impresora: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingImpresora = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes del Sistema'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCardIdentidadEmpresa(colorScheme),
                const SizedBox(height: 24),
                _buildCardAparienciaTema(colorScheme),
                const SizedBox(height: 24),
                _buildCardImpresoraFiscal(colorScheme),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardIdentidadEmpresa(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Identidad de la Empresa',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Datos fiscales y logotipo para comprobantes, reportes y pantalla principal',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 28),

            // Sección de Logotipo
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Preview del Logo
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _logoBase64 != null && _logoBase64!.isNotEmpty
                      ? Image.memory(
                          base64Decode(_logoBase64!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                            color: colorScheme.error,
                          ),
                        )
                      : Icon(
                          Icons.storefront_outlined,
                          size: 44,
                          color: colorScheme.outline,
                        ),
                ),
                const SizedBox(width: 20),
                // Botones de acción del logo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _seleccionarLogo,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Subir / Cambiar Logo'),
                          ),
                          if (_logoBase64 != null && _logoBase64!.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: _quitarLogo,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Quitar Logo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                side: BorderSide(color: colorScheme.error),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Formatos admitidos: PNG, JPG, JPEG',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Campos de texto de la empresa
            TextField(
              controller: _razonSocialController,
              decoration: const InputDecoration(
                labelText: 'Razón Social / Nombre Comercial',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rifController,
                    decoration: const InputDecoration(
                      labelText: 'RIF / Identificación Fiscal',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _telefonoController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _direccionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Dirección Fiscal',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),

            // Botón Guardar
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSavingEmpresa ? null : _guardarDatosEmpresa,
                icon: _isSavingEmpresa
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Guardar Datos de Empresa'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardAparienciaTema(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ValueListenableBuilder<ConfigData>(
          valueListenable: AppEvents.configNotifier,
          builder: (context, config, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Apariencia y Tema',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Personaliza el modo visual y la paleta de colores de toda la aplicación',
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
                const Divider(height: 28),

                // Modo Claro / Oscuro
                Text(
                  'Modo Visual',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('Modo Claro'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('Modo Oscuro'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {config.themeMode},
                  onSelectionChanged: (Set<ThemeMode> newSelection) {
                    _cambiarModoTema(newSelection.first);
                  },
                ),
                const SizedBox(height: 24),

                // Selector de Color
                Text(
                  'Color de Acento',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: AppEvents.coloresDisponibles.entries.map((entry) {
                    final key = entry.key;
                    final color = entry.value;
                    final isSelected = config.colorTemaKey == key;
                    final nombre = AppEvents.nombresColores[key] ?? key;

                    return Tooltip(
                      message: nombre,
                      child: InkWell(
                        onTap: () => _cambiarColorTema(key, color),
                        borderRadius: BorderRadius.circular(24),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.onSurface
                                  : Colors.transparent,
                              width: 3.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.35),
                                blurRadius: isSelected ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 24)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCardImpresoraFiscal(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Dispositivos e Impresión Fiscal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Configuración del puerto serial y modelo de la máquina fiscal para este equipo',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 28),

            SwitchListTile(
              title: const Text('Activar Impresión Fiscal', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Habilita la comunicación con la impresora fiscal por el puerto serial al facturar.'),
              value: _impresionActiva,
              activeThumbColor: colorScheme.primary,
              onChanged: (val) => setState(() => _impresionActiva = val),
            ),
            const SizedBox(height: 16),

            Opacity(
              opacity: _impresionActiva ? 1.0 : 0.5,
              child: AbsorbPointer(
                absorbing: !_impresionActiva,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modelo de Impresora Fiscal', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Modelo Actual',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.print),
                      ),
                      // ignore: deprecated_member_use
                      value: _modeloActual,
                      items: _modelosFiscales.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _modeloActual = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Puerto (Impresora)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.usb),
                            ),
                            // ignore: deprecated_member_use
                            value: _puerto,
                            items: _puertosDisponibles.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _puerto = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _copiasController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Copias adicionales',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.file_copy),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSavingImpresora ? null : _guardarConfiguracionImpresora,
                icon: _isSavingImpresora
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Guardar Configuración de Impresora'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
