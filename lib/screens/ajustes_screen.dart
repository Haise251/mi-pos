import 'package:flutter/material.dart';

import '../services/base_datos.dart';
import '../services/excel_service.dart';
import '../services/respaldo_service.dart';
import '../services/tasa_service.dart';
import 'bitacora_screen.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController();
  final _tasaDivisaCtrl = TextEditingController();
  final _comisionCtrl = TextEditingController();
  bool _cargando = true;
  bool _procesandoRespaldo = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _tasaCtrl.dispose();
    _tasaDivisaCtrl.dispose();
    _comisionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    _nombreCtrl.text = await BaseDatos.instancia.obtenerNombreNegocio();
    final tasa = await BaseDatos.instancia.obtenerTasa();
    _tasaCtrl.text = tasa.toString();
    // Si no hay tasa de divisa configurada, precargamos la general
    final tasaDivisa = await BaseDatos.instancia.obtenerTasaDivisa();
    _tasaDivisaCtrl.text =
        (tasaDivisa > 0 ? tasaDivisa : tasa).toStringAsFixed(2);
    final comision = await BaseDatos.instancia.obtenerComisionAvance();
    _comisionCtrl.text = comision % 1 == 0
        ? comision.toStringAsFixed(0)
        : comision.toString();
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final tasa = double.parse(_tasaCtrl.text.replaceAll(',', '.'));
    final tasaDivisa = double.parse(_tasaDivisaCtrl.text.replaceAll(',', '.'));
    final comision = double.parse(_comisionCtrl.text.replaceAll(',', '.'));
    // Guarda en BD y notifica a todo el sistema al instante (también queda en bitácora)
    await TasaService.guardar(tasa);
    await BaseDatos.instancia.guardarTasaDivisa(tasaDivisa);
    await BaseDatos.instancia.guardarNombreNegocio(_nombreCtrl.text.trim());
    await BaseDatos.instancia.guardarComisionAvance(comision);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✅ Ajustes guardados')));
  }

  // ---------- Respaldo Excel ----------

  Future<void> _exportarExcel() async {
    setState(() => _procesandoRespaldo = true);
    try {
      final ruta = await ExcelService.instancia.exportarRespaldo();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ruta == null
                ? 'Exportación cancelada'
                : '✅ Respaldo guardado en:\n$ruta',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al exportar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoRespaldo = false);
    }
  }

  Future<void> _importarExcel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar respaldo'),
        content: const Text(
          'Se crearán los productos y clientes que falten y se '
              'actualizarán los existentes según el archivo Excel.\n\n'
              'No se borrará nada del sistema actual.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesandoRespaldo = true);
    try {
      final r = await ExcelService.instancia.importarRespaldo();
      if (!mounted) return;
      if (r['cancelado'] == true) return;
      if (r['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${r['error']}')),
        );
        return;
      }
      final tasa = r['tasa'] as double?;
      final comision = r['comision'] as double?;
      final negocio = r['nombre'] as String?;
      if (tasa != null && tasa > 0) await TasaService.guardar(tasa);
      if (comision != null) {
        await BaseDatos.instancia.guardarComisionAvance(comision);
      }
      if (negocio != null) {
        await BaseDatos.instancia.guardarNombreNegocio(negocio);
      }
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Productos: ${r['productosCreados']} creados, '
                '${r['productosActualizados']} actualizados'
                '${r['productosOmitidos'] > 0 ? ', ${r['productosOmitidos']} omitidos' : ''}\n'
                'Clientes: ${r['clientesCreados']} nuevos, '
                '${r['clientesActualizados']} actualizados',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error al importar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoRespaldo = false);
    }
  }

  // ---------- Respaldo local (.db) ----------

  Future<void> _exportarBd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copia local de la base de datos'),
        content: const Text(
          'Se guardará una copia completa (.db) de TODO: productos, ventas, '
              'clientes, créditos, compras y bitácora.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar copia'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesandoRespaldo = true);
    try {
      final ruta = await RespaldoService.instancia.exportar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ruta == null
                ? 'Operación cancelada'
                : '✅ Copia guardada en:\n$ruta',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoRespaldo = false);
    }
  }

  Future<void> _restaurarBd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Restaurar base de datos'),
        content: const Text(
          'Esto REEMPLAZARÁ todos los datos actuales por los del archivo '
              'que elijas:\n\n'
              '• Ventas, compras y abonos actuales se perderán\n'
              '• Volverán los del respaldo\n\n'
              'Recomendación: exporta una copia actual ANTES de restaurar.\n\n'
              '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesandoRespaldo = true);
    try {
      final msg = await RespaldoService.instancia.restaurar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $msg'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoRespaldo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- Configuración general ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Configuración general',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del negocio',
                        prefixIcon: Icon(Icons.store),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tasaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tasa: Bs por 1 \$',
                        prefixIcon: Icon(Icons.currency_exchange),
                        suffixText: 'Bs/\$',
                        border: OutlineInputBorder(),
                        helperText:
                        'Tasa general del sistema (precios y cobros en Bs)',
                      ),
                      validator: (v) {
                        final t = double.tryParse(
                          v?.replaceAll(',', '.') ?? '',
                        );
                        if (t == null || t <= 0) {
                          return 'Ingresa una tasa válida mayor a 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tasaDivisaCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tasa para cobros en divisas',
                        prefixIcon: Icon(Icons.attach_money),
                        suffixText: 'Bs/\$',
                        border: OutlineInputBorder(),
                        helperText:
                        'Tasa especial para valorar los cobros en USD (Efectivo \$, Zelle, Binance). Se precarga al cobrar y puede ajustarse al vuelo',
                      ),
                      validator: (v) {
                        final t = double.tryParse(
                          v?.replaceAll(',', '.') ?? '',
                        );
                        if (t == null || t <= 0) {
                          return 'Ingresa una tasa válida mayor a 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _comisionCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Comisión de avance de efectivo (%)',
                        prefixIcon: Icon(Icons.percent),
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        helperText:
                        'Porcentaje que se precarga al hacer un avance de efectivo',
                      ),
                      validator: (v) {
                        final c = double.tryParse(
                          v?.replaceAll(',', '.') ?? '',
                        );
                        if (c == null || c < 0 || c > 100) {
                          return 'Ingresa un porcentaje entre 0 y 100';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _guardar,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar cambios'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---------- Respaldo Excel + Copia local BD ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Respaldo de datos (Excel)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Exporta productos, clientes y configuración a un '
                        'archivo .xlsx, o restaura desde uno. La importación '
                        'crea lo que falta y actualiza lo existente.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  if (_procesandoRespaldo) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _procesandoRespaldo
                              ? null
                              : _exportarExcel,
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Exportar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _procesandoRespaldo
                              ? null
                              : _importarExcel,
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Importar'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Text(
                    'Copia completa local (.db)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Incluye TODO: ventas históricas, créditos, compras '
                        'y bitácora. La restauración reemplaza todos los '
                        'datos actuales.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _procesandoRespaldo
                              ? null
                              : _exportarBd,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Copiar BD'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade900,
                          ),
                          onPressed: _procesandoRespaldo
                              ? null
                              : _restaurarBd,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restaurar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---------- Bitácora ----------
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Registro de actividad'),
              subtitle: const Text(
                'Bitácora de ventas, compras, usuarios y cambios del sistema',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BitacoraScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Los precios se definen y registran en dólares (\$). '
                  'Los montos en Bs son referencia calculada con la tasa actual. '
                  'La tasa de cada venta queda guardada en el histórico.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}