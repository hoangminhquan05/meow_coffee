import 'package:intl/intl.dart';

String formatVnd(num amount, {String suffix = 'VND'}) {
  final formatted =
      NumberFormat('#,##0', 'en_US').format(amount).replaceAll(',', '.');
  return '$formatted $suffix';
}

/// "25.000đ"
String formatMoney(num amount) => formatVnd(amount, suffix: 'đ').replaceAll(' đ', 'đ');

/// "22/11/2026 08:15"
String formatDateTime(DateTime? dt) =>
    dt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(dt);

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
