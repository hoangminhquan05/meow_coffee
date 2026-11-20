import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../providers/cart_provider.dart';
import '../utils/formatters.dart';

class InvoicePdfService {
  static const _downloadsChannel =
      MethodChannel('com.example.meow_coffee/downloads');
  static Future<File> generateAndSave({
    required List<CartItem> items,
    required double totalPrice,
    required String userName,
    required String currentDate,
    required String paymentMethod,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'HOA DON THANH TOAN',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'MEOW COFFEE',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Dia chi: 83 Hai Ba Trung, Hoan Kiem, TP.Ha Noi'),
          pw.Text('Dien thoai: 032 8386 66'),
          pw.Divider(),
          pw.Text('Nhan vien: ${normalizeVietnamese(userName)}'),
          pw.Text('Ngay: $currentDate'),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  'San pham',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Expanded(
                flex: 1,
                child: pw.Text(
                  'SL',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Thanh tien',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          ...items.map(
            (item) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(normalizeVietnamese(item.product.name)),
                  ),
                  pw.Expanded(
                    flex: 1,
                    child: pw.Text(
                      'x${item.quantity}',
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      formatVnd(item.totalPrice),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Tong tien:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatVnd(totalPrice),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Phuong thuc thanh toan: ${normalizeVietnamese(paymentMethod)}',
          ),
          pw.SizedBox(height: 12),
          pw.Text('Cam on quy khach!'),
        ],
      ),
    );

    final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'INVOICE_$timeStamp.pdf';
    final bytes = await pdf.save();

    if (Platform.isAndroid) {
      final savedPath = await _downloadsChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'fileName': fileName,
          'mimeType': 'application/pdf',
          'bytes': bytes,
        },
      );
      if (savedPath != null && savedPath.isNotEmpty) {
        return File(savedPath);
      }
    }

    final dir = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }
}
