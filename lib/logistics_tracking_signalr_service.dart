import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

class LogisticsTrackingSignalRService {
  LogisticsTrackingSignalRService._();

  static final LogisticsTrackingSignalRService instance =
      LogisticsTrackingSignalRService._();

  HubConnection? _connection;
  String? _lastJoinedDeliveryRequestId;
  bool _isConnecting = false;

  final StreamController<Map<String, dynamic>> _riderLocationController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onRiderLocationUpdated =>
      _riderLocationController.stream;

  bool get isConnected => _connection?.state == HubConnectionState.Connected;

  Future<void> connect({
    required String hubBaseUrl,
  }) async {
    if (_connection?.state == HubConnectionState.Connected) {
      debugPrint('[SignalR] Already connected.');
      return;
    }

    if (_isConnecting) {
      debugPrint('[SignalR] Connection already in progress.');
      return;
    }

    _isConnecting = true;

    final cleanBaseUrl = hubBaseUrl.endsWith('/')
        ? hubBaseUrl.substring(0, hubBaseUrl.length - 1)
        : hubBaseUrl;

    final hubUrl = '$cleanBaseUrl/hubs/logistics-tracking';

    debugPrint('[SignalR] Connecting to $hubUrl using WebSockets');

    try {
      await _connection?.stop();
    } catch (e) {
      debugPrint('[SignalR] Previous connection stop ignored: $e');
    }

    _connection = null;

    try {
      final connection = HubConnectionBuilder()
          .withUrl(
            hubUrl,
            options: HttpConnectionOptions(
              // Final Uber/Bolt-style real-time transport.
              // This requires nginx /hubs/ WebSocket upgrade support.
              transport: HttpTransportType.WebSockets,
              skipNegotiation: true,
              requestTimeout: 60000,
            ),
          )
          .withAutomaticReconnect()
          .build();

      _connection = connection;

      _registerConnectionHandlers(connection);
      _registerHubEvents(connection);

      await connection.start()?.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException(
            'SignalR WebSocket connection timed out after 60 seconds.',
          );
        },
      );

      debugPrint('[SignalR] Connected successfully. State=${connection.state}');

      final deliveryId = _lastJoinedDeliveryRequestId;
      if (deliveryId != null && deliveryId.trim().isNotEmpty) {
        await joinDeliveryTrackingGroup(deliveryId);
      }
    } catch (e, stackTrace) {
      debugPrint('[SignalR] Connection failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      try {
        await _connection?.stop();
      } catch (_) {}

      _connection = null;
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  void _registerConnectionHandlers(HubConnection connection) {
    connection.onclose(({error}) {
      debugPrint('[SignalR] Closed. Error: $error');
    });

    connection.onreconnecting(({error}) {
      debugPrint('[SignalR] Reconnecting. Error: $error');
    });

    connection.onreconnected(({connectionId}) async {
      debugPrint('[SignalR] Reconnected. ConnectionId: $connectionId');

      final deliveryId = _lastJoinedDeliveryRequestId;

      if (deliveryId != null && deliveryId.trim().isNotEmpty) {
        try {
          await joinDeliveryTrackingGroup(deliveryId);
        } catch (e, stackTrace) {
          debugPrint('[SignalR] Failed to rejoin delivery group: $e');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    });
  }

  void _registerHubEvents(HubConnection connection) {
    connection.on('RiderLocationUpdated', (arguments) {
      debugPrint('[SignalR] RiderLocationUpdated received: $arguments');

      if (arguments == null || arguments.isEmpty) return;

      final raw = arguments.first;

      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        _riderLocationController.add(data);
        return;
      }

      debugPrint(
        '[SignalR] RiderLocationUpdated ignored. Unsupported payload: $raw',
      );
    });
  }

  Future<void> joinDeliveryTrackingGroup(String deliveryRequestId) async {
    final cleanDeliveryId = deliveryRequestId.trim();

    if (cleanDeliveryId.isEmpty) {
      debugPrint('[SignalR] Cannot join group. Empty delivery ID.');
      return;
    }

    _lastJoinedDeliveryRequestId = cleanDeliveryId;

    final connection = _connection;

    if (connection == null || connection.state != HubConnectionState.Connected) {
      debugPrint(
        '[SignalR] Cannot join group. Not connected. delivery=$cleanDeliveryId',
      );
      return;
    }

    debugPrint('[SignalR] Joining delivery group: $cleanDeliveryId');

    try {
      await connection.invoke(
        'JoinDeliveryTrackingGroup',
        args: <Object>[cleanDeliveryId],
      )?.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'JoinDeliveryTrackingGroup timed out after 30 seconds.',
          );
        },
      );

      debugPrint(
        '[SignalR] Joined delivery group successfully: $cleanDeliveryId',
      );
    } catch (e, stackTrace) {
      debugPrint('[SignalR] Join delivery group failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> leaveDeliveryTrackingGroup(String deliveryRequestId) async {
    final cleanDeliveryId = deliveryRequestId.trim();

    if (cleanDeliveryId.isEmpty) {
      debugPrint('[SignalR] Cannot leave group. Empty delivery ID.');
      return;
    }

    final connection = _connection;

    if (connection == null || connection.state != HubConnectionState.Connected) {
      debugPrint(
        '[SignalR] Cannot leave group. Not connected. delivery=$cleanDeliveryId',
      );
      return;
    }

    debugPrint('[SignalR] Leaving delivery group: $cleanDeliveryId');

    try {
      await connection.invoke(
        'LeaveDeliveryTrackingGroup',
        args: <Object>[cleanDeliveryId],
      )?.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'LeaveDeliveryTrackingGroup timed out after 30 seconds.',
          );
        },
      );

      if (_lastJoinedDeliveryRequestId == cleanDeliveryId) {
        _lastJoinedDeliveryRequestId = null;
      }

      debugPrint(
        '[SignalR] Left delivery group successfully: $cleanDeliveryId',
      );
    } catch (e, stackTrace) {
      debugPrint('[SignalR] Leave delivery group failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> sendRiderLocation({
    required String deliveryRequestId,
    required String riderId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
  }) async {
    final cleanDeliveryId = deliveryRequestId.trim();
    final cleanRiderId = riderId.trim();

    if (cleanDeliveryId.isEmpty || cleanRiderId.isEmpty) {
      debugPrint(
        '[SignalR] Cannot send rider location. Missing delivery or rider ID.',
      );
      return;
    }

    final connection = _connection;

    if (connection == null || connection.state != HubConnectionState.Connected) {
      debugPrint(
        '[SignalR] Cannot send rider location. Not connected. delivery=$cleanDeliveryId rider=$cleanRiderId',
      );
      return;
    }

    debugPrint(
      '[SignalR] Sending rider location delivery=$cleanDeliveryId rider=$cleanRiderId lat=$latitude lng=$longitude',
    );

    try {
      await connection.invoke(
        'SendRiderLocation',
        args: <Object>[
          cleanDeliveryId,
          cleanRiderId,
          latitude,
          longitude,
          accuracy ?? 0.0,
          speed ?? 0.0,
          heading ?? 0.0,
        ],
      )?.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'SendRiderLocation timed out after 30 seconds.',
          );
        },
      );

      debugPrint('[SignalR] Rider location sent successfully.');
    } catch (e, stackTrace) {
      debugPrint('[SignalR] Send rider location failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final connection = _connection;

    try {
      debugPrint('[SignalR] Disconnecting...');

      if (connection != null) {
        await connection.stop();
      }

      debugPrint('[SignalR] Disconnected.');
    } catch (e, stackTrace) {
      debugPrint('[SignalR] Disconnect error: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _connection = null;
      _lastJoinedDeliveryRequestId = null;
      _isConnecting = false;
    }
  }

  void dispose() {
    disconnect();
    _riderLocationController.close();
  }
}
