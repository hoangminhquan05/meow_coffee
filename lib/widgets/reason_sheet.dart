import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'meow_ui.dart';

/// Bảng chọn nhanh lý do; chọn "Khác" thì gõ thêm. Trả về lý do hoặc null.
Future<String?> showReasonSheet(
  BuildContext context, {
  required String title,
  required List<String> reasons,
  required String confirmLabel,
  String cancelLabel = 'Quay lại',
  String? message,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReasonSheet(
      title: title,
      reasons: reasons,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      message: message,
    ),
  );
}

class _ReasonSheet extends StatefulWidget {
  final String title;
  final List<String> reasons;
  final String confirmLabel;
  final String cancelLabel;
  final String? message;

  const _ReasonSheet({
    required this.title,
    required this.reasons,
    required this.confirmLabel,
    required this.cancelLabel,
    this.message,
  });

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  String? _reason;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _result {
    if (_reason == null) return null;
    if (_reason == 'Khác') {
      final t = _other.text.trim();
      return t.isEmpty ? null : t;
    }
    return _reason;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              if (widget.message != null) ...[
                const SizedBox(height: 6),
                Text(widget.message!,
                    style: const TextStyle(fontSize: 13, color: AppColors.muted)),
              ],
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(
                  children: [
                    for (final r in widget.reasons)
                      RadioListTile<String>(
                        value: r,
                        title: Text(r),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              if (_reason == 'Khác')
                TextField(
                  controller: _other,
                  autofocus: true,
                  maxLength: 200,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Nhập lý do'),
                ),
              const SizedBox(height: 12),
              MeowPrimaryButton(
                label: widget.confirmLabel,
                solidColor: AppColors.danger,
                onPressed: _result == null ? null : () => Navigator.pop(context, _result),
              ),
              const SizedBox(height: 8),
              MeowSecondaryButton(
                label: widget.cancelLabel,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
