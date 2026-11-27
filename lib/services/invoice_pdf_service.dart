import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/order.dart';
import '../models/shop_settings.dart';
import '../utils/file_download.dart';
import '../utils/formatters.dart';

/// Xuất hóa đơn PDF từ một đơn đã lưu (L7). Font mặc định của gói pdf
/// không có dấu tiếng Việt nên chữ được bỏ dấu.
class InvoicePdfService {
  /// Bỏ dấu tiếng Việt nhưng giữ chữ hoa/thường.
  static String _t(String s) {
    final lower = normalizeVietnamese(s);
    final buf = StringBuffer();
    for (var i = 0; i < s.length && i < lower.length; i++) {
      final c = s[i];
      buf.write(c.toUpperCase() == c && c.toLowerCase() != c
          ? lower[i].toUpperCase()
          : lower[i]);
    }
    return buf.toString();
  }

  /// Tạo PDF rồi lưu (web: trình duyệt tải về; Android: Downloads).
  /// Trả về chỗ đã lưu để báo cho người dùng.
  static Future<String> generateAndSave(Order order, ShopSettings shop) async {
    final pdf = pw.Document();
    final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'HOA DON THANH TOAN',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'Ma don: ${order.orderCode}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (order.isCancelled)
            pw.Center(
              child: pw.Text('(DON DA HUY)', style: bold),
            ),
          pw.SizedBox(height: 12),
          pw.Text(_t(shop.name).toUpperCase(),
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (shop.address.isNotEmpty) pw.Text('Dia chi: ${_t(shop.address)}'),
          if (shop.phone.isNotEmpty) pw.Text('Dien thoai: ${shop.phone}'),
          pw.Divider(),
          pw.Text('Loai don: ${_t(order.fulfillmentLabel)}'),
          pw.Text('Thu ngan: ${_t(order.seller?.name ?? '')}'),
          pw.Text('Thoi gian: ${formatDateTime(order.createdAt)}'),
          pw.Divider(),
          pw.Row(
            children: [
              pw.Expanded(flex: 4, child: pw.Text('San pham', style: bold)),
              pw.Expanded(
                flex: 1,
                child: pw.Text('SL', textAlign: pw.TextAlign.center, style: bold),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text('Thanh tien', textAlign: pw.TextAlign.right, style: bold),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          for (final item in order.items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(_t(item.displayName)),
                        pw.Text(
                          '${formatVnd(item.unitPrice)} / mon',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        if (item.note.isNotEmpty)
                          pw.Text(
                            'Ghi chu: ${_t(item.note)}',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text('x${item.quantity}', textAlign: pw.TextAlign.center),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(formatVnd(item.lineTotal), textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ),
          pw.Divider(),
          if (order.note.isNotEmpty) ...[
            pw.Text('Ghi chu don: ${_t(order.note)}'),
            pw.SizedBox(height: 6),
          ],
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Tong tien:', style: bold),
              pw.Text(formatVnd(order.total), style: bold),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text('Phuong thuc thanh toan: ${_t(order.paymentMethod.label)}'),
          if (order.paymentRef != null)
            pw.Text('Noi dung chuyen khoan: ${order.paymentRef}'),
          pw.SizedBox(height: 12),
          pw.Text('Cam on quy khach!'),
        ],
      ),
    );

    return saveDownload(
      await pdf.save(),
      fileName: 'HOADON_${order.orderCode}.pdf',
      mimeType: 'application/pdf',
    );
  }
}
