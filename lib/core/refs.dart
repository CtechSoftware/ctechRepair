// lib/core/refs.dart
import 'package:cloud_firestore/cloud_firestore.dart';

const shopId = 'aSq95R9gOu4VTFHf2MBR';

/// Referencia a la shop actual (tipo DocumentReference)
DocumentReference get shopRef =>
    // --- ¡CAMBIO AQUÍ! Se añade la barra '/' al inicio ---
    FirebaseFirestore.instance.doc('/shops/$shopId');
