import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:steam_achievements_apk/main.dart';

void main() {
  testWidgets('app smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SteamTrophiesApp());
    await tester.pumpAndSettle();

    expect(find.text('Steam Achievements'), findsOneWidget);
  });
}
