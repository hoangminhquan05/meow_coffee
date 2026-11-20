import 'package:intl/intl.dart';

String formatVnd(double amount, {String suffix = 'VND'}) {
  final formatted =
      NumberFormat('#,##0', 'en_US').format(amount).replaceAll(',', '.');
  return '$formatted $suffix';
}

/// Removes Vietnamese diacritics and converts to lowercase for accent-insensitive search.
String normalizeVietnamese(String input) {
  const withDiacritics =
      'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
      'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
  const withoutDiacritics =
      'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
      'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';

  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    final index = withDiacritics.indexOf(char);
    buffer.write(index >= 0 ? withoutDiacritics[index] : char);
  }
  return buffer.toString().toLowerCase();
}
