// lib/features/customers/presentation/pages/add_customer_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/refs.dart';

class AddCustomerPage extends StatefulWidget {
  const AddCustomerPage({super.key});

  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _docId = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();

  final _focusPhone = FocusNode();
  final _focusEmail = FocusNode();
  final _focusDocId = FocusNode();
  final _focusAddress = FocusNode();
  final _focusNotes = FocusNode();

  bool _saving = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _docId.dispose();
    _address.dispose();
    _notes.dispose();
    _focusPhone.dispose();
    _focusEmail.dispose();
    _focusDocId.dispose();
    _focusAddress.dispose();
    _focusNotes.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Nombre requerido';
    if (s.length < 3) return 'Mínimo 3 caracteres';
    return null;
  }

  String? _validateEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // opcional
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    return ok ? null : 'Email inválido';
  }

  String? _validatePhone(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // opcional
    if (s.length < 6) return 'Teléfono demasiado corto';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance.collection('customers').add({
        'shopId': shopRef, // Reference (no string)
        'fullName': _fullName.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'docId': _docId.text.trim().isEmpty ? null : _docId.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'createdAt': now,
        'updatedAt': now,
      });

      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar cliente')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _fullName,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo *',
                        hintText: 'Ej.: Juan Pérez',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _focusPhone.requestFocus(),
                      validator: _validateName,
                      autofillHints: const [AutofillHints.name],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      focusNode: _focusPhone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        hintText: '+51 999 000 111',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _focusEmail.requestFocus(),
                      validator: _validatePhone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      focusNode: _focusEmail,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'cliente@correo.com',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _focusDocId.requestFocus(),
                      validator: _validateEmail,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _docId,
                      focusNode: _focusDocId,
                      decoration: const InputDecoration(
                        labelText: 'Documento (DNI/RUC)',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _focusAddress.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      focusNode: _focusAddress,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _focusNotes.requestFocus(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notes,
                      focusNode: _focusNotes,
                      decoration: const InputDecoration(
                        labelText: 'Notas',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 5,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
