import 'package:budget_ai/src/settings/currency_picker_screen.dart';
import 'package:budget_ai/src/settings/currency_settings_service.dart';
import 'package:budget_ai/src/settings/custom_currency_edit_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add form uses a large field limited to five characters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CustomCurrencyEditScreen()),
    );

    expect(find.text('Add Custom Currency'), findsOneWidget);
    expect(find.text('Add Currency'), findsOneWidget);
    expect(find.byIcon(Icons.save_outlined), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('custom-currency-field')),
      'ABCDEF',
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('custom-currency-field')),
    );
    expect(field.controller!.text, 'ABCDE');
    expect(field.style!.fontSize, 44);
  });

  testWidgets('edit form starts with the saved custom currency', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CustomCurrencyEditScreen(currency: 'BTC')),
    );

    expect(find.text('Edit Custom Currency'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('custom-currency-field')),
    );
    expect(field.controller!.text, 'BTC');
  });

  testWidgets('picker exposes add and edit actions for custom currencies', (
    tester,
  ) async {
    final currencies = CurrencySettingsService.instance.customCurrencies;
    final original = currencies.value;
    addTearDown(() => currencies.value = original);
    currencies.value = ['BTC'];

    await tester.pumpWidget(const MaterialApp(home: CurrencyPickerScreen()));

    expect(find.byTooltip('Add custom currency'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.pencil), findsOneWidget);
    expect(find.byTooltip('Edit BTC'), findsOneWidget);
  });

  test('custom currency validation rejects long and duplicate values', () {
    final service = CurrencySettingsService.instance;
    final original = service.customCurrencies.value;
    addTearDown(() => service.customCurrencies.value = original);
    service.customCurrencies.value = ['BTC'];

    expect(service.customCurrencyValidationError(''), isNotNull);
    expect(service.customCurrencyValidationError('ABCDEF'), isNotNull);
    expect(service.customCurrencyValidationError('USD'), isNotNull);
    expect(service.customCurrencyValidationError('btc'), isNotNull);
    expect(
      service.customCurrencyValidationError('btc', originalValue: 'BTC'),
      isNull,
    );
    expect(service.customCurrencyValidationError('XAU'), isNull);
  });
}
