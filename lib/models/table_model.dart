class TableModel {
  final String idBan;
  final String soBan;
  final int choNgoi;
  final String trangThai;

  const TableModel({
    this.idBan = '',
    this.soBan = '',
    this.choNgoi = 0,
    this.trangThai = 'Trống',
  });

  factory TableModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    final rawSeats = map['cho_ngoi'];
    final int parsedSeats = rawSeats is num
        ? rawSeats.toInt()
        : int.tryParse(rawSeats?.toString() ?? '') ?? 0;

    final rawId = map['id_ban']?.toString() ?? '';
    return TableModel(
      idBan: rawId.isNotEmpty ? rawId : (docId ?? ''),
      soBan: map['so_ban']?.toString() ?? '',
      choNgoi: parsedSeats,
      trangThai: map['trang_thai']?.toString() ?? 'Trống',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_ban': idBan,
      'so_ban': soBan,
      'cho_ngoi': choNgoi,
      'trang_thai': trangThai,
    };
  }

  TableModel copyWith({
    String? idBan,
    String? soBan,
    int? choNgoi,
    String? trangThai,
  }) {
    return TableModel(
      idBan: idBan ?? this.idBan,
      soBan: soBan ?? this.soBan,
      choNgoi: choNgoi ?? this.choNgoi,
      trangThai: trangThai ?? this.trangThai,
    );
  }
}
