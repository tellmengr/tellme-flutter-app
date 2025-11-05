import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cart_provider.dart';
import 'user_provider.dart';

class OrderConfirmationPage extends StatelessWidget {
  final Map<String, dynamic> orderDetails;

  const OrderConfirmationPage({
    Key? key,
    required this.orderDetails,
  }) : super(key: key);

  /// ✅ Currency formatter for Naira
  String formatCurrency(dynamic amount) {
    if (amount == null) return '₦0';
    String str = amount.toString();

    str = str.replaceAll('\$', '₦');

    try {
      double value =
          double.tryParse(str.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      final formatted = value.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      return '₦$formatted';
    } catch (_) {
      return '₦$str';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    // Detect payment type (ensure not Paystack)
    final paymentMethod =
        orderDetails['payment_method']?.toString().toLowerCase() ?? '';
    final paymentTitle =
        orderDetails['payment_method_title']?.toString().toLowerCase() ?? '';

    final isBankTransfer = (paymentMethod.contains('bank') ||
            paymentMethod.contains('bacs') ||
            paymentTitle.contains('bank transfer')) &&
        !paymentTitle.contains('paystack') &&
        !paymentMethod.contains('paystack');

    // 💰 Company account details
    const bankDetails = {
      'bank_name': 'Guaranty Trust Bank',
      'account_name': 'Tell Me Limited',
      'account_number': '0601734295',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Confirmation'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),

            // ✅ Success Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 80,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Order Placed Successfully!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            Text(
              'Thank you for your order, ${userProvider.userDisplayName}!',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // ✅ Order Details
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow('Order Number:',
                        '#${orderDetails['id'] ?? 'N/A'}', context),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Status:',
                      orderDetails['status']?.toString().toUpperCase() ??
                          'PENDING',
                      context,
                      valueColor: Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Order Date:',
                      orderDetails['date_created'] != null
                          ? DateTime.parse(orderDetails['date_created'])
                              .toString()
                              .split(' ')[0]
                          : DateTime.now().toString().split(' ')[0],
                      context,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Total Amount:',
                      formatCurrency(orderDetails['total']),
                      context,
                      valueColor: Colors.green,
                      isAmount: true,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      'Payment Method:',
                      orderDetails['payment_method_title'] ??
                          orderDetails['payment_method'] ??
                          'N/A',
                      context,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ✅ Show Bank Details if payment method is Bank Transfer
            if (isBankTransfer)
              Card(
                elevation: 3,
                color: Colors.blue.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.account_balance, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            'Bank Transfer Instructions',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Please make payment to the account below:',
                        style: TextStyle(color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      _buildBankRow('Bank Name', bankDetails['bank_name']!),
                      _buildBankRow('Account Name', bankDetails['account_name']!),
                      _buildBankRow('Account Number', bankDetails['account_number']!),
                      const SizedBox(height: 12),
                      const Text(
                        'After payment, please reply your confirmation email or contact support with your proof of payment.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            if (isBankTransfer) const SizedBox(height: 24),

            // ✅ Order Items
            if (orderDetails['line_items'] != null) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Items',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      ...((orderDetails['line_items'] as List).map((item) =>
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item['name']} (x${item['quantity']})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                                Text(
                                  formatCurrency(item['total']),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ✅ What's Next
            Card(
              elevation: 2,
              color: Colors.blue.withOpacity(0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "What's Next?",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      '• You will receive an email confirmation shortly\n'
                      '• We will process your order within 1-2 business days\n'
                      '• Tracking information will be sent via email\n'
                      '• Expected delivery: 3-5 business days',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // ✅ Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      cartProvider.clearCart();
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/',
                        (route) => false,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue Shopping',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Order tracking feature coming soon!'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Track Order',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    BuildContext context, {
    Color? valueColor,
    bool isAmount = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[600]),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: isAmount ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? Colors.grey[800],
                fontSize: isAmount ? 16 : null,
              ),
        ),
      ],
    );
  }

  Widget _buildBankRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w500, color: Colors.black87),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
