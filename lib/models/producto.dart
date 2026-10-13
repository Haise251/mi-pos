class Producto {
  final int? id;
  final String codigo;
  final String nombre;
  final double precio;
  final int stock;
  final int stockMinimo;
  final bool stockIlimitado;

  const Producto({
    this.id,
    required this.codigo,
    required this.nombre,
    required this.precio,
    this.stock = 0,
    this.stockMinimo = 5,
    this.stockIlimitado = false,
  });

  bool get bajoStock => !stockIlimitado && stock > 0 && stock <= stockMinimo;
  bool get sinStock => !stockIlimitado && stock <= 0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'codigo': codigo,
    'nombre': nombre,
    'precio': precio,
    'stock': stock,
    'stock_minimo': stockMinimo,
    'stock_ilimitado': stockIlimitado ? 1 : 0,
  };

  factory Producto.fromMap(Map<String, dynamic> map) => Producto(
    id: map['id'] as int?,
    codigo: (map['codigo'] ?? '') as String,
    nombre: map['nombre'] as String,
    precio: (map['precio'] as num).toDouble(),
    stock: (map['stock'] ?? 0) as int,
    stockMinimo: (map['stock_minimo'] ?? 5) as int,
    stockIlimitado: (map['stock_ilimitado'] ?? 0) == 1,
  );
}
