import 'package:flutter/material.dart';

/// Design tokens. One strong brand accent + semantic lead temperature colours.
class AppColors {
  const AppColors._();

  // Surfaces
  static const background = Color(0xFFFAF7F2); // warm off-white
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF3EFE8);
  static const border = Color(0xFFECE6DC);

  // Text
  static const ink = Color(0xFF17171C); // almost black
  static const inkSoft = Color(0xFF55555F);
  static const inkFaint = Color(0xFF8D8C95);

  // Brand
  static const brand = Color(0xFF4F46E5); // friendly indigo
  static const brandSoft = Color(0xFFEDECFD);
  static const brandDeep = Color(0xFF3730A3);

  // Semantic
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE6F6EC);
  static const warm = Color(0xFFF59E0B);
  static const warmSoft = Color(0xFFFEF3DC);
  static const hot = Color(0xFFE5484D);
  static const hotSoft = Color(0xFFFDEBEC);
  static const cold = Color(0xFF8D8C95);
  static const coldSoft = Color(0xFFF0EFF2);
  static const info = Color(0xFF0EA5E9);
  static const infoSoft = Color(0xFFE3F4FC);

  // WhatsApp handoff
  static const whatsapp = Color(0xFF1FAF5A);
  static const whatsappSoft = Color(0xFFE3F6EA);

  // Mascot halo
  static const mascotHalo = Color(0xFFFDE7DD);
}
