import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Khoảng thời gian [from, to) theo ngày.
class DayRange {
  final DateTime from;
  final DateTime to;

  const DayRange(this.from, this.to);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory DayRange.today() {
    final start = _day(DateTime.now());
    return DayRange(start, start.add(const Duration(days: 1)));
  }

  factory DayRange.lastDays(int days) {
    final end = _day(DateTime.now()).add(const Duration(days: 1));
    return DayRange(end.subtract(Duration(days: days)), end);
  }

  factory DayRange.thisMonth() {
    final now = DateTime.now();
    return DayRange(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
  }

  factory DayRange.fromPicker(DateTimeRange r) =>
      DayRange(_day(r.start), _day(r.end).add(const Duration(days: 1)));

  String get label {
    final f = DateFormat('dd/MM/yyyy');
    final lastDay = to.subtract(const Duration(days: 1));
    return _day(from) == _day(lastDay)
        ? f.format(from)
        : '${f.format(from)} – ${f.format(lastDay)}';
  }

  @override
  bool operator ==(Object other) =>
      other is DayRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Thanh chọn nhanh: Hôm nay / 7 ngày / Tháng này / Chọn ngày.
class DateRangeBar extends StatelessWidget {
  final DayRange value;
  final ValueChanged<DayRange> onChanged;

  const DateRangeBar({super.key, required this.value, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: value.from,
        end: value.to.subtract(const Duration(days: 1)),
      ),
    );
    if (picked != null) onChanged(DayRange.fromPicker(picked));
  }

  @override
  Widget build(BuildContext context) {
    final presets = <String, DayRange>{
      'Hôm nay': DayRange.today(),
      '7 ngày': DayRange.lastDays(7),
      'Tháng này': DayRange.thisMonth(),
    };
    final isCustom = !presets.values.contains(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in presets.entries)
              ChoiceChip(
                label: Text(e.key),
                selected: value == e.value,
                selectedColor: AppColors.soft,
                onSelected: (_) => onChanged(e.value),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.date_range_outlined, size: 16),
              label: const Text('Chọn ngày'),
              selected: isCustom,
              selectedColor: AppColors.soft,
              onSelected: (_) => _pick(context),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value.label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    );
  }
}
