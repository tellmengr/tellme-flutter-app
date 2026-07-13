// lib/config/api_config.dart
class ApiConfig {
  static const bool useStaging = false;

  static const String productionBaseUrl = 'https://api.tellme.ng';
  static const String stagingBaseUrl = 'https://api.tellme.ng';

  static String get baseUrl => useStaging ? stagingBaseUrl : productionBaseUrl;

  static const String apiVersion = 'v1';

  static String get apiPath => '$baseUrl/api/$apiVersion';

  // Rider endpoints
  static const String riderLookup = '/logistics/rider/lookup';
  static const String riderJobs = '/logistics/rider';

  // Admin endpoints
  static const String adminRiders = '/logistics/admin/riders';
  static const String adminDeliveries = '/logistics/admin/deliveries';

  // Delivery endpoints
  static const String createDelivery = '/logistics/deliveries';
  static const String getDeliveries = '/logistics/deliveries/my';
  static const String getDeliveryById = '/logistics/deliveries';
  static const String getTracking = '/logistics/deliveries';
  static const String calculateEstimate = '/logistics/estimate';

  // Payment endpoints
  static const String initializePayment = '/logistics/payment/initialize';
  static const String verifyPayment = '/logistics/payment/verify';

  static String buildUrl(String endpoint, {Map<String, String>? params}) {
    final uri = Uri.parse('$apiPath$endpoint');

    if (params != null && params.isNotEmpty) {
      return uri.replace(queryParameters: params).toString();
    }

    return uri.toString();
  }

  static String riderLookupUrl(String email) {
    return buildUrl(riderLookup, params: {'email': email});
  }

  static String deliveryByIdUrl(String deliveryId) {
    return buildUrl('$getDeliveryById/${Uri.encodeComponent(deliveryId)}');
  }

  static String trackingUrl(String deliveryId) {
    return buildUrl('$getTracking/${Uri.encodeComponent(deliveryId)}/tracking');
  }

  static String riderJobsUrl(String riderId) {
    return buildUrl('$riderJobs/${Uri.encodeComponent(riderId)}/jobs');
  }

  static String riderStatusUrl(String deliveryRequestId) {
    return buildUrl(
      '$riderJobs/deliveries/${Uri.encodeComponent(deliveryRequestId)}/status',
    );
  }

  static String riderLocationUrl({
    required String deliveryRequestId,
    required String riderId,
  }) {
    return buildUrl(
      '$riderJobs/deliveries/${Uri.encodeComponent(deliveryRequestId)}/location',
      params: {'riderId': riderId},
    );
  }

  static String riderVerifyDeliveryOtpUrl(String deliveryRequestId) {
    return buildUrl(
      '$riderJobs/deliveries/${Uri.encodeComponent(deliveryRequestId)}/verify-delivery-otp',
    );
  }
}
