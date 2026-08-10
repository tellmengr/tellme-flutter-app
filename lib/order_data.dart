class OrderData {
  final Map<String, dynamic> raw;

  const OrderData(this.raw);

  dynamic _first(Iterable<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      if (value is String &&
          (value.trim().isEmpty || value.trim().toLowerCase() == 'null')) {
        continue;
      }
      return value;
    }
    return null;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.map(
              (key, child) => MapEntry(key.toString(), child),
            ))
        .toList();
  }

  double _amount(Iterable<dynamic> values) {
    final value = _first(values);
    if (value is num) return value.toDouble();
    if (value is Map) {
      return _amount([
        value['amount'],
        value['value'],
        value['total'],
      ]);
    }
    return double.tryParse(
          (value ?? '0').toString().replaceAll(RegExp(r'[^0-9.-]'), ''),
        ) ??
        0;
  }

  String get orderNumber => (_first([
            raw['displayOrderNumber'],
            raw['orderNumber'],
            raw['order_number'],
            raw['number'],
            raw['reference'],
            _map(raw['order'])['orderNumber'],
            raw['id'],
          ]) ??
          'N/A')
      .toString()
      .replaceFirst(RegExp(r'^#'), '');

  String get id => (_first([
            raw['id'],
            raw['orderId'],
            raw['order_id'],
            _map(raw['order'])['id'],
          ]) ??
          orderNumber)
      .toString();

  String get statusKey => (_first([
            raw['status'],
            raw['orderStatus'],
            raw['order_status'],
            raw['displayStatus'],
            _map(raw['order'])['status'],
          ]) ??
          'pending')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_');

  String get statusLabel => label(statusKey);

  String get paymentStatusKey {
    final payments = _maps(raw['payments']);
    return (_first([
              raw['paymentStatus'],
              raw['payment_status'],
              _map(raw['payment'])['status'],
              payments.isEmpty ? null : payments.first['status'],
            ]) ??
            'pending')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');
  }

  String get paymentStatusLabel => label(paymentStatusKey);

  String get paymentMethod => (_first([
            raw['displayPaymentMethod'],
            raw['paymentMethodTitle'],
            raw['payment_method_title'],
            raw['paymentMethod'],
            raw['payment_method'],
            _map(raw['payment'])['method'],
            _map(raw['payment'])['provider'],
            _maps(raw['payments']).isEmpty
                ? null
                : _maps(raw['payments']).first['provider'],
          ]) ??
          'Not specified')
      .toString();

  String get currency => (_first([
            raw['currency'],
            raw['currencyCode'],
            raw['currency_code'],
            _map(raw['totalAmount'])['currency'],
          ]) ??
          'NGN')
      .toString();

  DateTime? get createdAt {
    final value = _first([
      raw['createdAt'],
      raw['created_at'],
      raw['date_created'],
      raw['orderDate'],
      raw['date'],
    ]);
    return value == null
        ? null
        : DateTime.tryParse(value.toString())?.toLocal();
  }

  DateTime? get updatedAt {
    final value = _first([
      raw['updatedAt'],
      raw['updated_at'],
      raw['date_modified'],
    ]);
    return value == null
        ? null
        : DateTime.tryParse(value.toString())?.toLocal();
  }

  double get total => _amount([
        raw['displayTotal'],
        raw['total'],
        raw['grandTotal'],
        raw['grand_total'],
        raw['amount'],
        raw['order_total'],
        raw['totalAmount'],
        _map(raw['order'])['totalAmount'],
      ]);

  double get subtotal => _amount([
        raw['subtotal'],
        raw['subtotalAmount'],
        raw['subtotal_amount'],
        _map(raw['order'])['subtotalAmount'],
      ]);

  double get shippingTotal => _amount([
        raw['shippingTotal'],
        raw['shipping_total'],
        raw['shippingAmount'],
        raw['shipping_amount'],
        _map(raw['order'])['shippingAmount'],
      ]);

  double get discountTotal => _amount([
        raw['discountTotal'],
        raw['discount_total'],
        raw['discountAmount'],
        raw['discount_amount'],
      ]);

  double get taxTotal => _amount([
        raw['taxTotal'],
        raw['total_tax'],
        raw['taxAmount'],
        raw['tax_amount'],
      ]);

  List<Map<String, dynamic>> get items {
    final source = _first([
      raw['items'],
      raw['lineItems'],
      raw['line_items'],
      _map(raw['order'])['items'],
    ]);
    return _maps(source).map((item) {
      final image = _first([
        item['imageUrl'],
        item['image_url'],
        item['image'],
        _map(item['image'])['src'],
      ]);
      return {
        ...item,
        'name': _first([
              item['name'],
              item['productName'],
              item['product_name'],
            ]) ??
            'Product',
        'variant': _first([
          item['variantName'],
          item['variant_name'],
          item['variation'],
        ]),
        'sku': _first([item['sku'], item['productSku'], item['product_sku']]),
        'quantity': int.tryParse((_first([
                      item['quantity'],
                      item['qty'],
                    ]) ??
                    1)
                .toString()) ??
            1,
        'unitAmount': _amount([
          item['unitAmount'],
          item['unit_amount'],
          item['price'],
        ]),
        'totalAmount': _itemTotal(item),
        'imageUrl': image?.toString(),
      };
    }).toList();
  }

  double _itemTotal(Map<String, dynamic> item) {
    final explicit = _amount([
      item['totalAmount'],
      item['total_amount'],
      item['total'],
    ]);
    if (explicit > 0) return explicit;
    final quantity = int.tryParse(
          (_first([item['quantity'], item['qty']]) ?? 1).toString(),
        ) ??
        1;
    return _amount([
          item['unitAmount'],
          item['unit_amount'],
          item['price'],
        ]) *
        quantity;
  }

  int get itemCount {
    final explicit = int.tryParse((_first([
              raw['itemCount'],
              raw['item_count'],
            ]) ??
            '')
        .toString());
    return explicit ??
        items.fold(0, (sum, item) => sum + (item['quantity'] as int));
  }

  Map<String, dynamic> get shippingAddress => _map(_first([
        raw['shippingAddress'],
        raw['shipping_address'],
        raw['shipping'],
      ]));

  Map<String, dynamic> get billingAddress => _map(_first([
        raw['billingAddress'],
        raw['billing_address'],
        raw['billing'],
      ]));

  Map<String, dynamic> get shipment => _map(raw['shipment']);

  String get trackingNumber => (_first([
            shipment['trackingNumber'],
            shipment['tracking_number'],
            raw['trackingNumber'],
            raw['tracking_number'],
          ]) ??
          '')
      .toString();

  String get carrier => (_first([
            shipment['carrier'],
            raw['carrier'],
          ]) ??
          '')
      .toString();

  String get shipmentStatusKey => (_first([
            shipment['status'],
            raw['shipmentStatus'],
            raw['shipment_status'],
          ]) ??
          '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_');

  String get recipientName => (_first([
            shippingAddress['recipientName'],
            shippingAddress['recipient_name'],
            [shippingAddress['first_name'], shippingAddress['last_name']]
                .where((value) =>
                    value != null && value.toString().trim().isNotEmpty)
                .join(' '),
            billingAddress['recipientName'],
          ]) ??
          '')
      .toString();

  String get addressText {
    final address =
        shippingAddress.isNotEmpty ? shippingAddress : billingAddress;
    final values = [
      _first([
        address['addressLine1'],
        address['address_line_1'],
        address['address_1']
      ]),
      _first([
        address['addressLine2'],
        address['address_line_2'],
        address['address_2']
      ]),
      _first([address['city']]),
      _first([address['state']]),
      _first([
        address['countryCode'],
        address['country_code'],
        address['country']
      ]),
    ];
    return values
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString().trim())
        .join(', ');
  }

  bool get paymentConfirmed =>
      const {
        'paid',
        'captured',
        'completed',
        'complete',
        'successful',
        'success',
      }.contains(paymentStatusKey) ||
      const {'processing', 'shipped', 'delivered', 'completed'}
          .contains(statusKey);

  bool get processingStarted =>
      const {
        'processing',
        'confirmed',
        'paid',
        'payment_received',
        'ready_to_ship',
        'shipped',
        'in_transit',
        'out_for_delivery',
        'delivered',
        'completed',
      }.contains(statusKey) ||
      shipmentStatusKey.isNotEmpty;

  bool get shipped =>
      trackingNumber.isNotEmpty ||
      const {'shipped', 'in_transit', 'out_for_delivery', 'delivered'}
          .contains(shipmentStatusKey) ||
      const {'shipped', 'in_transit', 'out_for_delivery', 'delivered'}
          .contains(statusKey);

  bool get delivered =>
      const {'delivered', 'completed'}.contains(shipmentStatusKey) ||
      const {'delivered', 'completed'}.contains(statusKey);

  bool get cancelled =>
      const {'cancelled', 'canceled', 'failed', 'refunded'}.contains(statusKey);

  static String label(String value) {
    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }
}
