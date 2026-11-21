import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/meow_ui.dart';

class _SaleDetail {
  final String sellerId;
  final String sellerName;
  final String saleDate;
  final List<Map<String, dynamic>> products;
  final double totalAmount;
  final String? paymentMethod;

  const _SaleDetail({
    required this.sellerId,
    required this.sellerName,
    required this.saleDate,
    required this.products,
    required this.totalAmount,
    this.paymentMethod,
  });
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  List<_SaleDetail> _originalSales = [];
  List<_SaleDetail> _filteredSales = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _userRole;

  Set<String> _selectedStaffIds = {};
  DateTime? _selectedDate;
  DateTimeRange? _selectedDateRange;
  String? _selectedPaymentMethod;
  String? _selectedProduct;

  Set<String> _availableProducts = {};
  Set<String> _availablePaymentMethods = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _errorMessage = 'Không có ID người dùng';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userDoc = await _firestore.collection('uSer').doc(uid).get();
      final role = userDoc.data()?['role'] as String?;

      Query<Map<String, dynamic>> query = _firestore.collection('order_history');
      if (role != 'ADMIN') {
        query = query.where('seller_id', isEqualTo: uid);
      }

      final snapshot = await query.get();
      final sales = snapshot.docs.map((doc) {
        final data = doc.data();
        final rawProducts = data['products'] as List<dynamic>? ?? [];
        final products = rawProducts
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        final rawTotal = data['total'];
        final total = rawTotal is num ? rawTotal.toDouble() : 0.0;
        final method = (data['paymentMethod'] as String?)?.trim();

        return _SaleDetail(
          sellerId: data['seller_id'] as String? ?? '',
          sellerName: data['user_name'] as String? ?? 'Không rõ',
          saleDate: data['time'] as String? ?? 'Không rõ',
          products: products,
          totalAmount: total,
          paymentMethod: (method != null && method.isNotEmpty) ? method : null,
        );
      }).toList();

      final productSet = <String>{};
      final methodSet = <String>{};
      for (final sale in sales) {
        for (final p in sale.products) {
          final pName = p['product_name']?.toString();
          if (pName != null && pName.isNotEmpty) productSet.add(pName);
        }
        if (sale.paymentMethod != null) {
          methodSet.add(sale.paymentMethod!);
        }
      }

      if (!mounted) return;
      setState(() {
        _userRole = role;
        _originalSales = sales;
        _filteredSales = sales;
        _availableProducts = productSet;
        _availablePaymentMethods = methodSet;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi khi tải dữ liệu: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredSales = _originalSales.where((sale) {
        if (_selectedStaffIds.isNotEmpty &&
            !_selectedStaffIds.contains(sale.sellerId)) {
          return false;
        }

        if (_selectedDate != null) {
          final dateStr = _dateFormat.format(_selectedDate!);
          if (!sale.saleDate.startsWith(dateStr)) return false;
        }

        if (_selectedDateRange != null) {
          try {
            final parsed = _dateTimeFormat.parse(sale.saleDate);
            final start = DateTime(
              _selectedDateRange!.start.year,
              _selectedDateRange!.start.month,
              _selectedDateRange!.start.day,
            );
            final end = DateTime(
              _selectedDateRange!.end.year,
              _selectedDateRange!.end.month,
              _selectedDateRange!.end.day,
              23,
              59,
              59,
            );
            if (parsed.isBefore(start) || parsed.isAfter(end)) return false;
          } catch (_) {
            return false;
          }
        }

        if (_selectedPaymentMethod != null &&
            sale.paymentMethod != _selectedPaymentMethod) {
          return false;
        }

        if (_selectedProduct != null &&
            !sale.products.any((p) => p['product_name'] == _selectedProduct)) {
          return false;
        }

        return true;
      }).toList();
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedStaffIds = {};
      _selectedDate = null;
      _selectedDateRange = null;
      _selectedPaymentMethod = null;
      _selectedProduct = null;
      _filteredSales = _originalSales;
    });
  }

  Future<void> _openFilterHubDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bộ lọc đơn hàng',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Chọn tiêu chí để xem đúng dữ liệu bạn cần.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              if (_userRole == 'ADMIN') ...[
                _FilterOptionTile(
                  icon: Icons.people_outline_rounded,
                  label: 'Lọc theo nhân viên',
                  active: _selectedStaffIds.isNotEmpty,
                  onTap: () => Navigator.pop(dialogContext, 'staff'),
                ),
                const SizedBox(height: 8),
              ],
              _FilterOptionTile(
                icon: Icons.calendar_today_outlined,
                label: 'Lọc theo ngày cụ thể',
                active: _selectedDate != null,
                onTap: () => Navigator.pop(dialogContext, 'date'),
              ),
              const SizedBox(height: 8),
              _FilterOptionTile(
                icon: Icons.date_range_outlined,
                label: 'Lọc theo khoảng ngày',
                active: _selectedDateRange != null,
                onTap: () => Navigator.pop(dialogContext, 'range'),
              ),
              const SizedBox(height: 8),
              _FilterOptionTile(
                icon: Icons.payments_outlined,
                label: 'Lọc theo phương thức thanh toán',
                active: _selectedPaymentMethod != null,
                onTap: () => Navigator.pop(dialogContext, 'payment'),
              ),
              const SizedBox(height: 8),
              _FilterOptionTile(
                icon: Icons.local_cafe_outlined,
                label: 'Lọc theo sản phẩm',
                active: _selectedProduct != null,
                onTap: () => Navigator.pop(dialogContext, 'product'),
              ),
              const SizedBox(height: 16),
              MeowSecondaryButton(
                label: 'Xóa tất cả bộ lọc',
                textColor: AppColors.danger,
                backgroundColor: AppColors.dangerSoft,
                borderColor: const Color(0xFFFECDD3),
                onPressed: () => Navigator.pop(dialogContext, 'clear'),
              ),
              const SizedBox(height: 8),
              MeowSecondaryButton(
                label: 'Đóng',
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    switch (choice) {
      case 'staff':
        await _openStaffFilterDialog();
        break;
      case 'date':
        await _openSingleDatePicker();
        break;
      case 'range':
        await _openDateRangePicker();
        break;
      case 'payment':
        await _openRadioFilterDialog(
          title: 'Phương thức thanh toán',
          options: _availablePaymentMethods.toList(),
          currentValue: _selectedPaymentMethod,
          onApply: (val) {
            _selectedPaymentMethod = val;
            _applyFilters();
          },
        );
        break;
      case 'product':
        await _openRadioFilterDialog(
          title: 'Chọn sản phẩm',
          options: _availableProducts.toList(),
          currentValue: _selectedProduct,
          onApply: (val) {
            _selectedProduct = val;
            _applyFilters();
          },
        );
        break;
      case 'clear':
        _clearFilters();
        break;
    }
  }

  Future<void> _openStaffFilterDialog() async {
    try {
      final snapshot = await _firestore
          .collection('uSer')
          .where('role', isEqualTo: 'Nhân Viên')
          .get();
      if (!mounted) return;
      final staff = snapshot.docs
          .map((d) => MapEntry(d.id, d.data()['name'] as String? ?? 'Không rõ'))
          .toList();

      final tempSelected = Set<String>.from(_selectedStaffIds);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text(
              'Chọn nhân viên',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: staff.isEmpty
                  ? const Text('Không có nhân viên nào')
                  : ListView(
                      shrinkWrap: true,
                      children: staff
                          .map(
                            (entry) => CheckboxListTile(
                              activeColor: AppColors.brand,
                              title: Text(entry.value),
                              value: tempSelected.contains(entry.key),
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    tempSelected.add(entry.key);
                                  } else {
                                    tempSelected.remove(entry.key);
                                  }
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _selectedStaffIds = tempSelected;
                  _applyFilters();
                },
                child: const Text('Áp dụng'),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải nhân viên: $e')),
        );
      }
    }
  }

  Future<void> _openSingleDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _selectedDate = picked;
      _selectedDateRange = null;
      _applyFilters();
    }
  }

  Future<void> _openDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _selectedDateRange = picked;
      _selectedDate = null;
      _applyFilters();
    }
  }

  Future<void> _openRadioFilterDialog({
    required String title,
    required List<String> options,
    required String? currentValue,
    required ValueChanged<String?> onApply,
  }) async {
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu để lọc')),
      );
      return;
    }

    var temp = currentValue;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: RadioGroup<String>(
              groupValue: temp,
              onChanged: (value) => setDialogState(() => temp = value),
              child: ListView(
                shrinkWrap: true,
                children: options
                    .map(
                      (opt) => RadioListTile<String>(
                        activeColor: AppColors.brand,
                        title: Text(opt),
                        value: opt,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onApply(null);
              },
              child: const Text('Bỏ lọc'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onApply(temp);
              },
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalRevenue =
        _filteredSales.fold<double>(0.0, (total, s) => total + s.totalAmount);
    final isAdmin = _userRole == 'ADMIN';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: const MeowHeader(title: 'Thống Kê'),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: MeowCard(
                      color: AppColors.dangerSoft,
                      borderColor: const Color(0xFFFECDD3),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      MeowEditorialHero(
                        eyebrow: 'MEOW COFFEE',
                        title: isAdmin
                            ? 'Thống kê toàn hệ thống'
                            : 'Đơn hàng của bạn',
                        subtitle: 'Tổng quan đơn hàng và doanh thu cửa hàng.',
                      ),
                      const SizedBox(height: 16),
                      if (_userRole != null) ...[
                        MeowSecondaryButton(
                          label: 'Bộ lọc đơn hàng',
                          icon: Icons.filter_list_rounded,
                          onPressed: _openFilterHubDialog,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF30223F),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TỔNG DOANH THU',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFEDE4F6),
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              formatVnd(totalRevenue, suffix: 'đ'),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF5D49E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_filteredSales.length} đơn hàng',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFEDE4F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'ĐƠN HÀNG GẦN ĐÂY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_filteredSales.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.bar_chart_rounded,
                                  size: 56,
                                  color: AppColors.mutedLight,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Không có đơn hàng nào',
                                  style: TextStyle(color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        for (final sale in _filteredSales) ...[
                          _SaleCard(sale: sale, isAdmin: isAdmin),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
    );
  }
}

class _FilterOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterOptionTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.soft : AppColors.bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: active ? AppColors.brand : AppColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? AppColors.brand : AppColors.ink,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: active ? AppColors.brand : AppColors.mutedLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final _SaleDetail sale;
  final bool isAdmin;

  const _SaleCard({
    required this.sale,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return MeowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sale.saleDate,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              Text(
                formatVnd(sale.totalAmount, suffix: 'đ'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (isAdmin) 'Nhân viên: ${sale.sellerName}',
              if (sale.paymentMethod != null) sale.paymentMethod!,
            ].join(' • '),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (sale.products.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...sale.products.map((p) {
              final name = p['product_name']?.toString() ?? '';
              final qty = p['quantity'] ?? 1;
              final price = (p['price'] is num)
                  ? (p['price'] as num).toDouble()
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$name × $qty',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    Text(
                      formatVnd(
                        price * (qty is num ? qty.toDouble() : 1),
                        suffix: 'đ',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          const Text(
            'Đã thanh toán',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
