import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/licencia_screen.dart';
import 'screens/login_screen.dart';
import 'services/base_datos.dart';
import 'services/licencia_service.dart';
import 'services/tasa_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SQLite en Windows/Linux para desarrollo (en Android/Chromebook es nativo)
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await BaseDatos.instancia.listar(); // fuerza apertura + migración
  await TasaService.cargar(); // carga la tasa global
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const _Puerta(),
    );
  }
}

/// Decide qué mostrar al arrancar según el estado de la licencia.
class _Puerta extends StatefulWidget {
  const _Puerta();

  @override
  State<_Puerta> createState() => _PuertaState();
}

class _PuertaState extends State<_Puerta> {
  late Future<EstadoLicencia> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = LicenciaService().verificar();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EstadoLicencia>(
      future: _futuro,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data!.expirada
            ? const LicenciaScreen(modoBloqueo: true)
            : const LoginScreen();
      },
    );
  }
}
