import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/table_model.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  String? _userRole;
  String? _selectedTableId;

  bool get _isAdmin => _userRole == 'ADMIN';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserRole();
  }

  Future<void> _loadCurrentUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('uSer').doc(uid).get();
      if (!mounted) return;
      setState(() => _userRole = doc.data()?['role'] as String?);
    } catch (_) {}
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _updateStatus(String tableId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('ql_ban')
          .doc(tableId)
          .update({'trang_thai': newStatus});
      if (mounted) setState(() => _selectedTableId = null);
      _showMessage('Đã cập nhật trạng thái bàn');
    } catch (e) {
      _showMessage('Lỗi khi cập nhật trạng thái bàn: $e');
    }
  }

  Future<void> _showAddOrEditDialog({TableModel? existing}) async {
    final result = await showDialog<({String name, int seats})>(
      context: context,
      builder: (_) => _AddOrEditTableDialog(existing: existing),
    );

    if (result == null) return;

    try {
      final col = FirebaseFirestore.instance.collection('ql_ban');
      if (existing == null) {
        final newDoc = col.doc();
        final newTable = TableModel(
          idBan: newDoc.id,
          soBan: result.name,
          choNgoi: result.seats,
          trangThai: 'Trống',
        );
        await newDoc.set(newTable.toMap());
        _showMessage('Đã thêm bàn mới');
      } else {
        await col.doc(existing.idBan).update({
          'so_ban': result.name,
          'cho_ngoi': result.seats,
        });
        if (mounted) setState(() => _selectedTableId = null);
        _showMessage('Đã cập nhật bàn');
      }
    } catch (e) {
      _showMessage('Lỗi lưu thông tin bàn: $e');
    }
  }

  Future<void> _confirmDelete(TableModel table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa ${table.soBan}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('ql_ban')
            .doc(table.idBan)
            .delete();
        if (mounted) setState(() => _selectedTableId = null);
        _showMessage('Đã xóa bàn');
      } catch (e) {
        _showMessage('Lỗi khi xóa bàn: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý bàn'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Thêm bàn mới',
              onPressed: () => _showAddOrEditDialog(),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('ql_ban').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Lỗi khi tải dữ liệu bàn: ${snapshot.error}'),
            );
          }

          final tables = (snapshot.data?.docs ?? [])
              .map((doc) => TableModel.fromMap(doc.data(), docId: doc.id))
              .toList();

          if (tables.isEmpty) {
            return const Center(
              child: Text(
                'Chưa có bàn nào',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              mainAxisExtent: 245,
            ),
            itemCount: tables.length,
            itemBuilder: (context, index) {
              final table = tables[index];
              final isSelected = _selectedTableId == table.idBan;
              final bgColor = switch (table.trangThai) {
                'Trống' => Colors.green.withValues(alpha: 0.2),
                'Đang hoạt động' => Colors.red.withValues(alpha: 0.2),
                _ => Colors.grey.withValues(alpha: 0.2),
              };

              return Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Card(
                      color: bgColor,
                      elevation: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _selectedTableId = isSelected ? null : table.idBan;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: double.infinity,
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.table_restaurant,
                                  size: 40,
                                  color: Colors.black87,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  table.soBan,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(table.trangThai),
                                Text(
                                  'Chỗ ngồi: ${table.choNgoi}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: ElevatedButton(
                          onPressed: () => _updateStatus(
                            table.idBan,
                            table.trangThai == 'Trống'
                                ? 'Đang hoạt động'
                                : 'Trống',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: table.trangThai == 'Trống'
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            table.trangThai == 'Trống' ? 'Hoạt động' : 'Trống',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      _showAddOrEditDialog(existing: table),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Text('Sửa',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: ElevatedButton(
                                  onPressed: () => _confirmDelete(table),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Text('Xóa',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddOrEditTableDialog extends StatefulWidget {
  final TableModel? existing;

  const _AddOrEditTableDialog({this.existing});

  @override
  State<_AddOrEditTableDialog> createState() => _AddOrEditTableDialogState();
}

class _AddOrEditTableDialogState extends State<_AddOrEditTableDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _seatsController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.soBan ?? '');
    _seatsController = TextEditingController(
      text: widget.existing != null ? widget.existing!.choNgoi.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final seats = int.tryParse(_seatsController.text.trim()) ?? 0;
    if (name.isEmpty || seats <= 0) {
      setState(() => _errorText = 'Vui lòng nhập tên bàn và số ghế hợp lệ');
      return;
    }
    Navigator.pop(context, (name: name, seats: seats));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Thêm bàn mới' : 'Chỉnh sửa bàn'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Tên bàn',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seatsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số ghế',
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isNew ? 'Thêm' : 'Lưu'),
        ),
      ],
    );
  }
}
