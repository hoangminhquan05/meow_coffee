import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/enums.dart';

/// Bàn trong `tables/{id}`. Trạng thái do nhân viên bấm thủ công.
class TableModel {
  final String id;
  final int tableNumber;
  final int seats;
  final TableStatus status;
  final DateTime? updatedAt;

  const TableModel({
    this.id = '',
    this.tableNumber = 0,
    this.seats = 0,
    this.status = TableStatus.available,
    this.updatedAt,
  });

  String get displayName => 'Bàn $tableNumber';

  factory TableModel.fromMap(Map<String, dynamic> map, {required String id}) {
    int toInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    final updated = map['updated_at'];
    return TableModel(
      id: id,
      tableNumber: toInt(map['table_number']),
      seats: toInt(map['seats']),
      status: TableStatus.fromValue(map['status'] as String?),
      updatedAt: updated is Timestamp ? updated.toDate() : null,
    );
  }

  factory TableModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      TableModel.fromMap(doc.data() ?? const {}, id: doc.id);
}
