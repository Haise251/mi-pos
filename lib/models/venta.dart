import 'package:flutter/material.dart';

import 'producto.dart';

class MetodoPago {
  final String id;
  final String nombre;
  final IconData icono;
  final bool esEfectivo; // puede dar vuelto
  final bool esBs; // se abona en bolívares
  const MetodoPago(
    this.id,
    this.nombre,
    this.icono, {
    this.esEfectivo = false,
    this.esBs = false,
  });
}

const List<MetodoPago> metodosPago = [
  MetodoPago('efectivo_usd', 'Efectivo \$', Icons.payments, esEfectivo: true),
  MetodoPago(
    'efectivo_bs',
    'Efectivo Bs',
    Icons.payments_outlined,
    esEfectivo: true,
    esBs: true,
  ),
  MetodoPago('pago_movil', 'Pago móvil', Icons.phone_android, esBs: true),
  MetodoPago(
    'transferencia',
    'Transferencia',
    Icons.account_balance,
    esBs: true,
  ),
  MetodoPago('punto', 'Punto de venta', Icons.credit_card, esBs: true),
  MetodoPago('zelle', 'Zelle', Icons.send_to_mobile),
  MetodoPago('binance', 'Binance', Icons.currency_bitcoin),
  MetodoPago('credito', 'A crédito', Icons.credit_score),
];

/// Métodos válidos para registrar abonos (todos menos el crédito).
List<MetodoPago> get metodosPagoAbono =>
    metodosPago.where((m) => m.id != 'credito').toList();

MetodoPago? metodoPorId(String id) {
  for (final m in metodosPago) {
    if (m.id == id) return m;
  }
  return null;
}

class Pago {
  final String metodo;
  final double montoUsd;
  final double montoBs;
  final String referencia;

  const Pago({
    required this.metodo,
    required this.montoUsd,
    required this.montoBs,
    this.referencia = '',
  });
}

class ItemVenta {
  final int productoId;
  final String nombre;
  final int cantidad;
  final double precioUsd;

  const ItemVenta({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.precioUsd,
  });

  double get subtotalUsd => precioUsd * cantidad;
}

class ItemCarrito {
  final Producto producto;
  int cantidad;
  ItemCarrito(this.producto, {this.cantidad = 1});
  double get subtotal => producto.precio * cantidad;
}

// ---------- Formato de montos ----------

String formatoUsd(double v) => '\$${v.toStringAsFixed(2)}';

String formatoBs(double v) => 'Bs ${v.toStringAsFixed(2)}';
