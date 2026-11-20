class SaleData {
  final String orderId;
  final String sellerName;
  final String saleDate;
  final String product;
  final int quantity;
  final double price;
  final String paymentMethod;

  const SaleData({
    required this.orderId,
    required this.sellerName,
    required this.saleDate,
    required this.product,
    required this.quantity,
    required this.price,
    required this.paymentMethod,
  });
}
