class Cliente {
  final int? id;
  final String nombre;
  final String telefono;

  const Cliente({this.id, required this.nombre, this.telefono = ''});

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'telefono': telefono,
    'creado_en': DateTime.now().toIso8601String(),
  };

  factory Cliente.fromMap(Map<String, dynamic> m) => Cliente(
    id: m['id'] as int?,
    nombre: m['nombre'] as String,
    telefono: (m['telefono'] ?? '') as String,
  );
}
