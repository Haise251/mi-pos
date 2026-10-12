import '../models/usuario.dart';

class SesionActual {
  SesionActual._();
  static Usuario? usuario;
  static bool get estaLogueado => usuario != null;
  static bool get esAdmin => usuario?.rol == 'admin';
  static int? get usuarioId => usuario?.id;
  static void cerrar() => usuario = null;
}
