import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/payment_transaction.dart';
import '../../services/online_order_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

/// Admin: "Giao dịch cần kiểm tra" (O6) – tiền về không khớp đơn
/// (thiếu/thừa, sai nội dung, đơn đã hủy / hết hạn…).
class PaymentReviewsScreen extends StatefulWidget {
  const PaymentReviewsScreen({super.key});

  @override
  State<PaymentReviewsScreen> createState() => _PaymentReviewsScreenState();
}

class _PaymentReviewsScreenState extends State<PaymentReviewsScreen> {
  static Stream<List<PaymentTransaction>> _watch(String status) => FirebaseFirestore.instance
      .collection('payment_transactions')
      .where('status', isEqualTo: status)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(PaymentTransaction.fromDoc).toList()
        ..sort((a, b) => (b.receivedAt ?? DateTime(0)).compareTo(a.receivedAt ?? DateTime(0))));

  late final _pending = _watch('needs_review');
  late final _resolved = _watch('resolved');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Giao Dịch Cần Kiểm Tra'),
          backgroundColor: AppColors.bg,
          bottom: const TabBar(
            labelColor: AppColors.brand,
            indicatorColor: AppColors.brand,
            tabs: [Tab(text: 'Cần xử lý'), Tab(text: 'Đã xử lý')],
          ),
        ),
        body: TabBarView(
          children: [
            _TxList(stream: _pending, empty: 'Không có giao dịch cần kiểm tra 🎉'),
            _TxList(stream: _resolved, empty: 'Chưa có giao dịch đã xử lý'),
          ],
        ),
      ),
    );
  }
}

class _TxList extends StatelessWidget {
  final Stream<List<PaymentTransaction>> stream;
  final String empty;

  const _TxList({required this.stream, required this.empty});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentTransaction>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Lỗi tải giao dịch: ${snap.error}',
                style: const TextStyle(color: AppColors.danger)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.brand));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return Center(child: Text(empty, style: const TextStyle(color: AppColors.muted)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _TxCard(tx: list[i]),
        );
      },
    );
  }
}

class _TxCard extends StatelessWidget {
  final PaymentTransaction tx;

  const _TxCard({required this.tx});

  Future<void> _attach(BuildContext context) async {
    final result = await showDialog<({String code, String note})>(
      context: context,
      builder: (_) => _AttachDialog(suggestedCode: tx.orderCode),
    );
    if (result == null || !context.mounted) return;
    try {
      await OnlineOrderService.attachPayment(tx.id, result.code, note: result.note);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã gắn vào đơn ${result.code.toUpperCase()}')),
      );
    } on OnlineOrderError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _dismiss(BuildContext context) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _NoteDialog(),
    );
    if (note == null || !context.mounted) return;
    try {
      await OnlineOrderService.dismissPayment(tx.id, note);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã đánh dấu đã xử lý')));
    } on OnlineOrderError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(14),
      borderColor: tx.needsReview ? AppColors.warning : AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(formatMoney(tx.amount),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.brand)),
              const Spacer(),
              Text(formatDateTime(tx.receivedAt),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText('Nội dung: ${tx.content}', style: const TextStyle(fontSize: 13)),
          Text(
            [
              if (tx.gateway.isNotEmpty) tx.gateway,
              if (tx.referenceCode.isNotEmpty) 'Mã GD ${tx.referenceCode}',
              if (tx.orderCode != null) 'Mã đơn nhận ra: ${tx.orderCode}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (tx.reasonText != null && tx.needsReview) ...[
            const SizedBox(height: 6),
            Text('Lý do: ${tx.reasonText}',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warning)),
          ],
          if (!tx.needsReview) ...[
            const SizedBox(height: 6),
            Text(
              '${tx.resolution == 'attached' ? 'Đã gắn vào đơn ${tx.orderCode}' : 'Đã xử lý ngoài app'}'
              '${tx.resolvedByName != null ? ' · ${tx.resolvedByName}' : ''}'
              ' · ${formatDateTime(tx.resolvedAt)}'
              '${(tx.note ?? '').isNotEmpty ? '\nGhi chú: ${tx.note}' : ''}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.success),
            ),
          ],
          if (tx.needsReview) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MeowSecondaryButton(
                    label: 'Đã xử lý',
                    height: 42,
                    onPressed: () => _dismiss(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MeowPrimaryButton(
                    label: 'Gắn vào đơn',
                    height: 42,
                    onPressed: () => _attach(context),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachDialog extends StatefulWidget {
  final String? suggestedCode;

  const _AttachDialog({this.suggestedCode});

  @override
  State<_AttachDialog> createState() => _AttachDialogState();
}

class _AttachDialogState extends State<_AttachDialog> {
  late final _code = TextEditingController(text: widget.suggestedCode ?? 'ON-');
  final _note = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^ON-\d{6}-\d{3}$', caseSensitive: false).hasMatch(_code.text.trim());
    return AlertDialog(
      title: const Text('Gắn vào đơn'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Đơn phải là đơn VietQR đang chờ thanh toán hoặc bị hủy do quá hạn. '
            'Đơn sẽ thành "đã thanh toán – chờ xác nhận".',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
          TextField(
            controller: _code,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Mã đơn (ON-ddMMyy-NNN)'),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, (code: _code.text.trim(), note: _note.text.trim()))
              : null,
          child: const Text('Gắn'),
        ),
      ],
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đã xử lý'),
      content: TextField(
        controller: _note,
        autofocus: true,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Ghi chú *',
          hintText: 'Ví dụ: đã hoàn 85.000đ cho khách qua STK …',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: _note.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _note.text.trim()),
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}
