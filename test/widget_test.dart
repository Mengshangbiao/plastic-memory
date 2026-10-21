import 'package:flutter_test/flutter_test.dart';

import 'package:plastic_memory/main.dart';

void main() {
  testWidgets('首页显示可塑性记忆菜单', (WidgetTester tester) async {
    await tester.pumpWidget(const PlasticMemoryApp());
    expect(find.text('可塑性记忆'), findsOneWidget);
    expect(find.text('纷乱回忆'), findsOneWidget);
    expect(find.text('创造回忆'), findsOneWidget);
  });
}
