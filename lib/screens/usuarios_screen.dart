import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/base_datos.dart';
import '../services/sesion.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<Usuario> _usuarios = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _usuarios = await BaseDatos.instancia.listarUsuarios();
    if (mounted) setState(() {});
  }

  Future<void> _formulario([Usuario? u]) async {
    final nombreCtrl = TextEditingController(text: u?.nombre ?? '');
    final usuarioCtrl = TextEditingController(text: u?.usuario ?? '');
    final passCtrl = TextEditingController();
    var rol = u?.rol ?? 'cajero';
    var activo = u?.activo ?? true;
    final formKey = GlobalKey<FormState>();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setEstado) => AlertDialog(
          title: Text(u == null ? 'Nuevo usuario' : 'Editar usuario'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: usuarioCtrl,
                    decoration: const InputDecoration(labelText: 'Usuario *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    enabled: u == null, // el nombre de usuario no se cambia
                  ),
                  TextFormField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: u == null
                          ? 'Contraseña *'
                          : 'Nueva contraseña (vacío = sin cambio)',
                    ),
                    validator: (v) => (u == null && (v == null || v.isEmpty))
                        ? 'Requerido'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: rol,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: const [
                      DropdownMenuItem(value: 'cajero', child: Text('Cajero')),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrador'),
                      ),
                    ],
                    onChanged: (v) => setEstado(() => rol = v ?? 'cajero'),
                  ),
                  SwitchListTile(
                    title: const Text('Activo'),
                    value: activo,
                    onChanged: (v) => setEstado(() => activo = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (u == null) {
                  await AuthService.crearUsuario(
                    nombre: nombreCtrl.text.trim(),
                    usuario: usuarioCtrl.text.trim(),
                    password: passCtrl.text,
                    rol: rol,
                  );
                } else {
                  await AuthService.guardarUsuario(
                    Usuario(
                      id: u.id,
                      nombre: nombreCtrl.text.trim(),
                      usuario: u.usuario,
                      salt: u.salt,
                      hash: u.hash,
                      rol: rol,
                      activo: activo,
                    ),
                    nuevaPassword: passCtrl.text,
                  );
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _eliminar(Usuario u) async {
    if (u.id == SesionActual.usuarioId) {
      _aviso('No puedes eliminar tu propio usuario');
      return;
    }
    if (u.rol == 'admin' && await BaseDatos.instancia.contarAdmins() <= 1) {
      _aviso('Debe existir al menos un administrador');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Eliminar a "${u.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (ok == true && u.id != null) {
      await BaseDatos.instancia.eliminarUsuario(u.id!);
      _cargar();
    }
  }

  void _aviso(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('⚠️ $msg')));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formulario(),
        icon: const Icon(Icons.person_add),
        label: const Text('Usuario'),
      ),
      body: ListView.separated(
        itemCount: _usuarios.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final u = _usuarios[i];
          return ListTile(
            leading: CircleAvatar(
              child: Text(u.nombre.isEmpty ? '?' : u.nombre[0].toUpperCase()),
            ),
            title: Text('${u.nombre} (${u.usuario})'),
            subtitle: Text(
              '${u.rol == 'admin' ? 'Administrador' : 'Cajero'} · ${u.activo ? "Activo" : "Inactivo"}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _formulario(u),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _eliminar(u),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
