import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/formatters.dart';

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
            title: const Text('Chọn nhân viên để lọc'),
            content: SizedBox(
              width: double.maxFinite,
              child: staff.isEmpty
                  ? const Text('Không có nhân viên nào')
                  : ListView(
                      shrinkWrap: true,
                      children: staff
                          .map(
                            (entry) => CheckboxListTile(
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
          title: Text(title),
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
    final colorScheme = Theme.of(context).colorScheme;
    final totalRevenue =
        _filteredSales.fold<double>(0.0, (total, s) => total + s.totalAmount);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          _userRole == 'ADMIN' ? 'Thống kê toàn hệ thống' : 'Đơn hàng của bạn',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_userRole != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.filter_list, color: Colors.white),
              onSelected: (value) {
                switch (value) {
                  case 'staff':
                    _openStaffFilterDialog();
                    break;
                  case 'date':
                    _openSingleDatePicker();
                    break;
                  case 'range':
                    _openDateRangePicker();
                    break;
                  case 'payment':
                    _openRadioFilterDialog(
                      title: 'Chọn phương thức thanh toán',
                      options: _availablePaymentMethods.toList(),
                      currentValue: _selectedPaymentMethod,
                      onApply: (val) {
                        _selectedPaymentMethod = val;
                        _applyFilters();
                      },
                    );
                    break;
                  case 'product':
                    _openRadioFilterDialog(
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
              },
              itemBuilder: (_) => [
                if (_userRole == 'ADMIN')
                  const PopupMenuItem(
                    value: 'staff',
                    child: Text('Lọc theo nhân viên'),
                  ),
                const PopupMenuItem(
                  value: 'date',
                  child: Text('Lọc theo ngày cụ thể'),
                ),
                const PopupMenuItem(
                  value: 'range',
                  child: Text('Lọc theo khoảng ngày'),
                ),
                const PopupMenuItem(
                  value: 'payment',
                  child: Text('Lọc theo phương thức thanh toán'),
                ),
                const PopupMenuItem(
                  value: 'product',
                  child: Text('Lọc theo sản phẩm'),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Xóa bộ lọc'),
                ),
              ],
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Card(
                      color: colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_filteredSales.isNotEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                title: 'Tổng đơn',
                                value: _filteredSales.length.toString(),
                                icon: Icons.receipt,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                title: 'Doanh thu',
                                value: formatVnd(totalRevenue, suffix: 'đ'),
                                icon: Icons.monetization_on,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Expanded(
                        child: _filteredSales.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.bar_chart,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Không có đơn hàng nào',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadData,
                                child: ListView.separated(
                                  itemCount: _filteredSales.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final sale = _filteredSales[index];
                                    return _SaleCard(
                                      sale: sale,
                                      isAdmin: _userRole == 'ADMIN',
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary, size: 22),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ],
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
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  sale.saleDate,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  formatVnd(sale.totalAmount, suffix: 'đ'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (isAdmin) ...[
              const SizedBox(height: 4),
              Text(
                'Nhân viên: ${sale.sellerName}',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
            if (sale.paymentMethod != null) ...[
              const SizedBox(height: 2),
              Text(
                'Thanh toán: ${sale.paymentMethod}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
            if (sale.products.isNotEmpty) ...[
              const Divider(height: 14),
              ...sale.products.map((p) {
                final name = p['product_name']?.toString() ?? '';
                final qty = p['quantity'] ?? 1;
                final price = (p['price'] is num)
                    ? (p['price'] as num).toDouble()
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text('$name x$qty')),
                      Text(formatVnd(price * (qty is num ? qty.toDouble() : 1),
                          suffix: 'đ')),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
