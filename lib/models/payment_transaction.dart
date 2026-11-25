import 'package:cloud_firestore/cloud_firestore.dart';

/// Giao dịch ngân hàng SePay báo về (`payment_transactions/{id}`, Worker ghi).
class PaymentTransaction {
  final String id;
  final int amount;
  final String content;
  final String gateway;
  final String referenceCode;
  final String transactionDate;
  final String? orderCode;
  final String? orderId;

  /// matched | needs_review | resolved
  final String status;
  final String? reasonText;
  final String? resolution; // attached | dismissed
  final String? note;
  final String? resolvedByName;
  final DateTime? receivedAt;
  final DateTime? resolvedAt;

  const PaymentTransaction({
    required this.id,
    required this.amount,
    required this.content,
    required this.gateway,
    required this.referenceCode,
    required this.transactionDate,
    required this.orderCode,
    required this.orderId,
    required this.status,
    required this.reasonText,
    required this.resolution,
    required this.note,
    required this.resolvedByName,
    required this.receivedAt,
    required this.resolvedAt,
  });

  bool get needsReview => status == 'needs_review';

  factory PaymentTransaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    final by = m['resolved_by'];
    return PaymentTransaction(
      id: doc.id,
      amount: (m['amount'] as num?)?.round() ?? 0,
      content: m['content']?.toString() ?? '',
      gateway: m['gateway']?.toString() ?? '',
      referenceCode: m['reference_code']?.toString() ?? '',
      transactionDate: m['transaction_date']?.toString() ?? '',
      orderCode: m['order_code'] as String?,
      orderId: m['order_id'] as String?,
      status: m['status']?.toString() ?? '',
      reasonText: m['reason_text'] as String?,
      resolution: m['resolution'] as String?,
      note: m['note'] as String?,
      resolvedByName: by is Map ? by['name']?.toString() : null,
      receivedAt: ts(m['received_at']),
      resolvedAt: ts(m['resolved_at']),
    );
  }
}
