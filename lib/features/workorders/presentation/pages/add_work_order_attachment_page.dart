import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

class AddWorkOrderAttachmentPage extends StatefulWidget {
  const AddWorkOrderAttachmentPage({super.key, required this.workOrderId});
  final String workOrderId;

  @override
  State<AddWorkOrderAttachmentPage> createState() =>
      _AddWorkOrderAttachmentPageState();
}

class _AddWorkOrderAttachmentPageState
    extends State<AddWorkOrderAttachmentPage> {
  final _picker = ImagePicker();
  XFile? _picked;
  final _caption = TextEditingController();
  bool _uploading = false;
  double _progress = 0.0;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final img = await _picker.pickImage(source: src, imageQuality: 90);
    if (img != null) setState(() => _picked = img);
  }

  Future<void> _upload() async {
    if (_picked == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una imagen')));
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0;
    });

    final db = FirebaseFirestore.instance;
    final storage = FirebaseStorage.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final file = File(_picked!.path);
    final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'jpg' : ext}';
    final storageRef = storage.ref().child(
      'workOrders/${widget.workOrderId}/attachments/$fileName',
    );

    try {
      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      uploadTask.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) {
          setState(() => _progress = s.bytesTransferred / s.totalBytes);
        }
      });

      final snap = await uploadTask.whenComplete(() => null);
      final url = await storageRef.getDownloadURL();
      final meta = await storageRef.getMetadata();

      final attRef = db
          .collection('workOrders')
          .doc(widget.workOrderId)
          .collection('attachments')
          .doc();
      await attRef.set({
        'url': url,
        'path': storageRef.fullPath,
        'caption': _caption.text.trim().isEmpty ? null : _caption.text.trim(),
        'contentType': meta.contentType,
        'size': meta.size,
        'uploadedBy': uid,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subiendo: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pad = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar adjunto')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploading
                            ? null
                            : () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploading
                            ? null
                            : () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Cámara'),
                      ),
                    ),
                  ],
                ),
                pad,
                AspectRatio(
                  aspectRatio: 1.5,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _picked == null
                        ? const Center(child: Text('Sin imagen seleccionada'))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_picked!.path),
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
                pad,
                TextField(
                  controller: _caption,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                pad,
                if (_uploading)
                  LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _uploading ? null : _upload,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: const Text('Subir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
