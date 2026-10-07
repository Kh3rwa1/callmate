import 'package:callpilot/services/whatsapp/whatsapp_service.dart';

/// Records WhatsApp handoffs instead of launching anything.
class FakeWhatsAppService implements WhatsAppService {
  FakeWhatsAppService({this.result = WhatsAppOpenResult.opened});

  WhatsAppOpenResult result;
  final opened = <({String phone, String message})>[];
  final copied = <String>[];
  final shared = <String>[];

  @override
  Future<WhatsAppOpenResult> openChat({
    required String phone,
    required String message,
  }) async {
    opened.add((phone: phone, message: message));
    return result;
  }

  @override
  Future<void> copyMessage(String message) async => copied.add(message);

  @override
  Future<void> shareMessage(String message) async => shared.add(message);
}
