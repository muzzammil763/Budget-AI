/// Expands common rupee and dollar amounts into speech-friendly prose.
///
/// This intentionally targets only amounts next to an explicit currency marker
/// so ordinary dates, counts, and finance tables are left unchanged.
String expandCurrencyAmountsForSpeech(String text, {String? languageCode}) {
  var result = text;
  final hasUrduScript = RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  if (hasUrduScript) {
    result = _expandUrduCurrency(result, r'PKR|Rs\.?|₨|روپے?', 'روپے');
    result = _expandUrduCurrency(result, r'USD|dollars?|\$|ڈالر', 'ڈالر');
    return result;
  }

  final useRomanUrdu =
      _looksLikeRomanUrdu(text) ||
      (languageCode?.toLowerCase().startsWith('ur') ?? false);
  for (final currency in _currencies) {
    final marker = currency.pattern;
    result = result.replaceAllMapped(
      RegExp(
        '(?:$marker)\\s*([+-]?[0-9][0-9,]*(?:\\.[0-9]+)?)',
        caseSensitive: false,
      ),
      (match) => _spokenAmount(match.group(1)!, currency, useRomanUrdu),
    );
    result = result.replaceAllMapped(
      RegExp(
        '([+-]?[0-9][0-9,]*(?:\\.[0-9]+)?)\\s*(?:$marker)',
        caseSensitive: false,
      ),
      (match) => _spokenAmount(match.group(1)!, currency, useRomanUrdu),
    );
  }
  return result;
}

String _expandUrduCurrency(String text, String marker, String currency) {
  var result = text.replaceAllMapped(
    RegExp(
      '(?:$marker)\\s*([+-]?[0-9][0-9,]*(?:\\.[0-9]+)?)',
      caseSensitive: false,
    ),
    (match) => '${_decimalToUrduWords(match.group(1)!)} $currency',
  );
  result = result.replaceAllMapped(
    RegExp(
      '([+-]?[0-9][0-9,]*(?:\\.[0-9]+)?)\\s*(?:$marker)',
      caseSensitive: false,
    ),
    (match) => '${_decimalToUrduWords(match.group(1)!)} $currency',
  );
  return result;
}

String _decimalToUrduWords(String value) {
  final normalized = value.replaceAll(',', '');
  final negative = normalized.startsWith('-');
  final parts = normalized.replaceFirst(RegExp(r'^[+-]'), '').split('.');
  var words = _integerToUrduWords(int.tryParse(parts.first) ?? 0);
  if (parts.length > 1 && parts[1].isNotEmpty) {
    final decimals = parts[1]
        .split('')
        .map((digit) => _urduOnes[int.parse(digit)])
        .join(' ');
    words = '$words اعشاریہ $decimals';
  }
  return negative ? 'منفی $words' : words;
}

String _integerToUrduWords(int value) {
  if (value < 100) return _urduBelowHundred[value];
  if (value < 1000) {
    final remainder = value % 100;
    return '${_urduOnes[value ~/ 100]} سو'
        '${remainder == 0 ? '' : ' ${_integerToUrduWords(remainder)}'}';
  }
  const scales = <({int value, String name})>[
    (value: 1000000000, name: 'ارب'),
    (value: 10000000, name: 'کروڑ'),
    (value: 100000, name: 'لاکھ'),
    (value: 1000, name: 'ہزار'),
  ];
  for (final scale in scales) {
    if (value >= scale.value) {
      final remainder = value % scale.value;
      return '${_integerToUrduWords(value ~/ scale.value)} ${scale.name}'
          '${remainder == 0 ? '' : ' ${_integerToUrduWords(remainder)}'}';
    }
  }
  return value.toString();
}

const _currencies = <_SpeechCurrency>[
  _SpeechCurrency(r'PKR|Rs\.?|₨|rupees?', 'rupee', 'rupees'),
  _SpeechCurrency(r'USD|\$|dollars?', 'dollar', 'dollars'),
];

class _SpeechCurrency {
  const _SpeechCurrency(this.pattern, this.singular, this.plural);

  final String pattern;
  final String singular;
  final String plural;
}

String _spokenAmount(
  String rawAmount,
  _SpeechCurrency currency,
  bool useRomanUrdu,
) {
  final normalized = rawAmount.replaceAll(',', '');
  final value = double.tryParse(normalized);
  if (value == null) return rawAmount;
  final words = useRomanUrdu
      ? _decimalToRomanUrduWords(normalized)
      : _decimalToWords(normalized);
  final unit = value.abs() == 1 ? currency.singular : currency.plural;
  return '$words $unit';
}

bool _looksLikeRomanUrdu(String text) {
  final matches = RegExp(
    r'\b(?:aap|ap|ka|ki|ke|ko|mein|main|hai|he|hain|hua|huwa|gaya|gayi|'
    r'kya|ye|yeh|aur|or|neeche|dekhein|dekh|kharche?|jama|darj)\b',
    caseSensitive: false,
  ).allMatches(text).length;
  return matches >= 2;
}

String _decimalToRomanUrduWords(String value) {
  final negative = value.startsWith('-');
  final unsigned = value.replaceFirst(RegExp(r'^[+-]'), '');
  final parts = unsigned.split('.');
  final integer = int.tryParse(parts.first) ?? 0;
  var words = _integerToRomanUrduWords(integer);
  if (parts.length > 1 && parts[1].isNotEmpty) {
    final decimals = parts[1]
        .split('')
        .map((digit) => _romanUrduOnes[int.parse(digit)])
        .join(' ');
    words = '$words point $decimals';
  }
  return negative ? 'minus $words' : words;
}

String _integerToRomanUrduWords(int value) {
  if (value < 100) return _romanUrduBelowHundred[value];
  if (value < 1000) {
    final remainder = value % 100;
    return '${_romanUrduOnes[value ~/ 100]} sau'
        '${remainder == 0 ? '' : ' ${_integerToRomanUrduWords(remainder)}'}';
  }
  const scales = <({int value, String name})>[
    (value: 1000000000, name: 'arab'),
    (value: 10000000, name: 'crore'),
    (value: 100000, name: 'lakh'),
    (value: 1000, name: 'hazaar'),
  ];
  for (final scale in scales) {
    if (value >= scale.value) {
      final remainder = value % scale.value;
      return '${_integerToRomanUrduWords(value ~/ scale.value)} ${scale.name}'
          '${remainder == 0 ? '' : ' ${_integerToRomanUrduWords(remainder)}'}';
    }
  }
  return value.toString();
}

String _decimalToWords(String value) {
  final negative = value.startsWith('-');
  final unsigned = value.replaceFirst(RegExp(r'^[+-]'), '');
  final parts = unsigned.split('.');
  final integer = int.tryParse(parts.first) ?? 0;
  var words = _integerToWords(integer);
  if (parts.length > 1 && parts[1].isNotEmpty) {
    final decimals = parts[1]
        .split('')
        .map((digit) => _ones[int.parse(digit)])
        .join(' ');
    words = '$words point $decimals';
  }
  return negative ? 'minus $words' : words;
}

String _integerToWords(int value) {
  if (value == 0) return 'zero';
  if (value < 20) return _ones[value];
  if (value < 100) {
    final remainder = value % 10;
    return remainder == 0
        ? _tens[value ~/ 10]
        : '${_tens[value ~/ 10]}-${_ones[remainder]}';
  }
  if (value < 1000) {
    final remainder = value % 100;
    return '${_ones[value ~/ 100]} hundred${remainder == 0 ? '' : ' and ${_integerToWords(remainder)}'}';
  }
  for (final scale in _scales) {
    if (value >= scale.value) {
      final remainder = value % scale.value;
      final separator = remainder > 0 && remainder < 100 ? ' and ' : ' ';
      return '${_integerToWords(value ~/ scale.value)} ${scale.name}'
          '${remainder == 0 ? '' : '$separator${_integerToWords(remainder)}'}';
    }
  }
  return value.toString();
}

const _ones = <String>[
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];

const _tens = <String>[
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

const _scales = <({int value, String name})>[
  (value: 1000000000000, name: 'trillion'),
  (value: 1000000000, name: 'billion'),
  (value: 1000000, name: 'million'),
  (value: 1000, name: 'thousand'),
];

const _romanUrduOnes = <String>[
  'zero',
  'aik',
  'do',
  'teen',
  'chaar',
  'paanch',
  'chay',
  'saat',
  'aath',
  'nau',
];

const _romanUrduBelowHundred = <String>[
  'zero',
  'aik',
  'do',
  'teen',
  'chaar',
  'paanch',
  'chay',
  'saat',
  'aath',
  'nau',
  'das',
  'gyarah',
  'barah',
  'terah',
  'chaudah',
  'pandrah',
  'solah',
  'satrah',
  'atharah',
  'unnees',
  'bees',
  'ikkees',
  'baees',
  'teees',
  'chaubees',
  'pachees',
  'chhabbees',
  'sattaees',
  'atthaees',
  'untees',
  'tees',
  'iktees',
  'battees',
  'taintees',
  'chauntees',
  'paintees',
  'chhattees',
  'saintees',
  'artees',
  'untalees',
  'chalees',
  'iktalees',
  'bayalees',
  'taintalees',
  'chawalees',
  'paintalees',
  'chhiyalees',
  'saintalees',
  'artalees',
  'unchaas',
  'pachaas',
  'ikyawan',
  'bawan',
  'tirpan',
  'chawan',
  'pachpan',
  'chhappan',
  'satawan',
  'atthawan',
  'unsath',
  'saath',
  'iksath',
  'basath',
  'tirsath',
  'chaunsath',
  'painsath',
  'chhiyasath',
  'sarsath',
  'arsath',
  'unhattar',
  'sattar',
  'ikhattar',
  'bahattar',
  'tihattar',
  'chauhattar',
  'pachhattar',
  'chhihattar',
  'satahattar',
  'athahattar',
  'unasi',
  'assi',
  'ikyasi',
  'bayasi',
  'tirasi',
  'chaurasi',
  'pachasi',
  'chhiyasi',
  'sataasi',
  'athaasi',
  'navasi',
  'nabbe',
  'ikyanave',
  'banave',
  'tiranave',
  'chauranave',
  'pachanave',
  'chhiyanave',
  'satanave',
  'athanave',
  'ninyanave',
];

const _urduOnes = <String>[
  'صفر',
  'ایک',
  'دو',
  'تین',
  'چار',
  'پانچ',
  'چھ',
  'سات',
  'آٹھ',
  'نو',
];

const _urduBelowHundred = <String>[
  'صفر',
  'ایک',
  'دو',
  'تین',
  'چار',
  'پانچ',
  'چھ',
  'سات',
  'آٹھ',
  'نو',
  'دس',
  'گیارہ',
  'بارہ',
  'تیرہ',
  'چودہ',
  'پندرہ',
  'سولہ',
  'سترہ',
  'اٹھارہ',
  'انیس',
  'بیس',
  'اکیس',
  'بائیس',
  'تئیس',
  'چوبیس',
  'پچیس',
  'چھبیس',
  'ستائیس',
  'اٹھائیس',
  'انتیس',
  'تیس',
  'اکتیس',
  'بتیس',
  'تینتیس',
  'چونتیس',
  'پینتیس',
  'چھتیس',
  'سینتیس',
  'اڑتیس',
  'انتالیس',
  'چالیس',
  'اکتالیس',
  'بیالیس',
  'تینتالیس',
  'چوالیس',
  'پینتالیس',
  'چھیالیس',
  'سینتالیس',
  'اڑتالیس',
  'انچاس',
  'پچاس',
  'اکیاون',
  'باون',
  'ترپن',
  'چَوّن',
  'پچپن',
  'چھپن',
  'ستاون',
  'اٹھاون',
  'انسٹھ',
  'ساٹھ',
  'اکسٹھ',
  'باسٹھ',
  'تریسٹھ',
  'چونسٹھ',
  'پینسٹھ',
  'چھیاسٹھ',
  'سڑسٹھ',
  'اڑسٹھ',
  'انہتر',
  'ستر',
  'اکہتر',
  'بہتر',
  'تہتر',
  'چوہتر',
  'پچہتر',
  'چھہتر',
  'ستتر',
  'اٹھہتر',
  'اناسی',
  'اسی',
  'اکیاسی',
  'بیاسی',
  'تراسی',
  'چوراسی',
  'پچاسی',
  'چھیاسی',
  'ستاسی',
  'اٹھاسی',
  'نواسی',
  'نوے',
  'اکیانوے',
  'بانوے',
  'ترانوے',
  'چورانوے',
  'پچانوے',
  'چھیانوے',
  'ستانوے',
  'اٹھانوے',
  'ننانوے',
];
