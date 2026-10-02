import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:book_ai_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E2E Smoke Test: App Starts and Navigates', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Check if Login Screen or Home Screen is visible
    expect(find.textContaining('Libris'), findsWidgets);
  });
}
