import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../../data/templates/templates.dart';

/// One line-icon family for everything the UI draws.
///
/// Typed lookups ([category], [skill], [role], [knowledge],
/// [notification]) are what screens use. [forEmoji] only remains for emoji
/// arriving in backend text (e.g. notification titles).
class AppIcons {
  const AppIcons._();

  static IconData category(BusinessCategory c) => switch (c) {
    BusinessCategory.coaching => Icons.school_outlined,
    BusinessCategory.realEstate => Icons.home_work_outlined,
    BusinessCategory.clinic => Icons.medical_services_outlined,
    BusinessCategory.diagnostic => Icons.science_outlined,
    BusinessCategory.automobile => Icons.directions_car_outlined,
    BusinessCategory.salon => Icons.content_cut_rounded,
    BusinessCategory.gym => Icons.fitness_center_rounded,
    BusinessCategory.restaurant => Icons.restaurant_outlined,
    BusinessCategory.retail => Icons.shopping_bag_outlined,
    BusinessCategory.localServices => Icons.handyman_outlined,
    BusinessCategory.other => Icons.auto_awesome_outlined,
  };

  static IconData skill(EmployeeSkill s) => switch (s) {
    EmployeeSkill.makeCalls => Icons.call_outlined,
    EmployeeSkill.qualifyLeads => Icons.track_changes_rounded,
    EmployeeSkill.followUp => Icons.chat_bubble_outline_rounded,
    EmployeeSkill.bookAppointments => Icons.event_outlined,
    EmployeeSkill.sales => Icons.work_outline_rounded,
    EmployeeSkill.customerSupport => Icons.headset_mic_outlined,
    EmployeeSkill.admissions => Icons.school_outlined,
    EmployeeSkill.enquiryHandling => Icons.help_outline_rounded,
  };

  /// The accessory on the mascot's badge for each kind of employee.
  static IconData role(EmployeeRoleKind r) => switch (r) {
    EmployeeRoleKind.sales => Icons.work_rounded,
    EmployeeRoleKind.appointments => Icons.event_rounded,
    EmployeeRoleKind.support => Icons.chat_bubble_rounded,
    EmployeeRoleKind.admissions => Icons.menu_book_rounded,
    EmployeeRoleKind.reception => Icons.room_service_rounded,
    EmployeeRoleKind.general => Icons.call_rounded,
  };

  static IconData knowledge(KnowledgeType t) => switch (t) {
    KnowledgeType.pdf => Icons.description_outlined,
    KnowledgeType.website => Icons.language_rounded,
    KnowledgeType.faq => Icons.help_outline_rounded,
    KnowledgeType.businessInfo => Icons.place_outlined,
    KnowledgeType.text => Icons.edit_note_rounded,
  };

  static IconData notification(NotificationType t) => switch (t) {
    NotificationType.hotLead => Icons.local_fire_department_rounded,
    NotificationType.followUpReady => Icons.chat_bubble_rounded,
    NotificationType.callback => Icons.event_rounded,
    NotificationType.campaign => Icons.campaign_rounded,
    NotificationType.newLead => Icons.bolt_rounded,
  };

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
