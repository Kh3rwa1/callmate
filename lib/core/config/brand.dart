/// Central product branding. CallPilot is the PRODUCT.
///
/// AI employees (Riya, Maya, Arjun…) are created by customers inside
/// CallPilot and are NEVER the product brand. Never hardcode an employee
/// name in UI – always read it from the Agent.
///
/// Note: the technical package id is `com.echoing.heights` (Android
/// applicationId/namespace + iOS bundle id).
class Brand {
  const Brand._();

  static const String appName = 'CallPilot';
  static const String tagline = 'Your AI Calling Employee';
  static const String description =
      'AI that calls, qualifies, and follows up for your business.';

  /// Fallbacks only used while the employee is still loading.
  static const String employeeFallbackName = 'Your AI employee';
  static const String employeeNoun = 'AI employee';
}

// ignore: constant_identifier_names
const String APP_NAME = Brand.appName;
// ignore: constant_identifier_names
const String APP_TAGLINE = Brand.tagline;
// ignore: constant_identifier_names
const String APP_DESCRIPTION = Brand.description;
