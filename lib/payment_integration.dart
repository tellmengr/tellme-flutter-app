import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'woocommerce_auth_service.dart';

class PaymentIntegration {
  final WooCommerceAuthService wooCommerceService;

  PaymentIntegration({required this.wooCommerceService});

  // ============================================================
  // ✅ ENHANCED PAYMENT PROCESSING - FIXED BANK TRANSFER FLOW
  // ============================================================
  Future<Map<String, dynamic>?> processPayment({
    required String paymentMethod,
    required List<dynamic> cartItems,
    required double totalAmount,
    required BuildContext context,
    String? paymentReference,
    Map<String, dynamic>? customerData,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddress,
  }) async {
    try {
      print('🔄 Processing payment with method: $paymentMethod');
      print('💰 Total amount: ₦$totalAmount');
      print('📦 Number of items: ${cartItems.length}');
      print('👤 Customer data: $customerData');

      // Generate order summary for logging
      final orderSummary = _generateOrderSummary(
        cartItems: cartItems,
        totalAmount: totalAmount,
        paymentMethod: paymentMethod,
      );
      print('📋 Order Summary: $orderSummary');

      Map<String, dynamic>? result;

      switch (paymentMethod) {
        case 'wallet':
          result = await _processWalletPayment(
            cartItems: cartItems,
            totalAmount: totalAmount,
            context: context,
            customerData: customerData,
            billingAddress: billingAddress,
            shippingAddress: shippingAddress,
          );
          break;

        case 'bank_transfer':
        case 'bacs':
          result = await _createOrderAfterPayment(
            paymentMethod: 'bacs',
            cartItems: cartItems,
            totalAmount: totalAmount,
            context: context,
            customerData: customerData,
            billingAddress: billingAddress,
            shippingAddress: shippingAddress,
          );

          // ✅ FIXED: Enhanced bank transfer success handling
          if (result?['success'] == true && result?['orderData']?['id'] != null) {
            print('✅ Bank transfer order created successfully: ${result!['orderData']['id']}');

            // Add specific bank transfer success data
            result['bank_transfer_instructions'] = {
              'message': 'Order created successfully. Please complete bank transfer to process your order.',
              'status': 'awaiting_payment',
              'next_steps': 'Check your email for bank account details and payment instructions.',
              'order_created': true, // Explicit confirmation
            };

            await _triggerOrderConfirmation(result['orderData']['id']);
          } else {
            print('❌ Bank transfer order creation failed: ${result?['message']}');
          }
          break;

        case 'card':
        case 'paystack':
          result = await _createOrderAfterPayment(
            paymentMethod: 'paystack',
            cartItems: cartItems,
            totalAmount: totalAmount,
            context: context,
            paymentReference: paymentReference,
            customerData: customerData,
            billingAddress: billingAddress,
            shippingAddress: shippingAddress,
          );

          // Trigger confirmation email for successful card payments
          if (result?['success'] == true && result?['orderData']?['id'] != null) {
            await _triggerOrderConfirmation(result!['orderData']['id']);
          }
          break;

        default:
          throw Exception('Unsupported payment method: $paymentMethod');
      }

      return result;
    } catch (e) {
      print('❌ Payment processing error: $e');
      final friendlyError = _getFriendlyErrorMessage(e);
      return {
        'success': false,
        'message': friendlyError,
        'error_details': e.toString(),
      };
    }
  }

  // ============================================================
  // ✅ WALLET PAYMENT - FIXED VERSION
  // ============================================================
  Future<Map<String, dynamic>?> _processWalletPayment({
    required List<dynamic> cartItems,
    required double totalAmount,
    required BuildContext context,
    Map<String, dynamic>? customerData,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddress,
  }) async {
    try {
      final int customerId = _getCustomerId(context, customerData);
      print('💰 Processing wallet payment for customer: $customerId');

      final List<Map<String, dynamic>> lineItems = _buildLineItems(cartItems);
      final Map<String, String> billing =
          _buildBillingAddress(context, billingAddress, customerData);
      final Map<String, String> shipping =
          _buildShippingAddress(context, shippingAddress, billingAddress, customerData);

      final paymentResult = await wooCommerceService.processWalletPayment(
        userId: customerId,
        totalAmount: totalAmount,
        lineItems: lineItems,
        billing: billing,
        shipping: shipping,
      );

      print('💰 Wallet payment result: $paymentResult');

      if (paymentResult['success'] == true) {
        print('✅ Wallet payment processed successfully');

        // FIXED: Safely handle order_id which might be string or int
        final dynamic orderId = paymentResult['order_id'];
        final String orderIdString = orderId?.toString() ?? '';
        final int? orderIdInt = _safeParseInt(orderId);

        print('📦 Order created with ID: $orderId (string: $orderIdString, int: $orderIdInt)');

        // Trigger confirmation email for wallet payments
        if (orderIdString.isNotEmpty) {
          final emailOrderId = orderIdInt ?? _safeParseInt(orderIdString) ?? 0;
          if (emailOrderId > 0) {
            await _triggerOrderConfirmation(emailOrderId);
          }
        }

        return {
          'success': true,
          'orderData': paymentResult['order_data'],
          'paymentReference': orderIdString,
          'orderId': orderIdInt,
          'message': 'Wallet payment completed successfully',
          'order_summary': _generateOrderSummary(
            cartItems: cartItems,
            totalAmount: totalAmount,
            paymentMethod: 'wallet',
          ),
        };
      } else {
        // Check if order was created but wallet debit failed
        if (paymentResult['order_created'] == true) {
          final dynamic orderId = paymentResult['order_id'];
          final String orderIdString = orderId?.toString() ?? '';

          return {
            'success': false,
            'order_created': true,
            'order_id': orderIdString,
            'message': 'Order was created but wallet payment failed. Please contact support.',
            'error': paymentResult['error'],
          };
        } else {
          throw Exception(paymentResult['error'] ?? 'Wallet payment failed');
        }
      }
    } catch (e) {
      print('❌ Wallet payment error: $e');
      final friendlyError = _getFriendlyErrorMessage(e);
      return {
        'success': false,
        'message': friendlyError,
        'error_details': e.toString(),
      };
    }
  }

  // ============================================================
  // ✅ CREATE ORDER AFTER PAYMENT (WooCommerce) - FIXED STATUS
  // ============================================================
  Future<Map<String, dynamic>?> _createOrderAfterPayment({
    required String paymentMethod,
    required List<dynamic> cartItems,
    required double totalAmount,
    required BuildContext context,
    String? paymentReference,
    Map<String, dynamic>? customerData,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddress,
  }) async {
    try {
      final int customerId = _getCustomerId(context, customerData);
      print('📦 Creating order for customer: $customerId with payment method: $paymentMethod');

      final List<Map<String, dynamic>> lineItems = _buildLineItems(cartItems);
      final Map<String, String> billing =
          _buildBillingAddress(context, billingAddress, customerData);
      final Map<String, String> shipping =
          _buildShippingAddress(context, shippingAddress, billingAddress, customerData);
      final Map<String, dynamic> metadata =
          _buildMetadata(paymentMethod, paymentReference);

      String orderStatus;
      String paymentMethodTitle;

      switch (paymentMethod) {
        case 'wallet':
          paymentMethodTitle = 'TeraWallet';
          orderStatus = 'processing';
          metadata['wallet_payment'] = 'true';
          metadata['transaction_id'] = paymentReference ?? '';
          break;

        case 'bacs':
        case 'bank_transfer':
          paymentMethodTitle = 'Bank Transfer';
          // ✅ FIX: Use 'on-hold' status that WooCommerce expects for bank transfers
          orderStatus = 'on-hold';
          metadata['awaiting_bank_transfer'] = 'true';
          metadata['bank_transfer_instructions'] = 'Please transfer the total amount to our bank account. Order will be processed once payment is confirmed.';
          break;

        case 'paystack':
        case 'card':
          paymentMethodTitle = 'Paystack';
          orderStatus = 'processing';
          metadata['paystack_reference'] = paymentReference ?? '';
          metadata['card_payment'] = 'true';
          break;

        default:
          paymentMethodTitle = 'Online Payment';
          orderStatus = 'pending';
      }

      final orderData = await wooCommerceService.createOrder(
        customerId: customerId,
        lineItems: lineItems,
        billing: billing,
        shipping: shipping,
        paymentMethod: paymentMethod,
        paymentMethodTitle: paymentMethodTitle,
        status: orderStatus,
        metadata: metadata,
      );

      if (orderData != null && orderData['error'] != true) {
        print('✅ Order created successfully: ${orderData['id']}');

        final orderSummary = _generateOrderSummary(
          cartItems: cartItems,
          totalAmount: totalAmount,
          paymentMethod: paymentMethod,
        );

        // FIXED: Ensure orderId is properly handled
        final dynamic orderId = orderData['id'];
        final String orderIdString = orderId?.toString() ?? '';
        final int? orderIdInt = _safeParseInt(orderId);

        // ✅ ENHANCED: Add explicit order creation confirmation
        final result = {
          'success': true,
          'orderData': orderData,
          'paymentReference': paymentReference ?? 'no_reference',
          'orderId': orderIdInt,
          'orderIdString': orderIdString,
          'message': 'Order created successfully',
          'order_summary': orderSummary,
          'next_steps': _getNextSteps(paymentMethod, orderStatus),
          'order_created': true, // Explicit confirmation flag
          'payment_status': _getPaymentStatus(paymentMethod, orderStatus),
        };

        // ✅ For bank transfer, add specific instructions
        if (paymentMethod == 'bacs' || paymentMethod == 'bank_transfer') {
          result['bank_transfer_details'] = {
            'status': 'awaiting_payment',
            'instructions': 'Please complete your bank transfer to process the order',
            'order_created_at': DateTime.now().toIso8601String(),
          };
        }

        return result;
      } else {
        throw Exception('Failed to create order: ${orderData?['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('❌ Order creation error: $e');
      final friendlyError = _getFriendlyErrorMessage(e);
      return {
        'success': false,
        'message': friendlyError,
        'error_details': e.toString(),
        'orderData': null,
        'order_created': false, // Explicit failure flag
      };
    }
  }

  // ============================================================
  // ✅ ORDER CONFIRMATION EMAIL TRIGGER
  // ============================================================
  Future<bool> _triggerOrderConfirmation(int orderId) async {
    try {
      print('📧 Triggering confirmation email for order: $orderId');

      // Method 1: Using WooCommerce REST API to add order note (triggers email)
      final emailResult = await wooCommerceService.sendRequest(
        'wc/v3/orders/$orderId/notes',
        method: 'POST',
        data: {
          'note': 'Order confirmed and details sent to customer. Thank you for your purchase!',
          'customer_note': true,
          'added_by_user': false,
        }
      );

      if (emailResult != null) {
        print('✅ Order confirmation triggered for order: $orderId');
        return true;
      }

      // Method 2: Alternative endpoint for email triggering
      final alternativeResult = await wooCommerceService.sendRequest(
        'tellme/v1/send-order-email',
        method: 'POST',
        data: {
          'order_id': orderId,
          'email_type': 'customer_processing_order',
        }
      );

      if (alternativeResult != null && alternativeResult['success'] == true) {
        print('✅ Order confirmation email sent via alternative endpoint');
        return true;
      }

      print('⚠️ Could not trigger email confirmation, but order was created successfully');
      return false;
    } catch (e) {
      print('❌ Failed to trigger confirmation email: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ PAYSTACK TRANSACTION VERIFICATION
  // ============================================================
  Future<bool> verifyPaystackTransaction(String reference) async {
    final secretKey = WooCommerceAuthService.paystackSecretKey;
    final url = Uri.parse('https://api.paystack.co/transaction/verify/$reference');

    print('🔍 Verifying Paystack transaction: $reference');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $secretKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['data'] != null && body['data']['status'] == 'success') {
          print('✅ Paystack verification confirmed');
          return true;
        } else {
          print('⚠️ Paystack verification failed: ${body['data']?['gateway_response']}');
          return false;
        }
      } else {
        print('❌ Paystack verification API error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Exception verifying Paystack transaction: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ ORDER VERIFICATION METHOD
  // ============================================================
  Future<bool> verifyOrderCreation(int orderId) async {
    try {
      final orderData = await wooCommerceService.sendRequest(
        'wc/v3/orders/$orderId',
        method: 'GET',
      );

      return orderData != null && orderData['id'] != null;
    } catch (e) {
      print('❌ Order verification failed: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ ENHANCED UTILITIES - FIXED VERSION
  // ============================================================

  // Order Summary Generation - FIXED
  Map<String, dynamic> _generateOrderSummary({
    required List<dynamic> cartItems,
    required double totalAmount,
    required String paymentMethod,
  }) {
    final items = cartItems.map((item) {
      // FIXED: Use non-nullable values for calculations
      final price = _safeParseDouble(item['price']);
      final quantity = _safeParseInt(item['quantity']) ?? 1; // Provide default
      final itemTotal = price * quantity;

      return '${quantity} x ${item['name']} - ₦${itemTotal.toStringAsFixed(2)}';
    }).toList();

    return {
      'items': items,
      'total_amount': totalAmount,
      'payment_method': paymentMethod,
      'order_date': DateTime.now().toIso8601String(),
      'item_count': cartItems.length,
      'formatted_total': '₦${totalAmount.toStringAsFixed(2)}',
    };
  }

  // Customer-friendly Error Messages
  String _getFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout') || errorString.contains('connection')) {
      return 'Payment processing timed out. Please check your internet connection and try again.';
    } else if (errorString.contains('insufficient') || errorString.contains('balance')) {
      return 'Insufficient wallet balance. Please choose another payment method or top up your wallet.';
    } else if (errorString.contains('network') || errorString.contains('unreachable')) {
      return 'Network error. Please check your connection and try again.';
    } else if (errorString.contains('card') || errorString.contains('declined')) {
      return 'Card payment declined. Please check your card details or try another payment method.';
    } else if (errorString.contains('order') || errorString.contains('create')) {
      return 'We encountered an issue creating your order. Please try again or contact support.';
    } else if (errorString.contains('type') && errorString.contains('string') && errorString.contains('int')) {
      return 'There was a technical issue with the payment. The order was created successfully. Please check your orders.';
    } else {
      return 'We encountered an issue processing your payment. Please try again or contact our support team.';
    }
  }

  // Next Steps Information - ENHANCED WITH STATUS FIX
  Map<String, String> _getNextSteps(String paymentMethod, String orderStatus) {
    // ✅ FIX: Handle 'on-hold' status for bank transfers
    final bool isBankTransferPending =
        (paymentMethod == 'bank_transfer' || paymentMethod == 'bacs') &&
        (orderStatus == 'pending-payment' || orderStatus == 'on-hold');

    if (isBankTransferPending) {
      return {
        'message': 'Order created successfully! Awaiting bank transfer.',
        'action': 'Check your email for bank account details',
        'timeline': 'Order will be processed within 24 hours of payment confirmation',
        'status': 'order_created',
        'payment_required': 'true',
      };
    }

    switch (paymentMethod) {
      case 'wallet':
        return {
          'message': 'Payment completed from your wallet balance',
          'action': 'Order is being processed',
          'timeline': 'You will receive shipping updates soon',
          'status': 'payment_complete',
        };
      case 'paystack':
      case 'card':
        return {
          'message': 'Card payment processed successfully',
          'action': 'Order is being processed',
          'timeline': 'You will receive shipping confirmation shortly',
          'status': 'payment_complete',
        };
      default:
        return {
          'message': 'Order received successfully',
          'action': 'Check your email for confirmation',
          'timeline': 'Processing will begin shortly',
          'status': 'order_created',
        };
    }
  }

  // Payment Status Helper - FIXED
  String _getPaymentStatus(String paymentMethod, String orderStatus) {
    // ✅ FIX: Handle 'on-hold' status for bank transfers
    if (paymentMethod == 'bank_transfer' || paymentMethod == 'bacs') {
      if (orderStatus == 'on-hold' || orderStatus == 'pending-payment') {
        return 'awaiting_payment';
      }
    } else if (orderStatus == 'processing' || orderStatus == 'completed') {
      return 'payment_complete';
    }
    return 'pending';
  }

  int _getCustomerId(BuildContext context, Map<String, dynamic>? customerData) {
    if (customerData != null && customerData['id'] != null) {
      return int.tryParse(customerData['id'].toString()) ?? 1;
    }
    return 1;
  }

  Map<String, String> _buildBillingAddress(
    BuildContext context,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? customerData,
  ) {
    if (billingAddress != null) {
      return {
        'first_name': billingAddress['firstName']?.toString() ?? '',
        'last_name': billingAddress['lastName']?.toString() ?? '',
        'company': billingAddress['company']?.toString() ?? '',
        'address_1': billingAddress['address1']?.toString() ?? '',
        'address_2': billingAddress['address2']?.toString() ?? '',
        'city': billingAddress['city']?.toString() ?? '',
        'state': billingAddress['state']?.toString() ?? '',
        'postcode': billingAddress['postcode']?.toString() ?? '',
        'country': billingAddress['country']?.toString() ?? 'NG',
        'email': customerData?['email']?.toString() ??
            billingAddress['email']?.toString() ??
            '',
        'phone': billingAddress['phone']?.toString() ?? '',
      };
    }
    return {
      'first_name': '',
      'last_name': '',
      'company': '',
      'address_1': '',
      'address_2': '',
      'city': '',
      'state': '',
      'postcode': '',
      'country': 'NG',
      'email': '',
      'phone': '',
    };
  }

  Map<String, String> _buildShippingAddress(
    BuildContext context,
    Map<String, dynamic>? shippingAddress,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? customerData,
  ) {
    final addressData = shippingAddress ?? billingAddress;
    if (addressData != null) {
      return {
        'first_name': addressData['firstName']?.toString() ?? '',
        'last_name': addressData['lastName']?.toString() ?? '',
        'company': addressData['company']?.toString() ?? '',
        'address_1': addressData['address1']?.toString() ?? '',
        'address_2': addressData['address2']?.toString() ?? '',
        'city': addressData['city']?.toString() ?? '',
        'state': addressData['state']?.toString() ?? '',
        'postcode': addressData['postcode']?.toString() ?? '',
        'country': addressData['country']?.toString() ?? 'NG',
      };
    }
    return {
      'first_name': '',
      'last_name': '',
      'company': '',
      'address_1': '',
      'address_2': '',
      'city': '',
      'state': '',
      'postcode': '',
      'country': 'NG',
    };
  }

  // FIXED: Line items with string values for WooCommerce API
  List<Map<String, dynamic>> _buildLineItems(List<dynamic> cartItems) {
    return cartItems.map((item) {
      // FIXED: Use non-nullable values for calculations
      final price = _safeParseDouble(item['price']);
      final quantity = _safeParseInt(item['quantity']) ?? 1; // Provide default
      final subtotal = price * quantity;

      return {
        'product_id': _safeParseInt(item['id']) ?? 0, // Provide default
        'quantity': quantity,
        'name': item['name']?.toString() ?? 'Unknown Product',
        'price': price.toString(),
        'subtotal': subtotal.toString(),
        'total': subtotal.toString(),
      };
    }).toList();
  }

  Map<String, dynamic> _buildMetadata(String paymentMethod, String? paymentReference) {
    return {
      'payment_method': paymentMethod,
      'payment_reference': paymentReference ?? '',
      'app_source': 'flutter_app',
      'created_via': 'mobile_app',
      'order_timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      'app_version': '1.0.0',
      'platform': 'flutter',
    };
  }

  // ============================================================
  // ✅ SAFE PARSING UTILITIES
  // ============================================================

  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    return double.tryParse(value.toString()) ?? 0.0;
  }

  int? _safeParseInt(dynamic value) {
    if (value == null) return null;

    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }

    return int.tryParse(value.toString());
  }
}