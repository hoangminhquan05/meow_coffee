import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';
import '../core/firestore_paths.dart';
import '../models/table_model.dart';

class TableService {
  TableService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(FsCollections.tables);

  /// Danh sách bàn realtime, sắp theo số bàn tăng dần.
  static Stream<List<TableModel>> watchAll() => _col.snapshots().map(
        (s) => s.docs.map(TableModel.fromDoc).toList()
          ..sort((a, b) => a.tableNumber.compareTo(b.tableNumber)),
      );

  /// Nhân viên/admin đổi trạng thái bàn thủ công (L11).
  static Future<void> setStatus(String id, TableStatus status) =>
      _col.doc(id).update({
        'status': status.value,
        'updated_at': FieldValue.serverTimestamp(),
      });

  /// Admin thêm bàn.
  static Future<void> add({required int tableNumber, required int seats}) =>
      _col.add({
        'table_number': tableNumber,
        'seats': seats,
        'status': TableStatus.available.value,
        'updated_at': FieldValue.serverTimestamp(),
      });

  /// Admin sửa bàn.
  static Future<void> update(
    String id, {
    required int tableNumber,
    required int seats,
  }) =>
      _col.doc(id).update({
        'table_number': tableNumber,
        'seats': seats,
        'updated_at': FieldValue.serverTimestamp(),
      });

  static Future<void> delete(String id) => _col.doc(id).delete();
}
