import 'package:ctech_repair/theme_notifier.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
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
      String msg = 'Error: ${e.message ?? e.code}';
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        msg = '📧 Email no encontrado o inválido.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = '🔒 Contraseña incorrecta.';
      } else if (e.code == 'too-many-requests') {
        msg = '⏳ Demasiados intentos. Intenta más tarde.';
      } else if (e.code == 'network-request-failed') {
        msg = '🌐 Error de red. Verifica tu conexión.';
      } else if (e.code == 'user-disabled') {
        msg = '🚫 Esta cuenta ha sido deshabilitada.';
      }
      setState(() {
        _error = msg;
      });
    } catch (e) {
      setState(() {
        _error = '❌ Ocurrió un error inesperado: ${e.toString()}';
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
    final theme = Theme.of(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeIcon = isDarkMode
        ? Icons.light_mode_outlined
        : Icons.dark_mode_outlined;
    final themeTooltip = isDarkMode
        ? 'Cambiar a tema claro'
        : 'Cambiar a tema oscuro';

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 32.0,
                  ),
                  child: Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // --- Logo ---
                          Center(
                            child: SizedBox(
                              width: 180,
                              height: 180,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.jpg', // tu JPG
                                  fit: BoxFit.cover, // llena el círculo
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Bienvenido a RepairManager',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onBackground,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ingresa tus credenciales para acceder',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 40),

                          // --- Campo Email ---
                          TextFormField(
                            controller: _email,
                            decoration: const InputDecoration(
                              hintText: 'Email',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.email,
                              AutofillHints.username,
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'El email es requerido';
                              if (!v.contains('@') || !v.contains('.'))
                                return 'Ingresa un email válido';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // --- Campo Contraseña ---
                          TextFormField(
                            controller: _pass,
                            decoration: InputDecoration(
                              hintText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                splashRadius: 20,
                                tooltip: _obscure
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _signIn(),
                            validator: (v) {
                              if (v == null || v.isEmpty)
                                return 'La contraseña es requerida';
                              if (v.length < 6) return 'Mínimo 6 caracteres';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // --- Olvidaste contraseña ---
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                /* TODO */
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Funcionalidad no implementada.',
                                    ),
                                  ),
                                );
                              },
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // --- Mensaje de Error ---
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _error != null
                                ? Container(
                                    key: const ValueKey('error'),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.colorScheme.error
                                            .withOpacity(0.4),
                                      ),
                                    ),
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('no_error'),
                                  ),
                          ),
                          const SizedBox(height: 24),

                          // --- Botón de Entrar ---
                          ElevatedButton(
                            onPressed: _loading ? null : _signIn,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Ingresar'),
                          ),
                          SizedBox(
                            height: MediaQuery.of(context).viewInsets.bottom > 0
                                ? 100
                                : 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- Botón de Tema Flotante ---
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(themeIcon),
                tooltip: themeTooltip,
                onPressed: () {
                  final currentMode = themeNotifier.value;
                  final currentBrightness = MediaQuery.platformBrightnessOf(
                    context,
                  );
                  if (currentMode == ThemeMode.system) {
                    themeNotifier.value = currentBrightness == Brightness.dark
                        ? ThemeMode.light
                        : ThemeMode.dark;
                  } else {
                    themeNotifier.value = currentMode == ThemeMode.light
                        ? ThemeMode.dark
                        : ThemeMode.light;
                  }
                },
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
