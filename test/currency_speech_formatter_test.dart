import 'package:budget_ai/src/chat/currency_speech_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expands rupee and dollar amounts into readable English', () {
    expect(
      expandCurrencyAmountsForSpeech('Logged Rs 250 and \$2.5.'),
      'Logged two hundred and fifty rupees and two point five dollars.',
    );
    expect(
      expandCurrencyAmountsForSpeech('1 rupee, 1 USD, and 1,250 PKR'),
      'one rupee, one dollar, and one thousand two hundred and fifty rupees',
    );
  });

  test('uses Urdu currency names when the response is Urdu script', () {
    expect(
      expandCurrencyAmountsForSpeech('خرچہ Rs 250 اور \$2.5 درج ہوا'),
      'خرچہ دو سو پچاس روپے اور دو اعشاریہ پانچ ڈالر درج ہوا',
    );
  });

  test('uses Roman Urdu number words for Roman Urdu responses', () {
    expect(
      expandCurrencyAmountsForSpeech(
        'Aap ka Rs 250 ka kharcha darj hua hai.',
        languageCode: 'ur-PK',
      ),
      'Aap ka do sau pachaas rupees ka kharcha darj hua hai.',
    );
  });

  test('leaves unrelated numbers unchanged', () {
    expect(
      expandCurrencyAmountsForSpeech('There are 5 entries on 19 August.'),
      'There are 5 entries on 19 August.',
    );
  });
}
