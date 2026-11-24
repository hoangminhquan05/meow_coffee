/// Chuẩn hoá SĐT Việt Nam.
/// "0901 234 567" / "84901234567" / "+84901234567" → "+84901234567".
/// Trả về null nếu không phải SĐT di động VN hợp lệ (10 số, đầu 03/05/07/08/09).
String? toE164Vn(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+84')) {
    digits = '0${digits.substring(3)}';
  } else if (digits.startsWith('84') && digits.length == 11) {
    digits = '0${digits.substring(2)}';
  }
  if (!RegExp(r'^0[35789]\d{8}$').hasMatch(digits)) return null;
  return '+84${digits.substring(1)}';
}

/// "+84901234567" → "0901 234 567" để hiển thị.
String formatVnPhone(String e164OrLocal) {
  final e164 = toE164Vn(e164OrLocal);
  if (e164 == null) return e164OrLocal;
  final local = '0${e164.substring(3)}';
  return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
}
