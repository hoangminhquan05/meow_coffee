import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../models/table_model.dart';
import '../../providers/session_provider.dart';
import '../../services/table_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/meow_ui.dart';

/// Quản lý bàn (L11): nhân viên/admin bấm Trống ↔ Bận thủ công;
/// chỉ admin thêm/sửa/xóa bàn.
class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  late final Stream<List<TableModel>> _tablesStream = TableService.watchAll();
  String? _selectedTableId;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggleStatus(TableModel table) async {
    final next = table.status == TableStatus.available
        ? TableStatus.occupied
        : TableStatus.available;
    try {
      await TableService.setStatus(table.id, next);
      if (mounted) setState(() => _selectedTableId = null);
      _showMessage('${table.displayName}: ${next.label}');
    } catch (e) {
      _showMessage('Lỗi khi cập nhật trạng thái bàn: $e');
    }
  }

  Future<void> _showAddOrEditDialog(
    List<TableModel> tables, {
    TableModel? existing,
  }) async {
    final result = await showDialog<({int number, int seats})>(
      context: context,
      builder: (_) => _AddOrEditTableDialog(
        existing: existing,
        usedNumbers: {
          for (final t in tables)
            if (t.id != existing?.id) t.tableNumber,
        },
      ),
    );
    if (result == null) return;

    try {
      if (existing == null) {
        await TableService.add(tableNumber: result.number, seats: result.seats);
        _showMessage('Đã thêm Bàn ${result.number}');
      } else {
        await TableService.update(
          existing.id,
          tableNumber: result.number,
          seats: result.seats,
        );
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
      message: 'Bạn có chắc chắn muốn xóa ${table.displayName}?',
      confirmLabel: 'Xóa bàn',
      cancelLabel: 'Hủy',
      isDanger: true,
    );
    if (!confirmed) return;
    try {
      await TableService.delete(table.id);
      if (mounted) setState(() => _selectedTableId = null);
      _showMessage('Đã xóa bàn');
    } catch (e) {
      _showMessage('Lỗi khi xóa bàn: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<SessionProvider>().isAdmin;

    return StreamBuilder<List<TableModel>>(
      stream: _tablesStream,
      builder: (context, snapshot) {
        final tables = snapshot.data ?? const <TableModel>[];
        TableModel? selectedTable;
        for (final t in tables) {
          if (t.id == _selectedTableId) selectedTable = t;
        }

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: MeowHeader(
            title: 'Quản Lý Bàn',
            trailing: isAdmin
                ? MeowCircleIconButton(
                    icon: Icons.add_rounded,
                    onTap: () => _showAddOrEditDialog(tables),
                  )
                : null,
          ),
          body: snapshot.hasError
              ? Center(
                  child: Text(
                    'Lỗi khi tải dữ liệu bàn: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.danger),
                  ),
                )
              : !snapshot.hasData
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.brand),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            children: [
                              const MeowEditorialHero(
                                eyebrow: 'MEOW COFFEE',
                                title: 'Sơ đồ bàn phục vụ',
                                subtitle:
                                    'Chạm vào bàn để đổi trạng thái Trống / Bận.',
                              ),
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
                                    childAspectRatio: 1.25,
                                  ),
                                  itemCount: tables.length,
                                  itemBuilder: (context, index) =>
                                      _TableCard(
                                    table: tables[index],
                                    selected:
                                        _selectedTableId == tables[index].id,
                                    onTap: () => setState(() {
                                      _selectedTableId =
                                          _selectedTableId == tables[index].id
                                              ? null
                                              : tables[index].id;
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (selectedTable != null)
                          _SelectedTableBar(
                            table: selectedTable,
                            isAdmin: isAdmin,
                            onToggle: () => _toggleStatus(selectedTable!),
                            onEdit: () => _showAddOrEditDialog(
                              tables,
                              existing: selectedTable,
                            ),
                            onDelete: () => _confirmDelete(selectedTable!),
                          ),
                      ],
                    ),
        );
      },
    );
  }
}

class _TableCard extends StatelessWidget {
  final TableModel table;
  final bool selected;
  final VoidCallback onTap;

  const _TableCard({
    required this.table,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = table.status == TableStatus.available;
    final color = isEmpty ? AppColors.success : AppColors.danger;
    return MeowCard(
      padding: const EdgeInsets.all(16),
      borderColor: selected ? AppColors.brand : AppColors.border,
      borderWidth: selected ? 2 : 1,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isEmpty ? AppColors.successSoft : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.table_restaurant_rounded,
                    size: 19, color: color),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isEmpty ? AppColors.successSoft : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  table.status.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                table.displayName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Text(
                '${table.seats} ghế',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedTableBar extends StatelessWidget {
  final TableModel table;
  final bool isAdmin;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SelectedTableBar({
    required this.table,
    required this.isAdmin,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = table.status == TableStatus.available;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
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
                'Đang chọn: ${table.displayName} (${table.status.label})',
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
                      label: isEmpty ? 'Chuyển sang Bận' : 'Chuyển sang Trống',
                      height: 44,
                      onPressed: onToggle,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: MeowSecondaryButton(
                        label: 'Sửa',
                        height: 44,
                        onPressed: onEdit,
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
                        onPressed: onDelete,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddOrEditTableDialog extends StatefulWidget {
  final TableModel? existing;
  final Set<int> usedNumbers;

  const _AddOrEditTableDialog({this.existing, required this.usedNumbers});

  @override
  State<_AddOrEditTableDialog> createState() => _AddOrEditTableDialogState();
}

class _AddOrEditTableDialogState extends State<_AddOrEditTableDialog> {
  late final TextEditingController _numberController = TextEditingController(
    text: widget.existing?.tableNumber.toString() ?? '',
  );
  late final TextEditingController _seatsController = TextEditingController(
    text: widget.existing?.seats.toString() ?? '',
  );
  String? _errorText;

  @override
  void dispose() {
    _numberController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  void _submit() {
    final number = int.tryParse(_numberController.text.trim()) ?? 0;
    final seats = int.tryParse(_seatsController.text.trim()) ?? 0;
    if (number <= 0 || seats <= 0) {
      setState(() => _errorText = 'Vui lòng nhập số bàn và số ghế hợp lệ');
      return;
    }
    if (widget.usedNumbers.contains(number)) {
      setState(() => _errorText = 'Bàn $number đã tồn tại');
      return;
    }
    Navigator.pop(context, (number: number, seats: seats));
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
            const SizedBox(height: 16),
            MeowFormField(
              label: 'SỐ BÀN',
              controller: _numberController,
              hintText: 'Ví dụ: 5',
              keyboardType: TextInputType.number,
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
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
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
