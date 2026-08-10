import 'package:flutter_test/flutter_test.dart';
import 'package:hello_app/order_data.dart';

void main() {
  group('OrderData', () {
    test('normalizes current TellMe order fields', () {
      final order = OrderData({
        'orderNumber': 'TM-10428',
        'status': 'in_transit',
        'paymentStatus': 'paid',
        'paymentMethod': 'wallet',
        'currency': 'NGN',
        'totalAmount': 27500,
        'shippingAmount': 2500,
        'createdAt': '2026-08-10T12:30:00Z',
        'items': [
          {
            'productName': 'Stylish Everyday Tote',
            'variantName': 'Black',
            'sku': 'TELLME522278',
            'quantity': 1,
            'unitAmount': 25000,
            'imageUrl': 'https://tellme.ng/product.jpg',
          },
        ],
        'shipment': {
          'carrier': 'TellMe Logistics',
          'trackingNumber': 'TML-9001',
          'status': 'in_transit',
        },
        'shippingAddress': {
          'recipientName': 'Adepitan Bero',
          'addressLine1': '30 Akinhanmi Street',
          'city': 'Ikom',
          'state': 'Cross River',
          'countryCode': 'NG',
        },
      });

      expect(order.orderNumber, 'TM-10428');
      expect(order.statusLabel, 'In Transit');
      expect(order.total, 27500);
      expect(order.shippingTotal, 2500);
      expect(order.itemCount, 1);
      expect(order.items.single['totalAmount'], 25000);
      expect(order.trackingNumber, 'TML-9001');
      expect(order.shipped, isTrue);
      expect(order.addressText, contains('Cross River'));
    });

    test('normalizes legacy WooCommerce order fields', () {
      final order = OrderData({
        'number': '10427',
        'status': 'processing',
        'currency': 'NGN',
        'total': '21800.00',
        'shipping_total': '1800.00',
        'payment_method_title': 'Bank transfer',
        'date_created': '2026-08-09T10:20:00',
        'line_items': [
          {
            'name': 'Laptop Stand',
            'sku': 'TELLME634216',
            'quantity': 2,
            'price': '10000.00',
            'total': '20000.00',
          },
        ],
        'shipping': {
          'first_name': 'Adepitan',
          'last_name': 'Bero',
          'address_1': '30 Akinhanmi Street',
          'city': 'Ikom',
          'state': 'Cross River',
          'country': 'NG',
        },
      });

      expect(order.orderNumber, '10427');
      expect(order.total, 21800);
      expect(order.paymentMethod, 'Bank transfer');
      expect(order.items.single['name'], 'Laptop Stand');
      expect(order.recipientName, 'Adepitan Bero');
      expect(order.processingStarted, isTrue);
    });
  });
}
