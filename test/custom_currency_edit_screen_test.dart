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
    expect(find.byIcon(CupertinoIcons.check_mark), findsWidgets);

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
    expect(find.text('Delete Currency'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('custom-currency-field')),
    );
    expect(field.controller!.text, 'BTC');

    await tester.tap(find.text('Delete Currency'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Delete Custom Currency?'), findsOneWidget);
    expect(find.text('Delete "BTC"? This cannot be undone.'), findsOneWidget);
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
    expect(find.byIcon(CupertinoIcons.square_pencil), findsOneWidget);
    expect(find.byTooltip('Edit BTC'), findsOneWidget);
  });

  testWidgets('picker search filters currencies by code and name', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CurrencyPickerScreen()));

    expect(find.byKey(const ValueKey('currency-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-custom-currency')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('currency-search-field')),
      'British',
    );
    await tester.pump();

    expect(find.text('GBP'), findsOneWidget);
    expect(find.text('USD'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('currency-search-field')),
      'not-a-currency',
    );
    await tester.pump();

    expect(find.text('No currencies found'), findsOneWidget);
  });

  testWidgets('picker reveals the existing selected currency on entry', (
    tester,
  ) async {
    final currency = CurrencySettingsService.instance.currency;
    final original = currency.value;
    addTearDown(() => currency.value = original);
    currency.value = 'JPY';

    await tester.pumpWidget(const MaterialApp(home: CurrencyPickerScreen()));
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('currency-options-scroll')),
    );
    expect(scrollView.controller!.offset, greaterThan(0));
  });

  testWidgets('selection keeps picker open until the user goes back', (
    tester,
  ) async {
    final currency = CurrencySettingsService.instance.currency;
    final original = currency.value;
    addTearDown(() => currency.value = original);
    currency.value = 'Rs';

    await tester.pumpWidget(const MaterialApp(home: CurrencyPickerScreen()));
    await tester.tap(find.text('USD'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(currency.value, 'USD');
    expect(find.text('Choose Currency Display'), findsOneWidget);
  });

  testWidgets('new custom currency is selected and scrolled into view', (
    tester,
  ) async {
    final service = CurrencySettingsService.instance;
    final originalCurrency = service.currency.value;
    final originalCustomCurrencies = service.customCurrencies.value;
    addTearDown(() {
      service.currency.value = originalCurrency;
      service.customCurrencies.value = originalCustomCurrencies;
    });
    service.currency.value = 'USD';
    service.customCurrencies.value = [];

    await tester.pumpWidget(const MaterialApp(home: CurrencyPickerScreen()));
    await tester.tap(find.byKey(const ValueKey('add-custom-currency')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    service.customCurrencies.value = ['XAU'];
    service.currency.value = 'XAU';
    Navigator.of(
      tester.element(find.byType(CustomCurrencyEditScreen)),
    ).pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final pickerScroll = find.byKey(const ValueKey('currency-options-scroll'));
    expect(pickerScroll, findsOneWidget);
    final scrollView = tester.widget<SingleChildScrollView>(pickerScroll);
    expect(service.currency.value, 'XAU');
    expect(find.text('Choose Currency Display'), findsOneWidget);
    expect(
      scrollView.controller!.offset,
      closeTo(scrollView.controller!.position.maxScrollExtent, 0.1),
    );
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
