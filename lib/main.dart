import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'features/customers/presentation/pages/customers_page.dart';

//const shopId = 'aSq95R9gOu4VTFHf2MBR'; // tu shopId
//DocumentReference get shopRef =>
//    FirebaseFirestore.instance.doc('shops/$shopId');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'CtechRepair',

      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;

        return user == null ? const LoginPage() : const CustomersPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();

  final _email = TextEditingController();

  final _pass = TextEditingController();

  bool _loading = false;

  bool _obscure = true;

  String? _error;

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;

    setState(() {
      _loading = true;

      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),

        password: _pass.text,
      );
    } on FirebaseAuthException catch (e) {
      // Mensajes amigables

      String msg = 'Error al iniciar sesión';

      if (e.code == 'user-not-found') msg = 'Usuario no encontrado';

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Credenciales inválidas';
      }

      if (e.code == 'too-many-requests') {
        msg = 'Demasiados intentos. Intenta luego.';
      }

      setState(() {
        _error = msg;
      });
    } catch (_) {
      setState(() {
        _error = 'Ocurrió un error inesperado';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),

          child: Padding(
            padding: const EdgeInsets.all(24),

            child: Form(
              key: _form,

              child: Column(
                mainAxisSize: MainAxisSize.min,

                children: [
                  const Text(
                    'Iniciar sesión',

                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _email,

                    decoration: const InputDecoration(labelText: 'Email'),

                    keyboardType: TextInputType.emailAddress,

                    validator: (v) =>
                        (v == null || v.isEmpty || !v.contains('@'))
                        ? 'Ingresa un email válido'
                        : null,
                  ),

                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _pass,

                    decoration: InputDecoration(
                      labelText: 'Contraseña',

                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),

                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),

                    obscureText: _obscure,

                    validator: (v) => (v == null || v.length < 6)
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),

                  const SizedBox(height: 16),

                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,

                    child: ElevatedButton(
                      onPressed: _loading ? null : _signIn,

                      child: _loading
                          ? const SizedBox(
                              height: 18,

                              width: 18,

                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
