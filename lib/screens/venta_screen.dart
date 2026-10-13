import 'dart:math';

import 'package:flutter/material.dart';

import '../models/producto.dart';
import '../models/venta.dart';
import '../services/base_datos.dart';
import '../services/tasa_service.dart';

class VentaScreen extends StatefulWidget {
  const VentaScreen({super.key});

  @override
  VentaScreenState createState() => VentaScreenState();
}

class VentaScreenState extends State<VentaScreen> {
  List<Producto> _catalogo = [];
  final Map<dynamic, ItemCarrito> _carrito = {};
  final _escanerCtrl = TextEditingController();
  final _escanerFocus = FocusNode();

  double get _tasa => TasaService.tasa.value;

  @override
  void initState() {
    super.initState();
    TasaService.tasa.addListener(_alCambiarTasa);
    _cargarCatalogo();
  }

  void _alCambiarTasa() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TasaService.tasa.removeListener(_alCambiarTasa);
    _escanerCtrl.dispose();
    _escanerFocus.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    _catalogo = await BaseDatos.instancia.listar();
    if (mounted) setState(() {});
  }

  Future<void> recargar() => _cargarCatalogo();

  double get _total => _carrito.values.fold(0, (s, i) => s + i.subtotal);

  int _enCarrito(Producto p) {
    if (p.id == null || p.codigo == '0000001') return 0;
    return _carrito[p.id]?.cantidad ?? 0;
  }

  void _agregar(Producto p) {
    if (p.id == null && p.codigo != '0000001') return;

    // Avance de efectivo: clave única por avance (permite varios en el ticket).
    // Producto normal: usamos su ID real.
    final dynamic clave =
    p.codigo == '0000001' ? DateTime.now().microsecondsSinceEpoch : p.id!;

    if (p.codigo != '0000001' &&
        !p.stockIlimitado &&
        _enCarrito(p) >= p.stock) {
      return;
    }

    setState(() {
      final existente = _carrito[clave];
      if (existente == null) {
        _carrito[clave] = ItemCarrito(p);
      } else {
        existente.cantidad++;
      }
    });
    _escanerFocus.requestFocus();
  }

  void _quitarClave(dynamic clave) {
    setState(() {
      final item = _carrito[clave];
      if (item == null) return;
      if (item.producto.codigo == '0000001') {
        _carrito.remove(clave);
      } else if (item.cantidad > 1) {
        item.cantidad--;
      } else {
        _carrito.remove(clave);
      }
    });
    _escanerFocus.requestFocus();
  }

  Future<void> _leerEscaner(String valor) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final texto = _escanerCtrl.text.trim();
    if (texto.isEmpty) return;

    final porCodigo = await BaseDatos.instancia.buscarPorCodigo(texto);
    if (porCodigo != null) {
      _agregar(porCodigo);
      _escanerCtrl.clear();
      _catalogo = await BaseDatos.instancia.listar();
    } else {
      _catalogo = await BaseDatos.instancia.listar(filtro: texto);
      _escanerCtrl.clear();
      if (_catalogo.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '⚠️ No se encontró producto con el código o nombre "$texto"',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        _catalogo = await BaseDatos.instancia.listar();
      }
    }
    if (mounted) {
      setState(() {});
      _escanerFocus.requestFocus();
    }
  }

  Future<int?> _dialogoNuevoClienteRapido(BuildContext parentCtx) async {
    final nombreCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final id = await showDialog<int>(
      context: parentCtx,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add, color: Colors.teal),
            SizedBox(width: 8),
            Text('Nuevo Cliente'),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre del cliente *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, null),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final nuevoId = await BaseDatos.instancia.guardarCliente(
                nombre: nombreCtrl.text.trim(),
                telefono: telCtrl.text.trim(),
              );
              if (c.mounted) Navigator.pop(c, nuevoId);
            },
            child: const Text('Guardar Cliente'),
          ),
        ],
      ),
    );
    nombreCtrl.dispose();
    telCtrl.dispose();
    return id;
  }

  Future<Map<String, dynamic>?> _dialogoCobro(double totalUsd) async {
    final clientes = await BaseDatos.instancia.listarClientes();
    final montoCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    var metodo = metodosPago.first;
    final pagos = <Pago>[];
    int? clienteSel;

    double restante() =>
        totalUsd - pagos.fold<double>(0, (s, p) => s + p.montoUsd);

    void sugerirMonto() {
      final r = restante();
      final v = metodo.esBs ? r / _tasa : r;
      montoCtrl.text = v <= 0.005 ? '' : v.toStringAsFixed(2);
    }

    sugerirMonto();

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstado) {
          final r = restante();
          final vuelto = r < -0.005 ? -r : 0.0;
          final cubierto = pagos.isNotEmpty && r <= 0.005;

          return AlertDialog(
            title: const Text('Cobrar'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${formatoUsd(totalUsd)} · ${formatoBs(totalUsd * _tasa)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Tasa: Bs ${_tasa.toStringAsFixed(2)} / \$1',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: metodosPago
                          .map(
                            (m) => ChoiceChip(
                          avatar: Icon(m.icono, size: 18),
                          label: Text(
                            m.nombre,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: metodo.id == m.id,
                          onSelected: (_) => setEstado(() {
                            metodo = m;
                            sugerirMonto();
                          }),
                        ),
                      )
                          .toList(),
                    ),
                    if (metodo.id == 'credito') ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: clienteSel,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Cliente *',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: clientes
                                  .map(
                                    (c) => DropdownMenuItem<int>(
                                  value: c['id'] as int,
                                  child: Text(c['nombre'] as String),
                                ),
                              )
                                  .toList(),
                              onChanged: (v) => setEstado(() => clienteSel = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              backgroundColor: Colors.teal.shade50,
                              foregroundColor: Colors.teal,
                            ),
                            onPressed: () async {
                              final nuevoId =
                              await _dialogoNuevoClienteRapido(ctx);
                              if (nuevoId != null) {
                                final nuevosClientes =
                                await BaseDatos.instancia.listarClientes();
                                setEstado(() {
                                  clientes.clear();
                                  clientes.addAll(nuevosClientes);
                                  clienteSel = nuevoId;
                                });
                              }
                            },
                            icon: const Icon(Icons.person_add, size: 18),
                            label: const Text('Nuevo'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: montoCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: metodo.esBs
                            ? 'Monto en bolívares'
                            : 'Monto en dólares',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        suffixText: metodo.esBs ? 'Bs' : '\$',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (!metodo.esEfectivo) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: refCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Referencia (opcional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        final monto =
                            double.tryParse(
                              montoCtrl.text.replaceAll(',', '.'),
                            ) ??
                                0;
                        if (monto <= 0) return;
                        if (metodo.id == 'credito' && clienteSel == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '⚠️ Selecciona un cliente para el crédito',
                              ),
                            ),
                          );
                          return;
                        }
                        double usd = metodo.esBs ? monto / _tasa : monto;
                        if (!metodo.esEfectivo) usd = min(usd, r);
                        setEstado(() {
                          pagos.add(
                            Pago(
                              metodo: metodo.id,
                              montoUsd: usd,
                              montoBs: usd * _tasa,
                              referencia: refCtrl.text.trim(),
                            ),
                          );
                          refCtrl.clear();
                          sugerirMonto();
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar pago'),
                    ),
                    ...pagos.map((p) {
                      final m = metodoPorId(p.metodo);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(m?.icono ?? Icons.payments, size: 20),
                        title: Text(
                          '${m?.nombre ?? p.metodo}: ${formatoUsd(p.montoUsd)} · ${formatoBs(p.montoBs)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setEstado(() {
                            pagos.remove(p);
                            sugerirMonto();
                          }),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: cubierto
                    ? () => Navigator.pop(ctx, {
                  'pagos': List<Pago>.of(pagos),
                  'clienteId': clienteSel,
                })
                    : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      montoCtrl.dispose();
      refCtrl.dispose();
    });
  }

  Future<void> _cobrar() async {
    if (_carrito.isEmpty || _tasa <= 0) return;
    final totalUsd = _total;

    // El ID real del producto "Avance de Efectivo" se resuelve aquí,
    // una sola vez, aunque haya varios avances en el carrito.
    Producto? productoAvance;
    final items = <ItemVenta>[];
    for (final i in _carrito.values) {
      if (i.producto.codigo == '0000001') {
        productoAvance ??= await BaseDatos.instancia.obtenerProductoAvance();
        items.add(ItemVenta(
          productoId: productoAvance.id!,
          nombre: i.producto.nombre,
          cantidad: i.cantidad,
          precioUsd: i.producto.precio,
        ));
      } else {
        items.add(ItemVenta(
          productoId: i.producto.id!,
          nombre: i.producto.nombre,
          cantidad: i.cantidad,
          precioUsd: i.producto.precio,
        ));
      }
    }

    final res = await _dialogoCobro(totalUsd);
    if (res == null || !mounted) return;
    final pagos = (res['pagos'] as List).cast<Pago>();
    final clienteId = res['clienteId'] as int?;

    final ventaId = await BaseDatos.instancia.registrarVenta(
      items: items,
      pagos: pagos,
      tasa: _tasa,
      clienteId: clienteId,
    );

    _carrito.clear();
    await _cargarCatalogo();
    if (!mounted) return;
    _escanerFocus.requestFocus();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✅ Venta registrada'),
        content: Text('Venta #$ventaId\nTotal: ${formatoUsd(totalUsd)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _escanerFocus.requestFocus(),
      behavior: HitTestBehavior.translucent,
      child: LayoutBuilder(
        builder: (context, c) {
          final escaner = Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _escanerCtrl,
              focusNode: _escanerFocus,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.qr_code_scanner),
                hintText: 'Escanea un código o busca producto…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: _leerEscaner,
            ),
          );

          return c.maxWidth > 700
              ? Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    escaner,
                    Expanded(child: _catalogoView()),
                  ],
                ),
              ),
              SizedBox(width: 360, child: _ticketView()),
            ],
          )
              : Column(
            children: [
              escaner,
              Expanded(flex: 3, child: _catalogoView()),
              Expanded(flex: 2, child: _ticketView()),
            ],
          );
        },
      ),
    );
  }

  Widget _catalogoView() {
    if (_catalogo.isEmpty) {
      return const Center(child: Text('Sin productos'));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.9,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _catalogo.length,
      itemBuilder: (_, i) {
        final p = _catalogo[i];
        final enCarrito = _enCarrito(p);
        return Card(
          child: InkWell(
            onTap: () => _agregar(p),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Badge(
                    isLabelVisible: enCarrito > 0,
                    label: Text('$enCarrito'),
                    child: const Icon(Icons.fastfood, size: 28),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(formatoUsd(p.precio)),
                  Text(
                    formatoBs(p.precio * _tasa),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _dialogoAvanceEfectivo() async {
    if (_tasa <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Configura primero la tasa de cambio')),
      );
      return;
    }
    // Precargamos el porcentaje de comisión guardado en Ajustes
    final comisionGuardada =
    await BaseDatos.instancia.obtenerComisionAvance();
    final textoComision = comisionGuardada % 1 == 0
        ? comisionGuardada.toStringAsFixed(0)
        : comisionGuardada.toString();
    final montoCtrl = TextEditingController(text: '1000');
    final comisionCtrl = TextEditingController(text: textoComision);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstadoDialog) {
          final montoBs =
              double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
          final pctComision =
              double.tryParse(comisionCtrl.text.replaceAll(',', '.')) ?? 0;
          final comisionBs = montoBs * (pctComision / 100);
          final totalBs = montoBs + comisionBs;
          final totalUsd = totalBs / _tasa;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.price_change, color: Colors.teal, size: 28),
                SizedBox(width: 10),
                Text('Avance de Efectivo'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: montoCtrl,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monto solicitado (Bs) *',
                      suffixText: 'Bs',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setEstadoDialog(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: comisionCtrl,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Porcentaje de comisión (%)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setEstadoDialog(() {}),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Monto a entregar:'),
                            Text(formatoBs(montoBs)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Comisión (${pctComision.toStringAsFixed(1)}%):'),
                            Text(formatoBs(comisionBs)),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total a cobrar:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${formatoBs(totalBs)} · ${formatoUsd(totalUsd)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                ),
                onPressed: totalBs <= 0
                    ? null
                    : () {
                  Navigator.pop(ctx);
                  // El ID real se resuelve al cobrar, no aquí.
                  _agregar(Producto(
                    codigo: '0000001',
                    nombre:
                    'Avance Efectivo (${formatoBs(montoBs)} + ${pctComision.toStringAsFixed(0)}% com.)',
                    precio: totalUsd,
                    stockIlimitado: true,
                  ));
                },
                icon: const Icon(Icons.add_shopping_cart, size: 22),
                label: const Text('Agregar al carrito'),
              ),
            ],
          );
        },
      ),
    );
    montoCtrl.dispose();
    comisionCtrl.dispose();
  }

  Widget _ticketView() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _dialogoAvanceEfectivo,
                icon: const Icon(Icons.price_change, size: 28),
                label: const Text(
                  '💸 AVANCE DE EFECTIVO',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Carrito / Ticket',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_carrito.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    label: const Text('Vaciar'),
                    onPressed: () {
                      setState(() => _carrito.clear());
                      _escanerFocus.requestFocus();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: _carrito.isEmpty
                ? const Center(child: Text('Carrito vacío'))
                : ListView(
              children: _carrito.entries.map((entry) {
                final clave = entry.key;
                final item = entry.value;
                final esAvance = item.producto.codigo == '0000001';

                return ListTile(
                  dense: true,
                  title: Text(item.producto.nombre),
                  subtitle: Text(
                    '${formatoUsd(item.producto.precio)} c/u · ${formatoBs(item.producto.precio * _tasa)}',
                  ),
                  trailing: esAvance
                      ? IconButton(
                    tooltip: 'Eliminar avance',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                    ),
                    onPressed: () => _quitarClave(clave),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                        ),
                        onPressed: () => _quitarClave(clave),
                      ),
                      Text('${item.cantidad}'),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _agregar(item.producto),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      formatoBs(_total * _tasa),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Tasa: Bs ${_tasa.toStringAsFixed(2)} / \$1',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _carrito.isEmpty ? null : _cobrar,
                    icon: const Icon(Icons.payments),
                    label: const Text('Cobrar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}