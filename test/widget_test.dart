import 'package:flutter_test/flutter_test.dart';

import 'package:pamg_lab_ek1/main.dart';

void main() {
  testWidgets('Ekran logowania się wyświetla', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Logowanie'), findsOneWidget);
  });
}