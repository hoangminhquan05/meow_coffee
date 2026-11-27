import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/firestore_paths.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

/// Số lời mời trong ca hiện tại của shipper (đọc nhật ký `dispatch_offers`).
class OfferStats {
  final int offered;
  final int accepted;
  final int declined;
  final int timeout;

  const OfferStats({this.offered = 0, this.accepted = 0, this.declined = 0, this.timeout = 0});

  /// Từ chối + hết giờ – cùng cách đếm với cảnh báo O35.
  int get missed => declined + timeout;

  factory OfferStats.fromResults(Iterable<String?> results) {
    var accepted = 0, declined = 0, timeout = 0, offered = 0;
    for (final r in results) {
      // Lời mời bị quán thu hồi (gán tay / hủy đơn) không tính cho shipper.
      if (r == 'cancelled') continue;
      offered++;
      switch (r) {
        case 'accepted':
          accepted++;
        case 'declined':
          declined++;
        case 'timeout':
          timeout++;
      }
    }
    return OfferStats(offered: offered, accepted: accepted, declined: declined, timeout: timeout);
  }

  static Stream<OfferStats> watch(String uid, String shiftId) {
    if (shiftId.isEmpty) return Stream.value(const OfferStats());
    return FirebaseFirestore.instance
        .collection(FsCollections.dispatchOffers)
        .where('shipper.id', isEqualTo: uid)
        .where('shift_id', isEqualTo: shiftId)
        .snapshots()
        .map((s) => OfferStats.fromResults(s.docs.map((d) => d.data()['result'] as String?)));
  }
}

Color _missedColor(int missed) => missed >= 3
    ? AppColors.danger
    : missed == 2
        ? AppColors.warning
        : AppColors.muted;

/// Lời nhắc theo số lần từ chối/bỏ lỡ (O35).
String? missedNote(int missed) => missed >= 3
    ? 'Quản lý đã được thông báo về số lần từ chối/bỏ lỡ của bạn.'
    : missed == 2
        ? 'Đã từ chối/bỏ lỡ 2 lời mời – lần sau quản lý sẽ được thông báo.'
        : null;

/// Thống kê lời mời trong ca: dạng dòng gọn (trang chủ) hoặc thẻ (tab Hôm nay).
class ShiftOfferStats extends StatefulWidget {
  final String uid;
  final String shiftId;
  final bool compact;

  const ShiftOfferStats({
    super.key,
    required this.uid,
    required this.shiftId,
    this.compact = false,
  });

  @override
  State<ShiftOfferStats> createState() => _ShiftOfferStatsState();
}

class _ShiftOfferStatsState extends State<ShiftOfferStats> {
  // Giữ một luồng cho mỗi ca – màn cha rebuild (GPS, đồng hồ) không nghe lại từ đầu.
  late Stream<OfferStats> _stream = OfferStats.watch(widget.uid, widget.shiftId);

  @override
  void didUpdateWidget(covariant ShiftOfferStats old) {
    super.didUpdateWidget(old);
    if (old.shiftId != widget.shiftId || old.uid != widget.uid) {
      _stream = OfferStats.watch(widget.uid, widget.shiftId);
    }
  }

  bool get compact => widget.compact;
  String get shiftId => widget.shiftId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OfferStats>(
      stream: _stream,
      builder: (context, snap) {
        final s = snap.data ?? const OfferStats();
        final color = _missedColor(s.missed);
        final note = missedNote(s.missed);
        if (compact) return _compact(s, color, note);
        return MeowCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('LỜI MỜI TRONG CA NÀY',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              const SizedBox(height: 10),
              Row(
                children: [
                  _num('${s.offered}', 'Lời mời', AppColors.ink),
                  _num('${s.accepted}', 'Đã nhận', AppColors.success),
                  _num('${s.declined}', 'Từ chối', s.declined > 0 ? color : AppColors.muted),
                  _num('${s.timeout}', 'Hết giờ', s.timeout > 0 ? color : AppColors.muted),
                ],
              ),
              if (shiftId.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Bắt đầu ca để nhận lời mời.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(note,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _compact(OfferStats s, Color color, String? note) {
    final warn = s.missed >= 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: s.missed >= 3
            ? AppColors.dangerSoft
            : warn
                ? AppColors.warningSoft
                : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warn ? Colors.transparent : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(warn ? Icons.warning_amber_rounded : Icons.mark_email_unread_outlined,
                  size: 20, color: warn ? color : AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trong ca: ${s.offered} lời mời · nhận ${s.accepted} · '
                  'từ chối ${s.declined} · hết giờ ${s.timeout}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: warn ? FontWeight.w700 : FontWeight.w500,
                      color: warn ? color : AppColors.inkSlate),
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: Text(note, style: TextStyle(fontSize: 12, color: color)),
            ),
        ],
      ),
    );
  }

  Widget _num(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      );
}
