// Pins RoyalButton's variant styling and merge behavior so the shared
// button component can't silently drift from the app's button hierarchy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/theme_constants.dart';
import 'package:royal_frame/widgets/royal_button.dart';

Future<void> pumpButton(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('primary renders a FilledButton and fires onPressed once',
      (tester) async {
    var presses = 0;
    await pumpButton(
      tester,
      RoyalButton(label: 'Go', onPressed: () => presses++),
    );
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(presses, 1);
  });

  testWidgets(
      'emphasized keeps gold tint fill and 1.5 border when geometry knobs are set',
      (tester) async {
    await pumpButton(
      tester,
      RoyalButton(
        label: 'Try Again',
        icon: Icons.refresh,
        variant: RoyalButtonVariant.emphasized,
        expand: true,
        minHeight: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        onPressed: () {},
      ),
    );
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    final style = button.style!;
    expect(style.backgroundColor!.resolve({}), kGoldTintBg,
        reason: 'geometry knobs must not clobber the variant fill');
    expect(style.side!.resolve({})!.width, 1.5);
    expect(style.side!.resolve({})!.color, kGold);
    expect(style.minimumSize!.resolve({}), const Size(0, 52));
    expect(
      style.padding!.resolve({}),
      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
    expect(style.textStyle!.resolve({})!.fontSize, 16);
  });

  testWidgets('secondary is a gold 1.5 outline with bold label',
      (tester) async {
    await pumpButton(
      tester,
      RoyalButton(
        label: 'Share',
        variant: RoyalButtonVariant.secondary,
        onPressed: () {},
      ),
    );
    final style =
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!;
    expect(style.backgroundColor, isNull);
    expect(style.side!.resolve({})!.width, 1.5);
    expect(style.textStyle!.resolve({})!.fontWeight, FontWeight.bold);
  });

  testWidgets('tertiary is a plain TextButton with 13pt label and 16 icons',
      (tester) async {
    await pumpButton(
      tester,
      RoyalButton(
        label: 'Main Menu',
        icon: Icons.home_outlined,
        variant: RoyalButtonVariant.tertiary,
        onPressed: () {},
      ),
    );
    final style = tester.widget<TextButton>(find.byType(TextButton)).style!;
    expect(style.foregroundColor!.resolve({}), kGoldLight);
    expect(style.textStyle!.resolve({})!.fontSize, 13);
    expect(style.iconSize!.resolve({}), 16);
  });

  testWidgets('null onPressed renders a disabled button with no press scale',
      (tester) async {
    await pumpButton(tester, const RoyalButton(label: 'Locked'));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.press(find.byType(RoyalButton));
    await tester.pump(kDurFast);
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.0);
  });

  testWidgets('press scales down to 0.96 and springs back on release',
      (tester) async {
    await pumpButton(
      tester,
      RoyalButton(label: 'Press me', onPressed: () {}),
    );
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(RoyalButton)));
    await tester.pump();
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.96);

    await gesture.up();
    await tester.pump();
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await tester.pumpAndSettle();
  });
}
