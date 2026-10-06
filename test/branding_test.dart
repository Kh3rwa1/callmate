import 'dart:io';

import 'package:callpilot/core/config/brand.dart';
import 'package:callpilot/data/datasources/mock/mock_backend.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/templates/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Brand', () {
    test('exact product name, tagline, description', () {
      expect(Brand.appName, 'CallPilot');
      expect(APP_NAME, 'CallPilot');
      expect(Brand.tagline, 'Your AI Calling Employee');
      expect(Brand.description, 'AI that calls, qualifies, and follows up for your business.');
    });

    test('package id stays com.lexi.light; launcher label is CallPilot', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.lexi.light"'));
      expect(gradle, contains('namespace = "com.lexi.light"'));
      expect(File('android/app/src/main/kotlin/com/lexi/light/MainActivity.kt').readAsStringSync(), startsWith('package com.lexi.light'));
      expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), contains('android:label="CallPilot"'));
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = com\.lexi\.light;').allMatches(pbx).length, 3);
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<string>CallPilot</string>'));
    });

    test('no forbidden product branding in app sources', () {
      final forbidden = [RegExp('Riya AI'), RegExp('riyaai'), RegExp('CALLPILOT'), RegExp(r'\bLexi\b'), RegExp('Call Pilot')];
      final files = [
        ...Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')),
        File('android/app/src/main/AndroidManifest.xml'),
        File('ios/Runner/Info.plist'),
        File('web/index.html'),
        File('web/manifest.json'),
      ];
      for (final f in files) {
        final s = f.readAsStringSync();
        for (final r in forbidden) {
          expect(r.hasMatch(s), isFalse, reason: '${f.path} contains ${r.pattern}');
        }
      }
    });
  });

  group('Templates', () {
    test('every business category has a template with an employee', () {
      for (final c in BusinessCategory.values) {
        final t = templateFor(c);
        expect(t.category, c);
        expect(t.agent.role, isNotEmpty);
        expect(t.workflow.interestLabel, isNotEmpty);
      }
    });

    test('skills drive the suggested role', () {
      final base = templateFor(BusinessCategory.realEstate);
      expect(agentForSkills(base, {EmployeeSkill.sales}).role, 'Sales Assistant');
      expect(agentForSkills(base, {EmployeeSkill.bookAppointments}).role, 'Appointment Assistant');
      expect(agentForSkills(base, {EmployeeSkill.admissions}).role, 'Admissions Assistant');
      expect(EmployeeRoleKind.fromRole('Sales Assistant'), EmployeeRoleKind.sales);
    });

    test('lead is generic with custom attributes + legacy payload support', () {
      final legacy = Lead.fromJson({'id': '1', 'course_interest': 'NEET', 'preferred_batch': 'Evening', 'budget': '50000'});
      expect(legacy.interest, 'NEET');
      expect(legacy.attributes, {'batch': 'Evening', 'budget': '50000'});
      expect(legacy.interestLine, 'NEET · Evening');
      final re = Lead.fromJson({
        'id': '2',
        'interest': '3 BHK',
        'attributes': {'location': 'Salt Lake'},
      });
      expect(re.interestLine, '3 BHK · Salt Lake');
      expect(NextAction.parse('counsellor_callback'), NextAction.humanFollowUp);
    });
  });

  group('Demo tenant is configurable, not the brand', () {
    test('Maya @ real-estate tenant works end-to-end in the mock pipeline', () {
      final b = MockBackend(
        business: const Business(id: 'b', name: 'Sharma Realty', category: BusinessCategory.realEstate),
        agent: const Agent(id: 'a', name: 'Maya', role: 'Sales Assistant', status: AgentStatus.active, templateId: 'generic_sales_v1'),
      );
      final call = b.simulateCall(LeadTemperature.hot);
      expect(call.transcript.lines.first.text, contains('Maya'));
      expect(call.transcript.lines.first.text, contains('Sharma Realty'));
      expect(call.transcript.lines.map((l) => l.text).join(' '), isNot(contains('NEET')));
      final fu = b.followUps[call.followUpId]!;
      expect(fu.message, contains('Sharma Realty'));
      b.dispose();
    });
  });
}
