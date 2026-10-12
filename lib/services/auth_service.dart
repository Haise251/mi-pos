import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/usuario.dart';
import 'base_datos.dart';

class AuthService {
  static String _generarSalt() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String hashear(String salt, String password) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  /// Devuelve el usuario si las credenciales son correctas, null si no.
  /// Registra en bitácora tanto ingresos como intentos fallidos.
  static Future<Usuario?> login(String usuario, String password) async {
    final u = await BaseDatos.instancia.buscarUsuario(usuario.trim());
    if (u != null && hashear(u.salt, password) == u.hash) {
      await BaseDatos.instancia.registrarBitacora(
        'login',
        '${u.nombre} (${u.usuario})',
      );
      return u;
    }
    await BaseDatos.instancia.registrarBitacora(
      'login_fallido',
      'Intento con usuario "${usuario.trim()}"',
    );
    return null;
  }

  static Future<void> crearUsuario({
    required String nombre,
    required String usuario,
    required String password,
    String rol = 'cajero',
  }) async {
    final salt = _generarSalt();
    final u = Usuario(
      nombre: nombre,
      usuario: usuario,
      salt: salt,
      hash: hashear(salt, password),
      rol: rol,
    );
    final mapa = u.toMap()..['creado_en'] = DateTime.now().toIso8601String();
    await BaseDatos.instancia.insertarUsuario(mapa);
    await BaseDatos.instancia.registrarBitacora(
      'usuario_crear',
      '$nombre ($usuario) · rol $rol',
    );
  }

  /// Para editar: si [nuevaPassword] es null o vacía, conserva la actual.
  static Future<void> guardarUsuario(Usuario u, {String? nuevaPassword}) async {
    var copia = u;
    var cambioPass = false;
    if (nuevaPassword != null && nuevaPassword.isNotEmpty) {
      cambioPass = true;
      final salt = _generarSalt();
      copia = Usuario(
        id: u.id,
        nombre: u.nombre,
        usuario: u.usuario,
        salt: salt,
        hash: hashear(salt, nuevaPassword),
        rol: u.rol,
        activo: u.activo,
      );
    }
    await BaseDatos.instancia.actualizarUsuario(copia.toMap());
    await BaseDatos.instancia.registrarBitacora(
      'usuario_editar',
      '${u.nombre} (${u.usuario})${cambioPass ? ' · contraseña cambiada' : ''}',
    );
  }
}
