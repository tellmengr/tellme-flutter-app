import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'cart_provider.dart';
import 'order_data.dart';
import 'order_tracking_page.dart';
import 'user_provider.dart';

class OrderConfirmationPage extends StatelessWidget {
  final Map<String, dynamic> orderDetails;

  const OrderConfirmationPage({
    super.key,
    required this.orderDetails,
  });

  dynamic _first(List<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null' && text != 'N/A') {
        return value;
      }
    }
    return null;
  }

  dynamic _nested(String parent, String child) {
    final value = orderDetails[parent];
    return value is Map ? value[child] : null;
  }

  String _orderNumber() {
    final value = _first([
      orderDetails['displayOrderNumber'],
      orderDetails['orderNumber'],
      orderDetails['order_number'],
      orderDetails['number'],
      orderDetails['reference'],
      orderDetails['id'],
    ]);
    if (value == null) return 'N/A';
    final text = value.toString().trim();
    if (RegExp(r'^[a-f0-9]{24,}$', caseSensitive: false).hasMatch(text)) {
      return '#${text.substring(0, 8).toUpperCase()}';
    }
    if (text.startsWith('WC-')) return '#${text.substring(3)}';
    return text.startsWith('#') ? text : '#$text';
  }

  String _status() {
    final raw = (_first([
              orderDetails['displayStatus'],
              orderDetails['status'],
              orderDetails['payment_status'],
              orderDetails['paymentStatus'],
              _nested('payment', 'status'),
            ]) ??
            'Order Received')
        .toString();
    return raw
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  String _date() {
    final raw = _first([
      orderDetails['date_created'],
      orderDetails['createdAt'],
      orderDetails['created_at'],
      orderDetails['orderDate'],
      orderDetails['date'],
    ]);
    final parsed = raw == null ? null : DateTime.tryParse(raw.toString());
    return (parsed ?? DateTime.now()).toLocal().toString().split(' ')[0];
  }

  double _amount() {
    final raw = _first([
      orderDetails['displayTotal'],
      orderDetails['total'],
      orderDetails['grandTotal'],
      orderDetails['amount'],
      orderDetails['order_total'],
      _nested('payment', 'amount'),
      orderDetails['totalAmount'],
    ]);
    if (raw is num) return raw.toDouble();
    return double.tryParse(
          (raw ?? '0').toString().replaceAll(RegExp(r'[^0-9.]'), ''),
        ) ??
        0;
  }

  String _currency(double amount) {
    final formatted = amount.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    return '\u20A6$formatted';
  }

  String _paymentMethod() {
    return (_first([
              orderDetails['displayPaymentMethod'],
              orderDetails['payment_method_title'],
              orderDetails['paymentMethodTitle'],
              orderDetails['payment_method'],
              orderDetails['paymentMethod'],
              _nested('payment', 'method'),
            ]) ??
            'N/A')
        .toString();
  }

  bool get _isBankTransfer {
    final method = _paymentMethod().toLowerCase();
    return method.contains('bank') ||
        method.contains('transfer') ||
        method.contains('bacs');
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context, listen: false);
    final cart = Provider.of<CartProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Order Confirmation'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle,
                    size: 78, color: Colors.green),
              ),
              const SizedBox(height: 24),
              Text(
                'Order Placed Successfully!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Thank you for your order, ${user.userDisplayName}!',
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              _detailsCard(context),
              if (_isBankTransfer) ...[
                const SizedBox(height: 20),
                _bankTransferCard(context),
              ],
              const SizedBox(height: 20),
              _nextCard(),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        cart.clearCart();
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/', (_) => false);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: const Text('Continue Shopping',
                          textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderTrackingPage(
                            orderNumber: OrderData(orderDetails).orderNumber,
                            initialOrder: orderDetails,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: const Text('Track Order'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsCard(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order Details',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _row('Order Number:', _orderNumber()),
            _row('Status:', _status(), color: Colors.orange),
            _row('Order Date:', _date()),
            _row('Total Amount:', _currency(_amount()),
                color: Colors.green, bold: true),
            _row('Payment Method:', _paymentMethod()),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 116,
              child: Text(label, style: TextStyle(color: Colors.grey[700]))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bankTransferCard(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bank Transfer Details',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Bank: Guaranty Trust Bank'),
            const Text('Account Name: Tell Me Limited'),
            const Text('Account Number: 0601734295'),
            const SizedBox(height: 10),
            const Text('Use your order number as the transfer reference.'),
          ],
        ),
      ),
    );
  }

  Widget _nextCard() {
    return Card(
      color: Colors.blueGrey.shade50,
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("What's Next?",
                style:
                    TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text('You will receive an email confirmation shortly.'),
            Text('We will process your order within 1-2 business days.'),
            Text('Tracking information will be sent by email.'),
          ],
        ),
      ),
    );
  }
}
