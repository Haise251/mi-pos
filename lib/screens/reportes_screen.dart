import 'package:flutter/material.dart';

import '../models/venta.dart';
import '../services/base_datos.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  static const _dias = [
    '',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const _meses = [
    '',
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  DateTime _dia = DateTime.now();
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>> _top = [];
  List<Map<String, dynamic>> _productosVendidos = [];
  String _filtroMetodo = 'todos';

  bool get _esHoy {
    final h = DateTime.now();
    return _dia.year == h.year && _dia.month == h.month && _dia.day == h.day;
  }

  String get _diaStr =>
      '${_dia.year}-${_dia.month.toString().padLeft(2, '0')}-${_dia.day.toString().padLeft(2, '0')}';

  String get _diaBonito =>
      '${_dias[_dia.weekday]} ${_dia.day} ${_meses[_dia.month]} ${_dia.year}';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _resumen = await BaseDatos.instancia.resumenDia(_diaStr);
    _top = await BaseDatos.instancia.topProductos(dias: 30, limite: 10);
    _productosVendidos = await BaseDatos.instancia.productosVendidosDia(
      _diaStr,
    );
    if (mounted) setState(() {});
  }

  void _moverDia(int delta) {
    setState(() => _dia = _dia.add(Duration(days: delta)));
    _cargar();
  }

  List<Map<String, dynamic>> get _ventasFiltradas {
    final rawVentas =
    (_resumen?['ventas'] as List? ?? []).cast<Map<String, dynamic>>();
    if (_filtroMetodo == 'todos') return rawVentas;
    return rawVentas.where((v) {
      final metodos = (v['metodos_pago'] as String? ?? '').toLowerCase();
      final estado = (v['estado_pago'] as String? ?? '').toLowerCase();
      if (_filtroMetodo == 'credito') return estado == 'credito';
      if (_filtroMetodo == 'avance') return metodos.contains('avance');
      return metodos.contains(_filtroMetodo.toLowerCase());
    }).toList();
  }

  Future<void> _dialogoArqueoCaja() async {
    if (_resumen == null) return;
    final espBs = (_resumen!['efectivoEsperadoBs'] as num?)?.toDouble() ?? 0;
    final espUsd = (_resumen!['efectivoEsperadoUsd'] as num?)?.toDouble() ?? 0;

    final contadoBsCtrl = TextEditingController();
    final contadoUsdCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setEstadoDialog) {
          final cBs =
              double.tryParse(contadoBsCtrl.text.replaceAll(',', '.')) ?? 0;
          final cUsd =
              double.tryParse(contadoUsdCtrl.text.replaceAll(',', '.')) ?? 0;

          final difBs = cBs - espBs;
          final difUsd = cUsd - espUsd;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.point_of_sale, color: Colors.teal),
                SizedBox(width: 8),
                Text('Arqueo de Caja'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💵 Efectivo Esperado en Caja',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('En Bolívares:'),
                            Text(
                              formatoBs(espBs),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('En Dólares (\$):'),
                            Text(
                              formatoUsd(espUsd),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contadoBsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Efectivo contado en Bolívares (Bs)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixText: 'Bs',
                    ),
                    onChanged: (_) => setEstadoDialog(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contadoUsdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Efectivo contado en Dólares (\$)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      suffixText: '\$',
                    ),
                    onChanged: (_) => setEstadoDialog(() {}),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (difBs == 0 && difUsd == 0)
                          ? Colors.green.shade50
                          : (difBs < 0 || difUsd < 0
                          ? Colors.red.shade50
                          : Colors.orange.shade50),
                      border: Border.all(
                        color: (difBs == 0 && difUsd == 0)
                            ? Colors.green
                            : (difBs < 0 || difUsd < 0
                            ? Colors.red
                            : Colors.orange),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (difBs == 0 && difUsd == 0)
                              ? '✅ Caja Cuadrada Perfecta'
                              : (difBs < 0 || difUsd < 0
                              ? '🚨 Faltante en caja'
                              : '⚠️ Sobrante en caja'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (difBs == 0 && difUsd == 0)
                                ? Colors.green
                                : (difBs < 0 || difUsd < 0
                                ? Colors.red
                                : Colors.orange.shade800),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Diferencia Bs:'),
                            Text(
                              formatoBs(difBs),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: difBs < 0
                                    ? Colors.red
                                    : (difBs > 0
                                    ? Colors.orange.shade800
                                    : Colors.green),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Diferencia \$:'),
                            Text(
                              formatoUsd(difUsd),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: difUsd < 0
                                    ? Colors.red
                                    : (difUsd > 0
                                    ? Colors.orange.shade800
                                    : Colors.green),
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
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
    contadoBsCtrl.dispose();
    contadoUsdCtrl.dispose();
  }

  Future<void> _detalleVenta(int ventaId) async {
    final det = await BaseDatos.instancia.detalleVenta(ventaId);
    if (det == null || !mounted) return;
    final venta = det['venta'] as Map<String, dynamic>;
    final items = (det['items'] as List).cast<Map<String, dynamic>>();
    final pagos = (det['pagos'] as List).cast<Map<String, dynamic>>();
    final tasa = (venta['tasa'] as num?)?.toDouble() ?? 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Venta #$ventaId',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(
                    venta['estado_pago'] == 'credito'
                        ? '📄 A crédito'
                        : '✅ Pagada',
                    style: TextStyle(
                      color: venta['estado_pago'] == 'credito'
                          ? Colors.red
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Fecha: ${venta['fecha'].toString().substring(0, 16).replaceAll('T', ' ')} · Tasa: Bs ${tasa.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Divider(height: 24),
            const Text(
              '📦 Productos vendidos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...items.map(
                  (i) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${i['cantidad']} × ${i['nombre_producto']}'),
                subtitle: Text(
                  '${formatoUsd((i['precio_usd'] as num).toDouble())} c/u',
                ),
                trailing: Text(
                  '${formatoUsd((i['subtotal_usd'] as num).toDouble())} · ${formatoBs((i['subtotal_usd'] as num).toDouble() * tasa)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const Divider(height: 24),
            const Text(
              '💳 Métodos de Pago',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...pagos.map((p) {
              final m = metodoPorId(p['metodo'] as String);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(m?.icono ?? Icons.payments, size: 20),
                title: Text(m?.nombre ?? (p['metodo'] as String)),
                subtitle: (p['referencia'] as String? ?? '').isEmpty
                    ? null
                    : Text('Ref: ${p['referencia']}'),
                trailing: Text(
                  '${formatoUsd((p['monto_usd'] as num).toDouble())} · ${formatoBs((p['monto_bs'] as num).toDouble())}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Venta',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${formatoUsd((venta['total_usd'] as num).toDouble())} · ${formatoBs((venta['total_bs'] as num).toDouble())}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumen;
    final maxCant = _top.isNotEmpty
        ? ((_top.first['cantidad'] as num?)?.toDouble() ?? 1)
        : 1.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Reportes de Ventas')),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---------- Selector de fecha ----------
          Card(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _moverDia(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _diaBonito,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _esHoy ? null : () => _moverDia(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: _esHoy
                      ? null
                      : () {
                    setState(() => _dia = DateTime.now());
                    _cargar();
                  },
                  child: const Text('Hoy'),
                ),
              ],
            ),
          ),

          // ---------- Resumen del día & Arqueo ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Resumen del día',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade50,
                          foregroundColor: Colors.teal,
                        ),
                        onPressed: _dialogoArqueoCaja,
                        icon: const Icon(Icons.point_of_sale, size: 18),
                        label: const Text('Arqueo de Caja'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${r['numVentas']} venta${r['numVentas'] == 1 ? '' : 's'}',
                      ),
                      Text(
                        '${formatoUsd(r['totalUsd'])} · ${formatoBs(r['totalBs'])}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  if (r['numVentas'] > 0)
                    Text(
                      'Ticket promedio: ${formatoUsd(r['totalUsd'] / r['numVentas'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  const Divider(height: 24),
                  _filaResumen(
                    '🛒 Compras del día',
                    '${r['numCompras']} · ${formatoUsd(r['comprasUsd'])}',
                  ),
                  _filaResumen(
                    '📄 Crédito otorgado',
                    formatoUsd(_montoMetodo(r['pagos'], 'credito')),
                  ),
                  _filaResumen(
                    '💰 Abonos recibidos',
                    '${r['numAbonos']} · ${formatoUsd(r['abonosUsd'])}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Desglose por método de pago',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if ((r['pagos'] as List).isEmpty)
                    const Text(
                      'Sin pagos registrados',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ...(r['pagos'] as List).map((p) {
                    final m = metodoPorId(p['metodo'] as String);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(m?.icono ?? Icons.payments, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m?.nombre ?? (p['metodo'] as String),
                            ),
                          ),
                          Text(
                            '${formatoUsd((p['total_usd'] as num).toDouble())} · ${formatoBs((p['total_bs'] as num).toDouble())}',
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ---------- Sección: Qué se vendió hoy ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shopping_bag, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(
                        '¿Qué se vendió hoy?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_productosVendidos.isEmpty)
                    const Text(
                      'No hay productos vendidos en esta fecha',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ..._productosVendidos.map((pv) {
                    final nombre = pv['nombre'] as String;
                    final cant =
                        (pv['cantidad'] as num?)?.toInt() ?? 0;
                    final usd =
                        (pv['total_usd'] as num?)?.toDouble() ?? 0;
                    final tasa =
                    (r['totalUsd'] > 0
                        ? r['totalBs'] / r['totalUsd']
                        : 0.0);
                    final bs = usd * (tasa > 0 ? tasa : 1);

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        nombre,
                        style:
                        const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('$cant unidad${cant == 1 ? '' : 'es'} vendida${cant == 1 ? '' : 's'}'),
                      trailing: Text(
                        '${formatoUsd(usd)} · ${formatoBs(bs)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ---------- Top 10 Productos del Mes ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔥 Lo más vendido (últimos 30 días)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_top.isEmpty)
                    const Text(
                      'Aún no hay ventas registradas',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ..._top.asMap().entries.map((e) {
                    final i = e.key;
                    final t = e.value;
                    final cant = (t['cantidad'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${i + 1}º',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t['nombre'] as String,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${cant.toStringAsFixed(0)} u · ${formatoUsd((t['total_usd'] as num).toDouble())}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: maxCant > 0 ? cant / maxCant : 0,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ---------- Lista de Ventas con Filtrado ----------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ventas del día',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      DropdownButton<String>(
                        value: _filtroMetodo,
                        isDense: true,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos los métodos'),
                          ),
                          DropdownMenuItem(
                            value: 'efectivo',
                            child: Text('💵 Efectivo'),
                          ),
                          DropdownMenuItem(
                            value: 'pagomovil',
                            child: Text('📱 Pago Móvil'),
                          ),
                          DropdownMenuItem(
                            value: 'punto',
                            child: Text('💳 Punto de Venta'),
                          ),
                          DropdownMenuItem(
                            value: 'zelle',
                            child: Text('💲 Zelle'),
                          ),
                          DropdownMenuItem(
                            value: 'credito',
                            child: Text('📄 Crédito'),
                          ),
                          DropdownMenuItem(
                            value: 'avance',
                            child: Text('💸 Avance de Efectivo'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _filtroMetodo = v);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_ventasFiltradas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Sin ventas para el método seleccionado',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ..._ventasFiltradas.map((v) {
                    final credito = v['estado_pago'] == 'credito';
                    final metodos =
                        v['metodos_pago'] as String? ?? 'Desconocido';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text(
                        '#${v['id']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      title: Text(
                        v['fecha'].toString().substring(11, 16),
                      ),
                      subtitle: Text(
                        credito ? '📄 A crédito' : '💳 $metodos',
                        style: TextStyle(
                          color: credito ? Colors.red : Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Text(
                        formatoUsd((v['total_usd'] as num).toDouble()),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _detalleVenta(v['id'] as int),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaResumen(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(etiqueta), Text(valor)],
      ),
    );
  }

  double _montoMetodo(List pagos, String metodo) {
    for (final p in pagos) {
      if (p['metodo'] == metodo) {
        return (p['total_usd'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }
}