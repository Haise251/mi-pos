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
  final Map<int, ItemCarrito> _carrito = {};
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
    if (mounted) setState(() {}); // redibuja precios en Bs al instante
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

  /// HomeScreen llama esto al regresar a la pestaña de venta.
  Future<void> recargar() => _cargarCatalogo();

  double get _total => _carrito.values.fold(0, (s, i) => s + i.subtotal);

  int _enCarrito(Producto p) => _carrito[p.id]?.cantidad ?? 0;

  void _agregar(Producto p) {
    if (p.id == null) return;
    if (_enCarrito(p) >= p.stock) return; // sin stock disponible
    setState(() {
      final existente = _carrito[p.id];
      if (existente == null) {
        _carrito[p.id!] = ItemCarrito(p);
      } else {
        existente.cantidad++;
      }
    });
    _escanerFocus.requestFocus(); // el escáner siempre listo
  }

  void _quitar(Producto p) {
    setState(() {
      final item = _carrito[p.id];
      if (item == null) return;
      item.cantidad > 1 ? item.cantidad-- : _carrito.remove(p.id);
    });
    _escanerFocus.requestFocus(); // el escáner siempre listo
  }

  Future<void> _leerEscaner(String valor) async {
    final texto = valor.trim();
    if (texto.isEmpty) return;
    final porCodigo = await BaseDatos.instancia.buscarPorCodigo(texto);
    if (porCodigo != null) {
      _agregar(porCodigo);
    } else {
      _catalogo = await BaseDatos.instancia.listar(filtro: texto);
    }
    _escanerCtrl.clear();
    if (mounted) {
      setState(() {});
      _escanerFocus.requestFocus(); // listo para el siguiente escaneo
    }
  }

  // ---------- Diálogo de cobro ----------

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
                      if (clientes.isEmpty)
                        const Text(
                          '⚠️ No hay clientes registrados. El admin puede crearlos en "Cuentas por cobrar".',
                          style: TextStyle(fontSize: 12, color: Colors.red),
                        ),
                      if (clientes.isNotEmpty)
                        DropdownButtonFormField<int>(
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
                        // Digital y crédito no generan vuelto: se ajustan al restante
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
                        subtitle: p.referencia.isEmpty
                            ? null
                            : Text('Ref: ${p.referencia}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setEstado(() {
                            pagos.remove(p);
                            sugerirMonto();
                          }),
                        ),
                      );
                    }),
                    if (pagos.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Restante'),
                          Text(
                            '${formatoUsd(r > 0 ? r : 0)} · ${formatoBs(r > 0 ? r * _tasa : 0)}',
                          ),
                        ],
                      ),
                      if (vuelto > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Vuelto a entregar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              '${formatoUsd(vuelto)} · ${formatoBs(vuelto * _tasa)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                    ],
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
    final items = _carrito.values
        .map(
          (i) => ItemVenta(
            productoId: i.producto.id!,
            nombre: i.producto.nombre,
            cantidad: i.cantidad,
            precioUsd: i.producto.precio,
          ),
        )
        .toList();

    final res = await _dialogoCobro(totalUsd);
    if (res == null || !mounted) return;
    final pagos = (res['pagos'] as List).cast<Pago>();
    final clienteId = res['clienteId'] as int?;
    final hayCredito = pagos.any((p) => p.metodo == 'credito');
    if (hayCredito && clienteId == null) return;

    final ventaId = await BaseDatos.instancia.registrarVenta(
      items: items,
      pagos: pagos,
      tasa: _tasa,
      clienteId: clienteId,
    );

    final pagado = pagos.fold<double>(0, (s, p) => s + p.montoUsd);
    final vuelto = pagado - totalUsd;
    final creditoUsd = pagos
        .where((p) => p.metodo == 'credito')
        .fold<double>(0, (s, p) => s + p.montoUsd);

    _carrito.clear();
    await _cargarCatalogo();
    if (!mounted) return;
    _escanerFocus.requestFocus();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('✅ Venta registrada'),
        content: Text(
          'Venta #$ventaId\nTotal: ${formatoUsd(totalUsd)} · ${formatoBs(totalUsd * _tasa)}'
          '${vuelto > 0.005 ? '\nVuelto: ${formatoUsd(vuelto)} · ${formatoBs(vuelto * _tasa)}' : ''}'
          '${creditoUsd > 0.005 ? '\n📄 A crédito: ${formatoUsd(creditoUsd)}' : ''}',
        ),
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
    // Cualquier toque en la pantalla devuelve el foco al campo del escáner,
    // para que el siguiente escaneo siempre caiga en el lugar correcto.
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
      return const Center(
        child: Text(
          'Sin productos. El admin puede agregarlos en Inventario 📦',
        ),
      );
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
        final sinStock = p.stock <= 0;
        return Card(
          color: sinStock ? Colors.grey.shade200 : null,
          child: InkWell(
            onTap: sinStock ? null : () => _agregar(p),
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
                  Text(
                    'Stock: ${p.stock}',
                    style: TextStyle(
                      fontSize: 11,
                      color: p.stock <= 5 ? Colors.orange : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ticketView() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ticket',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_carrito.isNotEmpty)
                  IconButton(
                    tooltip: 'Vaciar carrito',
                    icon: const Icon(Icons.delete_sweep_outlined),
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
                    children: _carrito.values
                        .map(
                          (item) => ListTile(
                            dense: true,
                            title: Text(item.producto.nombre),
                            subtitle: Text(
                              '${formatoUsd(item.producto.precio)} c/u · ${formatoBs(item.producto.precio * _tasa)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => _quitar(item.producto),
                                ),
                                Text('${item.cantidad}'),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => _agregar(item.producto),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
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
                      formatoUsd(_total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  '≈ ${formatoBs(_total * _tasa)} · Tasa Bs ${_tasa.toStringAsFixed(2)}/\$',
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
