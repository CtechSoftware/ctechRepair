// lib/theme_notifier.dart
import 'package:flutter/material.dart';

// Notificador global que almacena el ThemeMode actual
// Inicialmente usa el tema del sistema
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
