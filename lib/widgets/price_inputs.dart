import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';
import 'meow_ui.dart';

/// Trạng thái ô nhập giá cho màn thêm/sửa sản phẩm.
/// Món chia size: nhập giá S/M/L (để trống = không bán size đó).
/// Món không chia size: một giá → `{default: giá}`.
class PriceFormController {
  bool hasSizes = true;
  final single = TextEditingController();
  final bySize = {
    for (final s in Product.sizeOrder) s: TextEditingController(),
  };

  void load(Map<String, int> prices) {
    hasSizes = prices.isNotEmpty && !prices.containsKey(Product.defaultSize);
    if (hasSizes) {
      for (final s in Product.sizeOrder) {
        final p = prices[s];
        bySize[s]!.text = p == null ? '' : '$p';
      }
    } else {
      final p = prices[Product.defaultSize];
      single.text = p == null ? '' : '$p';
    }
  }

  /// Trả về map giá, hoặc null nếu chưa hợp lệ.
  Map<String, int>? build() {
    int? parse(String t) {
      final v = int.tryParse(t.trim().replaceAll('.', '').replaceAll(',', ''));
      return (v != null && v > 0) ? v : null;
    }

    if (!hasSizes) {
      final v = parse(single.text);
      return v == null ? null : {Product.defaultSize: v};
    }
    final result = <String, int>{};
    for (final e in bySize.entries) {
      if (e.value.text.trim().isEmpty) continue;
      final v = parse(e.value.text);
      if (v == null) return null;
      result[e.key] = v;
    }
    return result.isEmpty ? null : result;
  }

  void dispose() {
    single.dispose();
    for (final c in bySize.values) {
      c.dispose();
    }
  }
}

class PriceInputs extends StatefulWidget {
  final PriceFormController controller;

  const PriceInputs({super.key, required this.controller});

  @override
  State<PriceInputs> createState() => _PriceInputsState();
}

class _PriceInputsState extends State<PriceInputs> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Chia size S / M / L',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          subtitle: const Text(
            'Tắt nếu món chỉ có một giá (ví dụ bánh)',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          value: c.hasSizes,
          onChanged: (v) => setState(() => c.hasSizes = v),
        ),
        if (c.hasSizes)
          Row(
            children: [
              for (final s in Product.sizeOrder) ...[
                Expanded(
                  child: MeowFormField(
                    label: 'GIÁ SIZE $s',
                    controller: c.bySize[s]!,
                    hintText: 'VNĐ',
                    keyboardType: TextInputType.number,
                  ),
                ),
                if (s != Product.sizeOrder.last) const SizedBox(width: 10),
              ],
            ],
          )
        else
          MeowFormField(
            label: 'GIÁ *',
            controller: c.single,
            hintText: 'Nhập giá bán (VNĐ)',
            keyboardType: TextInputType.number,
          ),
        if (c.hasSizes)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Để trống size nào thì món không bán size đó (cần ít nhất 1 size).',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ),
      ],
    );
  }
}
