import 'dart:async';
import 'dart:ui' show PictureRecorder;

import 'package:callpilot/core/motion/motion.dart';
import 'package:callpilot/core/providers.dart';
import 'package:callpilot/core/theme/app_glyphs.dart';
import 'package:callpilot/core/theme/app_theme.dart';
import 'package:callpilot/core/utils/format.dart';
import 'package:callpilot/core/widgets/app_card.dart';
import 'package:callpilot/core/widgets/celebration.dart';
import 'package:callpilot/core/widgets/mascot.dart';
import 'package:callpilot/core/widgets/whole_word_text.dart';
import 'package:callpilot/data/models/models.dart';
import 'package:callpilot/data/repositories/repositories.dart';
import 'package:callpilot/features/home/home_hero.dart';
import 'package:callpilot/features/home/week_funnel.dart';
import 'package:callpilot/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

final _morning = DateTime(2026, 10, 10, 11);
final _night = DateTime(2026, 10, 10, 22);

class _Events implements BackendEvents {
  final controller = StreamController<BackendEvent>.broadcast();
  @override
  Stream<BackendEvent> get stream => controller.stream;
}

Call _hotCall(String id, String leadId, {String? fu}) => Call(
  id: id,
  leadId: leadId,
  leadName: 'Ravi Kumar',
  leadPhone: '+919800000000',
  agentId: 'a1',
  status: CallStatus.completed,
  startedAt: DateTime(2026, 10, 10, 11),
  followUpId: fu,
  leadScore: const LeadScore(
    value: 90,
    temperature: LeadTemperature.hot,
    intent: LeadIntent.interested,
  ),
);

void main() {
  tearDown(MascotAssets.reset);

  group('Hero model', () {
    const s = S.en;

    test('a live call beats everything and names the customer', () {
      final m = HeroFocusl.from(
        s: s,
        now: _night,
        live: true,
        liveName: 'Ravi Kumar',
        hot: 3,
        followUps: 2,
      );
      expect(m.mode, HeroFocus.live);
      expect(m.mascot, MascotState.calling);
      expect(m.status, 'Calling Ravi…');
      expect(m.action, HeroAction.seeLive);
      expect(m.actionLabel, 'See live calls');
    });

    test('live without a known name stays generic', () {
      final m = HeroFocusl.from(s: s, now: _morning, live: true);
      expect(m.status, 'Calling your customers…');
    });

    test('hot leads come next, even outside calling hours', () {
      final m = HeroFocusl.from(s: s, now: _night, hot: 3);
      expect(m.mode, HeroFocus.hot);
      expect(m.status, '3 ready to buy');
      expect(m.action, HeroAction.seeReady);
      expect(m.actionLabel, 'See who is ready');
    });

    test('outside calling hours the employee rests', () {
      final m = HeroFocusl.from(
        s: s,
        now: _night,
        callingStart: 9,
        callingEnd: 18,
        leads: 4,
      );
      expect(m.mode, HeroFocus.resting);
      expect(m.mascot, MascotState.resting);
      expect(m.status, 'Resting – calls start at 9:00 AM');
      expect(
        HeroFocusl.from(
          s: s,
          now: DateTime(2026, 1, 1, 7),
          callingStart: 9,
        ).mode,
        HeroFocus.resting,
      );
    });

    test('otherwise ready, with the most useful next step', () {
      final ready = HeroFocusl.from(s: s, now: _morning);
      expect(ready.mode, HeroFocus.ready);
      expect(ready.mascot, MascotState.idle);
      expect(ready.status, 'Ready to call your customers');
      expect(ready.action, HeroAction.addCustomers);

      final msgs = HeroFocusl.from(s: s, now: _morning, followUps: 2);
      expect(msgs.actionLabel, 'Send 2 messages');
      final fresh = HeroFocusl.from(s: s, now: _morning, leads: 9, newLeads: 5);
      expect(fresh.action, HeroAction.callNew);
      expect(fresh.actionLabel, 'Call 5 New Customers');
    });

    test('every string exists in Hindi and Bengali', () {
      for (final lang in AppLang.values) {
        final l = S(lang);
        expect(l.heroResting('9:00 AM'), contains('9:00 AM'));
        expect(l.heroCalling('Ravi'), contains('Ravi'));
        expect(l.celebrateReady('Ravi'), contains('Ravi'));
        expect(l.funnelTalked, isNotEmpty);
        expect(l.weekCallsSemantics(3), contains('3'));
        expect(l.worthCaption(2), contains('2'));
        expect(l.gsAllSet, isNotEmpty);
      }
      expect(const S(AppLang.hi).heroEyebrow, isNot(S.en.heroEyebrow));
      expect(const S(AppLang.bn).heroEyebrow, isNot(S.en.heroEyebrow));
    });
  });

  group('Hero view', () {
    Future<void> pumpHero(WidgetTester tester, HeroFocusl m, {int? calls}) =>
        tester.pumpWidget(
          _app(
            SingleChildScrollView(
              child: HeroView(
                model: m,
                employeeName: 'Riya',
                callsToday: calls,
                onAction: () {},
              ),
            ),
          ),
        );

    for (final (name, model) in [
      ('live', HeroFocusl.from(s: S.en, now: _morning, live: true)),
      ('hot', HeroFocusl.from(s: S.en, now: _morning, hot: 2)),
      ('resting', HeroFocusl.from(s: S.en, now: _night)),
      ('ready', HeroFocusl.from(s: S.en, now: _morning)),
    ]) {
      testWidgets('$name: mascot pose, status line and one action', (
        tester,
      ) async {
        await pumpHero(tester, model, calls: 12);
        expect(find.text(model.status), findsOneWidget);
        expect(find.text(model.actionLabel), findsOneWidget);
        final mascot = tester.widget<Mascot>(find.byType(Mascot));
        expect(mascot.state, model.mascot);
        // The live state pulses; the others don't.
        expect(
          find.byType(StatusDot),
          name == 'live' ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('calls today counts up to its final value', (tester) async {
      await pumpHero(
        tester,
        HeroFocusl.from(s: S.en, now: _morning),
        calls: 1234,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1,234'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1,234'), findsOneWidget);
    });

    testWidgets('while loading it shows no misleading zero', (tester) async {
      await pumpHero(tester, HeroFocusl.from(s: S.en, now: _morning));
      expect(find.byKey(const Key('hero-calls')), findsNothing);
      expect(find.text('0'), findsNothing);
    });
  });

  group('This week funnel', () {
    test('bar widths are proportional to the widest stage', () {
      expect(funnelFractions([100, 50, 25, 0]), [1.0, 0.5, 0.25, 0.0]);
      expect(funnelFractions([0, 0, 0, 0]), [0, 0, 0, 0]);
      // A single lead still shows a sliver.
      expect(funnelFractions([1000, 1, 0, 0])[1], 0.04);
      // Later stages larger than the first never overflow the bar.
      expect(funnelFractions([2, 4, 1, 0]), [0.5, 1.0, 0.25, 0.0]);
    });

    test('calls are bucketed by local day, oldest first', () {
      final now = DateTime(2026, 10, 10, 15);
      final starts = [
        DateTime(2026, 10, 10, 9),
        DateTime(2026, 10, 10, 1),
        DateTime(2026, 10, 9, 23),
        DateTime(2026, 10, 4, 12),
        DateTime(2026, 10, 3, 12), // 7 days ago: out of range
        DateTime(2026, 10, 11, 1), // future: ignored
      ];
      expect(callsPerDay(starts, now), [1, 0, 0, 0, 0, 1, 2]);
    });

    test('sparkline points span the box, highest value at the top', () {
      final pts = SparklinePainter.points([0, 5, 10], const Size(100, 40));
      expect(pts.first.dx, 3);
      expect(pts.last.dx, 97);
      expect(pts.last.dy, 3);
      expect(pts.first.dy, 37);
      expect(SparklinePainter.points(const [], const Size(10, 10)), isEmpty);
    });

    testWidgets('card: money first, four stages, neutral delta chips', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SingleChildScrollView(
            child: WeekFunnelCard(
              results: ResultsSummary(
                range: ResultsRange.week,
                hasCalls: true,
                avgDealValueInr: 5000,
                current: PeriodResults(
                  enquiries: 40,
                  callsConnected: 20,
                  interested: 8,
                  readyToBuy: 3,
                  estimatedValueInr: 15000,
                ),
                previous: PeriodResults(
                  enquiries: 30,
                  callsConnected: 25,
                  interested: 8,
                  readyToBuy: 1,
                ),
              ),
              daily: [1, 2, 0, 4, 3, 5, 6],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(Fmt.inr(15000)), findsOneWidget);
      expect(find.text('could come from 3 ready buyers'), findsOneWidget);
      for (final l in ['Enquiries', 'Talked', 'Interested', 'Ready to buy']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(find.text('▲ 10'), findsOneWidget);
      expect(find.text('▼ 5'), findsOneWidget);
      expect(find.text('▲ 2'), findsOneWidget);
      // No change → no chip.
      expect(find.byType(DeltaChip), findsNWidgets(3));
      expect(find.byKey(const Key('sparkline')), findsOneWidget);
      expect(find.bySemanticsLabel('21 calls in the last 7 days'), findsOne);
    });
  });

  group('Mascot', () {
    testWidgets('without artwork every state is drawn with its overlay', (
      tester,
    ) async {
      MascotAssets.debugOverride = {};
      for (final st in MascotState.values) {
        await tester.pumpWidget(_app(Mascot(state: st, key: ValueKey(st))));
        await tester.pump(const Duration(milliseconds: 500));
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((c) => c.painter)
            .toList();
        expect(painters.whereType<BirdPainter>().single.state, st.pose);
        expect(painters.whereType<BirdPainter>().single.extras, isFalse);
        final overlay = painters.whereType<MascotOverlayPainter>().single;
        expect(overlay.state, st);
        expect(find.byType(Image), findsNothing);
      }
    });

    test('each state has its own overlay; idle stays bare', () {
      final parts = {
        for (final s in MascotState.values) s: MascotOverlayPainter.partsFor(s),
      };
      expect(parts[MascotState.idle], isEmpty);
      expect(parts[MascotState.calling], [
        MascotOverlayPart.handset,
        MascotOverlayPart.soundWaves,
      ]);
      expect(parts[MascotState.celebrating], [MascotOverlayPart.confetti]);
      expect(parts[MascotState.resting], [MascotOverlayPart.sleepZs]);
      expect(parts[MascotState.thinking], [MascotOverlayPart.thoughtDots]);
      expect(parts[MascotState.waving], [MascotOverlayPart.motionLines]);
      // Overlays never repeat across states.
      final all = parts.values.expand((p) => p).toList();
      expect(all.toSet().length, all.length);
    });

    test('overlay painter paints every state without throwing', () {
      for (final st in MascotState.values) {
        for (final moving in [true, false]) {
          final rec = PictureRecorderCanvas();
          MascotOverlayPainter(
            state: st,
            t: 1.3,
            moving: moving,
          ).paint(rec.canvas, const Size(120, 120));
          BirdPainter(
            state: st.pose,
            t: 1.3,
            moving: moving,
            extras: false,
          ).paint(rec.canvas, const Size(120, 120));
          rec.dispose();
        }
      }
      for (final pose in BirdPose.values) {
        final rec = PictureRecorderCanvas();
        BirdPainter(state: pose, t: 2.1).paint(rec.canvas, const Size(80, 80));
        rec.dispose();
      }
    });

    testWidgets('artwork for a state replaces the drawing', (tester) async {
      MascotAssets.debugOverride = {MascotState.resting.asset};
      await tester.pumpWidget(_app(const Mascot(state: MascotState.resting)));
      await tester.pump();
      final img = tester.widget<Image>(find.byType(Image));
      expect((img.image as AssetImage).assetName, 'assets/mascot/resting.png');
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is MascotOverlayPainter,
        ),
        findsNothing,
      );

      // A state without its own file still falls back to the drawing.
      await tester.pumpWidget(_app(const Mascot(state: MascotState.waving)));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('reads the asset manifest when nothing is overridden', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const Mascot(state: MascotState.idle)));
      await tester.runAsync(() => MascotAssets.load());
      await tester.pump();
      // The repo ships no pose files yet, so the drawing is used.
      expect(MascotAssets.has(MascotState.idle), isFalse);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('reduce motion: a still frame, no running animations', (
      tester,
    ) async {
      MascotAssets.debugOverride = {};
      for (final st in MascotState.values) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _app(Mascot(state: st, key: ValueKey(st)), reduced: true),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.hasRunningAnimations, isFalse, reason: '$st');
        final overlay = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((c) => c.painter)
            .whereType<MascotOverlayPainter>()
            .single;
        expect(overlay.moving, isFalse);
        final t0 = overlay.t;
        await tester.pump(const Duration(seconds: 1));
        final again = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((c) => c.painter)
            .whereType<MascotOverlayPainter>()
            .single;
        expect(again.t, t0);
      }
      // With motion on, the mascot animates.
      await tester.pumpWidget(_app(const Mascot(state: MascotState.idle)));
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
    });
  });

  group('Delight', () {
    testWidgets('ready-to-buy celebrates once per lead, then goes', (
      tester,
    ) async {
      MascotAssets.debugOverride = {};
      final events = _Events();
      addTearDown(events.controller.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendEventsProvider.overrideWithValue(events)],
          child: _app(const HotLeadCelebrator(child: SizedBox.expand())),
        ),
      );
      events.controller.add(
        CallCompletedEvent(_hotCall('c1', 'l1', fu: 'fu1'), null),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('celebration')), findsOneWidget);
      expect(find.text('Ravi is ready to buy!'), findsOneWidget);
      expect(find.byType(ConfettiBurst), findsOneWidget);

      // Gone within 1.2 s.
      await tester.pump(HotLeadCelebrator.showFor);
      await tester.pump();
      expect(find.byKey(const Key('celebration')), findsNothing);

      // The push for the same lead, and a second call with the same lead,
      // don't celebrate again.
      events.controller
        ..add(
          NotificationEvent(
            AppNotification(
              id: 'n1',
              type: NotificationType.hotLead,
              title: 'Ready',
              body: '',
              route: '/followups/fu1',
              createdAt: DateTime(2026),
            ),
          ),
        )
        ..add(CallCompletedEvent(_hotCall('c2', 'l1'), null));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('celebration')), findsNothing);

      // A different lead does.
      events.controller.add(CallCompletedEvent(_hotCall('c3', 'l2'), null));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('celebration')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    test('only ready-to-buy moments count', () {
      final warm = Call(
        id: 'c',
        leadId: 'l',
        leadName: 'A',
        leadPhone: '1',
        agentId: 'a',
        status: CallStatus.completed,
        startedAt: DateTime(2026),
      );
      expect(hotMomentFor(CallCompletedEvent(warm, null)), isNull);
      expect(hotMomentFor(const DataChangedEvent('leads')), isNull);
      final m = hotMomentFor(
        NotificationEvent(
          AppNotification(
            id: 'n',
            type: NotificationType.hotLead,
            title: '',
            body: '',
            route: '/leads/l9',
            createdAt: DateTime(2026),
          ),
        ),
      );
      expect(m!.keys, contains('lead:l9'));
      final ledger = CelebrationLedger();
      expect(ledger.claim(['a', 'b']), isTrue);
      expect(ledger.claim(['b', 'c']), isFalse);
      expect(ledger.claim(['c']), isFalse);
    });

    testWidgets('reduce motion: celebration is a still card', (tester) async {
      MascotAssets.debugOverride = {};
      await tester.pumpWidget(
        _app(const CelebrationToast(name: 'Ravi'), reduced: true),
      );
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsNothing);
      expect(find.byType(PopIn), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.text('Ravi is ready to buy!'), findsOneWidget);
    });

    testWidgets('call placed: rings ripple once, never under reduce motion', (
      tester,
    ) async {
      Widget burst(int n, {bool reduced = false}) => _app(
        RingBurst(trigger: n, child: const SizedBox(width: 48, height: 48)),
        reduced: reduced,
      );
      await tester.pumpWidget(burst(0));
      expect(find.byKey(const Key('ring-burst')), findsNothing);
      await tester.pumpWidget(burst(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('ring-burst')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('ring-burst')), findsNothing);

      await tester.pumpWidget(burst(1, reduced: true));
      await tester.pumpWidget(burst(2, reduced: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('ring-burst')), findsNothing);
    });
  });

  group('Icons & text helpers', () {
    testWidgets('every glyph is an SVG asset with the icon theme colour', (
      tester,
    ) async {
      for (final g in AppGlyphs.values) {
        await tester.pumpWidget(
          _app(
            IconTheme(
              data: const IconThemeData(color: Colors.red, size: 30),
              child: AppGlyph(g, semanticLabel: g.name),
            ),
          ),
        );
        final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(svg.width, 30);
        expect(
          svg.colorFilter,
          const ColorFilter.mode(Colors.red, BlendMode.srcIn),
        );
        expect(find.bySemanticsLabel(g.name), findsOneWidget);
        expect(g.asset, 'assets/icons/${g.name}.svg');
      }
    });

    test('numbers never break across lines', () {
      expect(keepNumbersTogether('64,358 min left'), '64,⁠358 min left');
      expect(keepNumbersTogether('a, b'), 'a, b');
    });

    test('whole words: shrink only when a word would not fit', () {
      const style = TextStyle(fontSize: 20);
      expect(
        WholeWordText.fitScale('Hi there', style, 500, 1.4, TextDirection.ltr),
        1.4,
      );
      final s = WholeWordText.fitScale(
        'Automobile',
        style,
        60,
        2.0,
        TextDirection.ltr,
      );
      expect(s, lessThan(2.0));
      expect(s, greaterThan(0));
    });
  });
}

/// A throwaway canvas for painting painters directly.
class PictureRecorderCanvas {
  PictureRecorderCanvas() : _rec = PictureRecorder() {
    canvas = Canvas(_rec);
  }
  final PictureRecorder _rec;
  late final Canvas canvas;
  void dispose() => _rec.endRecording().dispose();
}
