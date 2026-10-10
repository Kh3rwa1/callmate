import 'package:flutter/material.dart';

/// Line icons that stand in for the emoji the data layer still carries
/// (business categories, skills, lead attributes). Emoji look like a
/// template; one consistent icon family reads as designed.
class AppIcons {
  const AppIcons._();

  static const _byEmoji = <String, IconData>{
    '🎓': Icons.school_outlined,
    '📚': Icons.menu_book_outlined,
    '🏠': Icons.home_work_outlined,
    '🩺': Icons.medical_services_outlined,
    '🧪': Icons.science_outlined,
    '🚗': Icons.directions_car_outlined,
    '💇': Icons.content_cut_rounded,
    '🍽️': Icons.restaurant_outlined,
    '🍽': Icons.restaurant_outlined,
    '🛍️': Icons.shopping_bag_outlined,
    '🛍': Icons.shopping_bag_outlined,
    '🛠️': Icons.handyman_outlined,
    '🛠': Icons.handyman_outlined,
    '💼': Icons.work_outline_rounded,
    '📞': Icons.call_outlined,
    '🎯': Icons.track_changes_rounded,
    '💬': Icons.chat_bubble_outline_rounded,
    '📅': Icons.event_outlined,
    '🎧': Icons.headset_mic_outlined,
    '🛎️': Icons.room_service_outlined,
    '🛎': Icons.room_service_outlined,
    '❓': Icons.help_outline_rounded,
    '📄': Icons.description_outlined,
    '🌐': Icons.language_rounded,
    '📝': Icons.edit_note_rounded,
    '📍': Icons.place_outlined,
    '🕒': Icons.schedule_rounded,
    '💰': Icons.payments_outlined,
    '📌': Icons.push_pin_outlined,
    '🗣': Icons.record_voice_over_outlined,
    '🤝': Icons.handshake_outlined,
    '💳': Icons.credit_card_rounded,
    '📥': Icons.inbox_outlined,
    '🚀': Icons.rocket_launch_outlined,
    '🔥': Icons.local_fire_department_rounded,
    '✅': Icons.check_circle_rounded,
    '⚠️': Icons.error_outline_rounded,
    '✨': Icons.auto_awesome_rounded,
    '🎉': Icons.celebration_outlined,
    '👔': Icons.badge_outlined,
    '😊': Icons.sentiment_satisfied_rounded,
    '☀️': Icons.wb_sunny_outlined,
    '❄️': Icons.ac_unit_rounded,
    '•': Icons.circle_outlined,
  };

  /// Icon for [emoji], or null when there is no mapping.
  static IconData? forEmoji(String emoji) => _byEmoji[emoji.trim()];
}
