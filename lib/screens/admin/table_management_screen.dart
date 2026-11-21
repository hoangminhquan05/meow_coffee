import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/table_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tablesStream;
  String? _userRole;
  String? _selectedTableId;

  bool get _isAdmin => _userRole == 'ADMIN';

  @override
  void initState() {
    super.initState();
    _tablesStream = FirebaseFirestore.instance.collection('ql_ban').snapshots();
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
    final confirmed = await showMeowConfirmDialog(
      context,
      title: 'Xóa bàn',
      message: 'Bạn có chắc chắn muốn xóa ${table.soBan}?',
      confirmLabel: 'Xóa bàn',
      cancelLabel: 'Hủy',
      isDanger: true,
    );

    if (confirmed) {
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
      backgroundColor: AppColors.bg,
      appBar: MeowHeader(
        title: 'Quản Lý Bàn',
        trailing: _isAdmin
            ? MeowCircleIconButton(
                icon: Icons.add_rounded,
                onTap: () => _showAddOrEditDialog(),
              )
            : null,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _tablesStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Lỗi khi tải dữ liệu bàn: ${snapshot.error}',
                style: const TextStyle(color: AppColors.danger),
              ),
            );
          }

          final tables = (snapshot.data?.docs ?? [])
              .map((doc) => TableModel.fromMap(doc.data(), docId: doc.id))
              .toList();

          TableModel? selectedTable;
          if (_selectedTableId != null) {
            for (final t in tables) {
              if (t.idBan == _selectedTableId) {
                selectedTable = t;
                break;
              }
            }
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    const MeowEditorialHero(
                      eyebrow: 'MEOW COFFEE',
                      title: 'Sơ đồ bàn phục vụ',
                      subtitle:
                          'Chạm vào bàn để cập nhật trạng thái trống hoặc đang hoạt động.',
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(height: 16),
                      MeowPrimaryButton(
                        label: 'Thêm bàn mới',
                        icon: Icons.add_rounded,
                        height: 50,
                        onPressed: () => _showAddOrEditDialog(),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (tables.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Text(
                            'Chưa có bàn nào',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.08,
                        ),
                        itemCount: tables.length,
                        itemBuilder: (context, index) {
                          final table = tables[index];
                          final isSelected = _selectedTableId == table.idBan;
                          final isEmpty = table.trangThai == 'Trống';

                          return MeowCard(
                            padding: const EdgeInsets.all(16),
                            borderColor:
                                isSelected ? AppColors.brand : AppColors.border,
                            borderWidth: isSelected ? 2 : 1,
                            onTap: () {
                              setState(() {
                                _selectedTableId =
                                    isSelected ? null : table.idBan;
                              });
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isEmpty
                                            ? AppColors.soft
                                            : AppColors.dangerSoft,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.table_restaurant_rounded,
                                        size: 19,
                                        color: isEmpty
                                            ? AppColors.brand
                                            : AppColors.danger,
                                      ),
                                    ),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isEmpty
                                            ? AppColors.success
                                            : AppColors.danger,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      table.soBan,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${table.choNgoi} ghế • ${table.trangThai}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isEmpty
                                            ? AppColors.brand
                                            : AppColors.danger,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_isAdmin)
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _showAddOrEditDialog(
                                          existing: table,
                                        ),
                                        child: const Text(
                                          'Sửa',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        '  ·  ',
                                        style:
                                            TextStyle(color: AppColors.muted),
                                      ),
                                      GestureDetector(
                                        onTap: () => _confirmDelete(table),
                                        child: const Text(
                                          'Xóa',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.danger,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Text(
                                    'Chạm để đổi trạng thái',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (selectedTable != null)
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border:
                        Border(top: BorderSide(color: AppColors.borderSubtle)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Đang chọn: ${selectedTable.soBan}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: MeowPrimaryButton(
                                  label: selectedTable.trangThai == 'Trống'
                                      ? 'Chuyển hoạt động'
                                      : 'Chuyển bàn trống',
                                  height: 44,
                                  onPressed: () => _updateStatus(
                                    selectedTable!.idBan,
                                    selectedTable.trangThai == 'Trống'
                                        ? 'Đang hoạt động'
                                        : 'Trống',
                                  ),
                                ),
                              ),
                              if (_isAdmin) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: MeowSecondaryButton(
                                    label: 'Sửa',
                                    height: 44,
                                    onPressed: () => _showAddOrEditDialog(
                                      existing: selectedTable,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: MeowSecondaryButton(
                                    label: 'Xóa',
                                    height: 44,
                                    textColor: AppColors.danger,
                                    backgroundColor: AppColors.dangerSoft,
                                    borderColor: const Color(0xFFFECDD3),
                                    onPressed: () =>
                                        _confirmDelete(selectedTable!),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
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
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isNew ? 'Thêm bàn mới' : 'Chỉnh sửa bàn',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isNew
                  ? 'Thiết lập tên bàn và số chỗ ngồi.'
                  : 'Cập nhật thông tin bàn.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            MeowFormField(
              label: 'TÊN BÀN',
              controller: _nameController,
              hintText: 'Ví dụ: Bàn 01',
            ),
            const SizedBox(height: 14),
            MeowFormField(
              label: 'SỐ GHẾ',
              controller: _seatsController,
              hintText: 'Ví dụ: 4',
              keyboardType: TextInputType.number,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            MeowPrimaryButton(
              label: isNew ? 'Thêm bàn' : 'Lưu thay đổi',
              height: 48,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            MeowSecondaryButton(
              label: 'Hủy',
              height: 44,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
