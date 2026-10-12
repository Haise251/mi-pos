class Usuario {
  final int? id;
  final String nombre;
  final String usuario;
  final String salt;
  final String hash;
  final String rol; // 'admin' | 'cajero'
  final bool activo;

  const Usuario({
    this.id,
    required this.nombre,
    required this.usuario,
    this.salt = '',
    this.hash = '',
    this.rol = 'cajero',
    this.activo = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'usuario': usuario,
    'salt': salt,
    'hash': hash,
    'rol': rol,
    'activo': activo ? 1 : 0,
  };

  factory Usuario.fromMap(Map<String, dynamic> m) => Usuario(
    id: m['id'] as int?,
    nombre: m['nombre'] as String,
    usuario: m['usuario'] as String,
    salt: (m['salt'] ?? '') as String,
    hash: (m['hash'] ?? '') as String,
    rol: (m['rol'] ?? 'cajero') as String,
    activo: (m['activo'] ?? 1) == 1,
  );
}
