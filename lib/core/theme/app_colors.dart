import 'package:flutter/material.dart';

/// Design tokens. One strong brand accent + semantic lead temperature colours.
class AppColors {
  const AppColors._();

  // Surfaces
  static const background = Color(0xFFFAF7F2); // warm off-white
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF3EFE8);
  static const border = Color(0xFFECE6DC);
  static const hairline = Color(0x14000000);

  // Text
  static const ink = Color(0xFF17171C); // almost black
  static const inkSoft = Color(0xFF55555F);
  static const inkFaint = Color(0xFF706F78); // 4.6:1 on background (AA)

  // Brand
  static const brand = Color(0xFF4F46E5); // friendly indigo
  static const brandSoft = Color(0xFFEDECFD);
  static const brandDeep = Color(0xFF3730A3);

  // Semantic
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFE6F6EC);
  static const warm = Color(0xFFF59E0B);
  static const warmSoft = Color(0xFFFEF3DC);
  static const warmInk = Color(0xFFB45309); // text on light surfaces
  static const hot = Color(0xFFD92D35);
  static const hotSoft = Color(0xFFFDEBEC);
  static const cold = Color(0xFF6B6A73);
  static const coldSoft = Color(0xFFF0EFF2);
  static const info = Color(0xFF0369A1);
  static const infoSoft = Color(0xFFE3F4FC);

  // WhatsApp handoff
  static const whatsapp = Color(0xFF0F7A3F);
  static const whatsappSoft = Color(0xFFE3F6EA);

  // Mascot halo
  static const mascotHalo = Color(0xFFFDE7DD);
}
