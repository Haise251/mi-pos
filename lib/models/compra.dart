class ItemCompra {
  final int productoId;
  final String nombre;
  final int cantidad;
  final double costoUsd;

  const ItemCompra({
    required this.productoId,
    required this.nombre,
    required this.cantidad,
    required this.costoUsd,
  });

  double get subtotalUsd => costoUsd * cantidad;
}
