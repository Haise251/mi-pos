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
    if (mounted) setState(() {});
  }

  void _moverDia(int delta) {
    setState(() => _dia = _dia.add(Duration(days: delta)));
    _cargar();
  }

  Future<void> _detalleVenta(int ventaId) async {
    final det = await BaseDatos.instancia.detalleVenta(ventaId);
    if (det == null || !mounted) return;
    final venta = det['venta'] as Map<String, dynamic>;
    final items = (det['items'] as List).cast<Map<String, dynamic>>();
    final pagos = (det['pagos'] as List).cast<Map<String, dynamic>>();
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Venta #$ventaId',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            '${venta['fecha'].toString().substring(0, 16).replaceAll('T', ' ')} · '
            '${venta['estado_pago'] == 'credito' ? '📄 A crédito' : '✅ Pagada'}',
          ),
          const Divider(height: 24),
          ...items.map(
            (i) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${i['cantidad']} × ${i['nombre_producto']}'),
              trailing: Text(formatoUsd((i['subtotal_usd'] as num).toDouble())),
            ),
          ),
          const Divider(height: 24),
          const Text('Pagos', style: TextStyle(fontWeight: FontWeight.bold)),
          ...pagos.map((p) {
            final m = metodoPorId(p['metodo'] as String);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(m?.icono ?? Icons.payments, size: 20),
              title: Text(m?.nombre ?? (p['metodo'] as String)),
              trailing: Text(
                '${formatoUsd((p['monto_usd'] as num).toDouble())} · ${formatoBs((p['monto_bs'] as num).toDouble())}',
              ),
            );
          }),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${formatoUsd((venta['total_usd'] as num).toDouble())} · ${formatoBs((venta['total_bs'] as num).toDouble())}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
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
      appBar: AppBar(title: const Text('Reportes')),
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
                // ---------- Resumen del día ----------
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen del día',
                          style: Theme.of(context).textTheme.titleMedium,
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
                        const SizedBox(height: 8),
                        const Text(
                          'Pagos del día',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
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
                // ---------- Top productos ----------
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
                // ---------- Ventas del día ----------
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ventas de ${_esHoy ? 'hoy' : 'este día'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if ((r['ventas'] as List).isEmpty)
                          const Text(
                            'Sin ventas este día',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ...(r['ventas'] as List).map((v) {
                          final credito = v['estado_pago'] == 'credito';
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
                            subtitle: credito
                                ? const Text(
                                    '📄 A crédito',
                                    style: TextStyle(color: Colors.red),
                                  )
                                : null,
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
