import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../models/venta.dart';
import '../services/base_datos.dart';
import '../services/sesion.dart';

class InventarioScreen extends StatefulWidget {
  final bool soloLectura;

  /// Por defecto: los cajeros ven el inventario sin poder editar.
  InventarioScreen({super.key, bool? soloLectura})
    : soloLectura = soloLectura ?? !SesionActual.esAdmin;

  @override
  InventarioScreenState createState() => InventarioScreenState();
}

class InventarioScreenState extends State<InventarioScreen> {
  List<Producto> _productos = [];
  String _filtro = '';
  double _tasa = 0;
  bool _cargando = false;

  bool get _editable => !widget.soloLectura;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _cargando = true;
    if (mounted) setState(() {});
    _productos = await BaseDatos.instancia.listar(filtro: _filtro);
    _tasa = await BaseDatos.instancia.obtenerTasa();
    _cargando = false;
    if (mounted) setState(() {});
  }

  /// HomeScreen llama esto al entrar a la pestaña o volver de otras
  /// pantallas (Compras, etc.), para reflejar cambios de stock.
  Future<void> recargar() => _cargar();

  // ---------- Formulario alta/edición ----------

  Future<void> _formulario([Producto? producto]) async {
    if (!_editable) return;
    final codigoCtrl = TextEditingController(text: producto?.codigo ?? '');
    final nombreCtrl = TextEditingController(text: producto?.nombre ?? '');
    final precioCtrl = TextEditingController(
      text: producto?.precio.toString() ?? '',
    );
    final stockCtrl = TextEditingController(
      text: producto?.stock.toString() ?? '0',
    );
    final minCtrl = TextEditingController(
      text: producto?.stockMinimo.toString() ?? '5',
    );
    final formKey = GlobalKey<FormState>();

    var esIlimitado = producto?.stockIlimitado ?? false;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setEstadoDialog) => AlertDialog(
          title: Text(producto == null ? 'Nuevo producto' : 'Editar producto'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codigoCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Código de barras',
                      hintText: 'Escanea o escribe el código',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: precioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Precio en \$ *',
                    ),
                    validator: (v) =>
                        double.tryParse(v?.replaceAll(',', '.') ?? '') == null
                        ? 'Número inválido'
                        : null,
                  ),
                  // Referencia en Bs en vivo, según la tasa actual
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: precioCtrl,
                    builder: (_, val, _) {
                      final p =
                          double.tryParse(val.text.replaceAll(',', '.')) ?? 0;
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '≈ ${formatoBs(p * _tasa)} (tasa Bs ${_tasa.toStringAsFixed(2)}/\$)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stock ilimitado ∞'),
                    subtitle: const Text(
                      'Activar para productos sin control de stock (agua, servicios, refill)',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: esIlimitado,
                    onChanged: (val) =>
                        setEstadoDialog(() => esIlimitado = val),
                  ),
                  if (!esIlimitado) ...[
                    TextFormField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      enabled: producto == null, // en edición, usar "Ajustar"
                      decoration: InputDecoration(
                        labelText: 'Existencias',
                        helperText: producto == null
                            ? null
                            : 'Para cambiar stock usa el botón Ajustar',
                      ),
                    ),
                    TextFormField(
                      controller: minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Stock mínimo (alerta)',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final p = Producto(
                  id: producto?.id,
                  codigo: codigoCtrl.text.trim(),
                  nombre: nombreCtrl.text.trim(),
                  precio: double.parse(precioCtrl.text.replaceAll(',', '.')),
                  stock: esIlimitado
                      ? 0
                      : (producto == null
                          ? (int.tryParse(stockCtrl.text) ?? 0)
                          : producto.stock),
                  stockMinimo: esIlimitado
                      ? 0
                      : (int.tryParse(minCtrl.text) ?? 5),
                  stockIlimitado: esIlimitado,
                );
                try {
                  await BaseDatos.instancia.guardar(p);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '⚠️ El código ya existe en otro producto',
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardado == true) _cargar();
  }

  // ---------- Ajuste de stock con kardex ----------

  Future<void> _ajustarStock(Producto p) async {
    if (p.stockIlimitado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ℹ️ Este producto tiene stock ilimitado y no requiere ajuste.',
          ),
        ),
      );
      return;
    }
    var tipo = _TipoAjuste.entrada;
    final cantCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setEstado) => AlertDialog(
          title: Text('Stock de "${p.nombre}" (actual: ${p.stock})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<_TipoAjuste>(
                segments: const [
                  ButtonSegment(
                    value: _TipoAjuste.entrada,
                    icon: Icon(Icons.add),
                    label: Text('Entrada'),
                  ),
                  ButtonSegment(
                    value: _TipoAjuste.salida,
                    icon: Icon(Icons.remove),
                    label: Text('Salida'),
                  ),
                ],
                selected: {tipo},
                onSelectionChanged: (s) => setEstado(() => tipo = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cantCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (compra, merma, etc.)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );

    final cantidad = int.tryParse(cantCtrl.text) ?? 0;
    if (ok != true || cantidad <= 0) return;
    await BaseDatos.instancia.ajustarStock(
      p.id!,
      tipo == _TipoAjuste.entrada ? cantidad : -cantidad,
      tipo: tipo.name,
      referencia: motivoCtrl.text.trim().isEmpty
          ? 'Ajuste manual'
          : motivoCtrl.text.trim(),
    );
    _cargar();
  }

  // ---------- Kardex del producto ----------

  Future<void> _verKardex(Producto p) async {
    final movs = await BaseDatos.instancia.listarMovimientos(
      productoId: p.id,
      limite: 50,
    );
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Kardex: ${p.nombre}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (movs.isEmpty) const Text('Sin movimientos registrados'),
          ...movs.map(
            (m) => ListTile(
              dense: true,
              leading: Icon(
                m['tipo'] == 'entrada'
                    ? Icons.arrow_downward
                    : (m['tipo'] == 'salida' ? Icons.arrow_upward : Icons.tune),
                color: m['tipo'] == 'entrada' ? Colors.green : Colors.red,
              ),
              title: Text(
                '${m['tipo'].toString().toUpperCase()} de ${m['cantidad']}',
              ),
              subtitle: Text(
                '${m['fecha'].toString().substring(0, 16).replaceAll('T', ' ')} · ${m['usuario'] ?? '—'} · ${m['referencia'] ?? ''}',
              ),
              trailing: Text('Stock: ${m['stock_resultante'] ?? '?'}'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarEliminar(Producto p) async {
    if (!_editable) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Eliminar "${p.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (ok == true && p.id != null) {
      await BaseDatos.instancia.eliminar(p.id!);
      _cargar();
    }
  }

  Future<void> _vaciarCatalogo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Vaciar catálogo?'),
        content: const Text(
          'Se eliminarán TODOS los productos del inventario.\n\n'
          'Las ventas ya registradas conservan su detalle histórico.\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, vaciar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await BaseDatos.instancia.vaciarProductos();
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _editable
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab_vaciar',
                  tooltip: 'Vaciar catálogo',
                  onPressed: _vaciarCatalogo,
                  child: const Icon(Icons.delete_sweep_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab_nuevo',
                  onPressed: () => _formulario(),
                  icon: const Icon(Icons.add),
                  label: const Text('Producto'),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por nombre o código',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _filtro = v;
                      _cargar();
                    },
                  ),
                ),
                // 🔘 Botón para actualizar el inventario (stock tras compras)
                IconButton(
                  tooltip: 'Actualizar inventario',
                  icon: _cargando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _cargar,
                ),
              ],
            ),
          ),
          Expanded(
            child: _productos.isEmpty
                ? const Center(child: Text('Sin productos'))
                : ListView.separated(
                    itemCount: _productos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _productos[i];
                      final color = p.stockIlimitado
                          ? Colors.teal
                          : (p.sinStock
                              ? Colors.red
                              : (p.bajoStock ? Colors.orange : Colors.teal));
                      return ListTile(
                        leading: Icon(
                          p.stockIlimitado
                              ? Icons.all_inclusive
                              : Icons.inventory_2_outlined,
                          color: color,
                        ),
                        title: Text(p.nombre),
                        subtitle: Text(
                          'Cód: ${p.codigo.isEmpty ? '—' : p.codigo}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${formatoUsd(p.precio)} · ${formatoBs(p.precio * _tasa)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  p.stockIlimitado
                                      ? 'Stock: Ilimitado ∞'
                                      : 'Stock: ${p.stock}',
                                  style: TextStyle(fontSize: 12, color: color),
                                ),
                              ],
                            ),
                            if (_editable) ...[
                              IconButton(
                                tooltip: 'Ajustar stock',
                                icon: const Icon(Icons.tune),
                                onPressed: () => _ajustarStock(p),
                              ),
                              IconButton(
                                tooltip: 'Kardex',
                                icon: const Icon(Icons.history),
                                onPressed: () => _verKardex(p),
                              ),
                            ],
                          ],
                        ),
                        onTap: _editable ? () => _formulario(p) : null,
                        onLongPress: _editable
                            ? () => _confirmarEliminar(p)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _TipoAjuste { entrada, salida }
