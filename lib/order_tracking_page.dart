import 'package:flutter/material.dart';

import 'order_data.dart';
import 'tellme_account_api.dart';

const _trackingBlue = Color(0xFF0759B8);
const _trackingGreen = Color(0xFF0A9B69);

class OrderTrackingPage extends StatefulWidget {
  final String orderNumber;
  final Map<String, dynamic>? initialOrder;

  const OrderTrackingPage({
    super.key,
    required this.orderNumber,
    this.initialOrder,
  });

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  final TellmeAccountApi _api = TellmeAccountApi();
  Map<String, dynamic>? _order;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fresh = await _api.getOrderByNumber(widget.orderNumber);
      if (!mounted) return;
      setState(() {
        if (fresh != null) _order = fresh;
        if (_order == null) _error = 'This order could not be found.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_order == null) {
          _error = error.toString().replaceFirst('Exception: ', '');
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order == null ? null : OrderData(_order!);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0B1F33),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh order',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: order == null
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _orderHeader(order),
                  const SizedBox(height: 12),
                  _progressCard(order),
                  const SizedBox(height: 12),
                  if (order.trackingNumber.isNotEmpty) ...[
                    _shipmentCard(order),
                    const SizedBox(height: 12),
                  ],
                  _itemsCard(order),
                  const SizedBox(height: 12),
                  _paymentCard(order),
                  if (order.addressText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _addressCard(order),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined,
                size: 56, color: _trackingBlue),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Loading order...',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderHeader(OrderData order) {
    final statusColor = order.cancelled ? Colors.red : _trackingGreen;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORDER NUMBER',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF65778A))),
                    const SizedBox(height: 4),
                    Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0B1F33),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  order.statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 16, color: Color(0xFF65778A)),
              const SizedBox(width: 7),
              Text(_date(order.createdAt),
                  style: const TextStyle(color: Color(0xFF65778A))),
              const Spacer(),
              Text(
                _money(order.total, order.currency),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _trackingBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressCard(OrderData order) {
    final steps = [
      ('Order placed', true),
      ('Payment confirmed', order.paymentConfirmed),
      ('Processing', order.processingStarted),
      ('Shipped', order.shipped),
      ('Delivered', order.delivered),
    ];

    return _section(
      title: order.cancelled ? 'Order update' : 'Delivery progress',
      child: order.cancelled
          ? Row(
              children: [
                const Icon(Icons.cancel_outlined, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This order is ${order.statusLabel.toLowerCase()}.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          : Column(
              children: List.generate(steps.length, (index) {
                final step = steps[index];
                final active = step.$2;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active
                                ? _trackingGreen
                                : const Color(0xFFE3EAF2),
                          ),
                          child: Icon(
                            active ? Icons.check : Icons.circle,
                            size: active ? 16 : 7,
                            color:
                                active ? Colors.white : const Color(0xFF8FA0B2),
                          ),
                        ),
                        if (index < steps.length - 1)
                          Container(
                            width: 2,
                            height: 30,
                            color: steps[index + 1].$2
                                ? _trackingGreen
                                : const Color(0xFFE3EAF2),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        step.$1,
                        style: TextStyle(
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? const Color(0xFF0B1F33)
                              : const Color(0xFF8797A8),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
    );
  }

  Widget _shipmentCard(OrderData order) {
    return _section(
      title: 'Shipment',
      child: Column(
        children: [
          _detailRow('Tracking number', order.trackingNumber),
          if (order.carrier.isNotEmpty) _detailRow('Carrier', order.carrier),
          if (order.shipmentStatusKey.isNotEmpty)
            _detailRow(
              'Shipment status',
              OrderData.label(order.shipmentStatusKey),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard(OrderData order) {
    return _section(
      title: 'Items (${order.itemCount})',
      child: order.items.isEmpty
          ? const Text('Item details will appear when processing begins.',
              style: TextStyle(color: Color(0xFF65778A)))
          : Column(
              children: order.items.map((item) {
                final imageUrl = item['imageUrl']?.toString() ?? '';
                final variant = item['variant']?.toString() ?? '';
                final sku = item['sku']?.toString() ?? '';
                final total = (item['totalAmount'] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: imageUrl.isEmpty
                            ? const Icon(Icons.shopping_bag_outlined,
                                color: Color(0xFF8797A8))
                            : Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Color(0xFF8797A8)),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'].toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            if (variant.isNotEmpty)
                              Text(variant,
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF65778A))),
                            if (sku.isNotEmpty)
                              Text('SKU: $sku',
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF8797A8))),
                            const SizedBox(height: 4),
                            Text('Qty: ${item['quantity']}',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      if (total > 0)
                        Text(_money(total, order.currency),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _paymentCard(OrderData order) {
    final subtotal = order.subtotal > 0
        ? order.subtotal
        : (order.total - order.shippingTotal + order.discountTotal)
            .clamp(0, double.infinity)
            .toDouble();
    return _section(
      title: 'Payment summary',
      child: Column(
        children: [
          _detailRow('Payment method', order.paymentMethod),
          _detailRow('Payment status', order.paymentStatusLabel),
          const Divider(height: 24),
          _moneyRow('Subtotal', subtotal, order.currency),
          if (order.shippingTotal > 0)
            _moneyRow('Shipping', order.shippingTotal, order.currency),
          if (order.discountTotal > 0)
            _moneyRow('Discount', -order.discountTotal, order.currency),
          if (order.taxTotal > 0)
            _moneyRow('Tax', order.taxTotal, order.currency),
          const Divider(height: 24),
          _moneyRow('Total', order.total, order.currency, strong: true),
        ],
      ),
    );
  }

  Widget _addressCard(OrderData order) {
    return _section(
      title: 'Delivery address',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, color: _trackingBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.recipientName.isNotEmpty)
                  Text(order.recipientName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(order.addressText,
                    style: const TextStyle(
                        height: 1.45, color: Color(0xFF65778A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1F33))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child:
                Text(label, style: const TextStyle(color: Color(0xFF65778A))),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double amount, String currency,
      {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w400))),
          Text(
            _money(amount, currency),
            style: TextStyle(
              fontSize: strong ? 17 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? _trackingBlue : const Color(0xFF0B1F33),
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return 'Date unavailable';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}, '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _money(double amount, String currency) {
    final formatted = amount.toStringAsFixed(2).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
    return currency.toUpperCase() == 'NGN'
        ? '\u20A6$formatted'
        : '${currency.toUpperCase()} $formatted';
  }
}
