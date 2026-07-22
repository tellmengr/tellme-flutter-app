import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TellMeChatMessage {
  final String id;
  final String sender;
  final String message;
  final DateTime? createdAt;

  const TellMeChatMessage({
    required this.id,
    required this.sender,
    required this.message,
    required this.createdAt,
  });

  bool get fromAdmin => sender == 'admin';

  factory TellMeChatMessage.fromJson(Map<String, dynamic> json) {
    final createdRaw =
        (json['createdAt'] ?? json['created_at'] ?? '').toString();

    return TellMeChatMessage(
      id: (json['id'] ?? '').toString(),
      sender: (json['sender'] ?? 'visitor').toString(),
      message: (json['message'] ?? '').toString(),
      createdAt: createdRaw.isEmpty
          ? null
          : DateTime.tryParse(createdRaw.replaceFirst(' ', 'T')),
    );
  }
}

class TellMeLiveChatService {
  TellMeLiveChatService._();

  static final TellMeLiveChatService instance = TellMeLiveChatService._();

  static const String _baseUrl = 'https://tellme.ng';
  static const String _sessionKey = 'tellme_mobile_chat_session_code';
  static const String _appVersion = '1.0.7';

  Timer? _presenceTimer;
  String? _lastScreen;

  String get platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return Platform.operatingSystem;
  }

  Future<String> sessionCode() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_sessionKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final code = 'TMAPP-${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_sessionKey, code);
    return code;
  }

  Future<void> startPresence({
    required String currentPage,
    String? name,
    String? email,
  }) async {
    _lastScreen = currentPage;
    await updateSession(currentPage: currentPage, name: name, email: email);

    _presenceTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final screen = _lastScreen;
      if (screen == null) return;
      unawaited(updateSession(currentPage: screen, name: name, email: email));
    });
  }

  Future<void> updateSession({
    required String currentPage,
    String? name,
    String? email,
  }) async {
    _lastScreen = currentPage;

    final code = await sessionCode();
    final payload = <String, dynamic>{
      'sessionCode': code,
      'name': (name ?? '').trim(),
      'email': (email ?? '').trim(),
      'clientSource': 'mobile_app',
      'platform': platform,
      'appVersion': _appVersion,
      'deviceId': code,
      'currentPage': currentPage,
    };

    await http
        .post(
          Uri.parse('$_baseUrl/api/chat/session'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));
  }

  Future<List<TellMeChatMessage>> messages() async {
    final code = await sessionCode();
    final response = await http.get(
      Uri.parse(
          '$_baseUrl/api/chat/messages?sessionCode=${Uri.encodeComponent(code)}'),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Unable to load chat messages.');
    }

    final decoded = jsonDecode(response.body);
    final rawMessages = decoded is Map<String, dynamic>
        ? (decoded['messages'] ?? decoded['data'] ?? const [])
        : const [];

    if (rawMessages is! List) return const [];

    return rawMessages
        .whereType<Map>()
        .map((item) => TellMeChatMessage.fromJson(item.cast<String, dynamic>()))
        .where((item) => item.message.trim().isNotEmpty)
        .toList();
  }

  Future<void> sendMessage({
    required String message,
    String? name,
    String? email,
  }) async {
    final text = message.trim();
    if (text.isEmpty) return;

    final code = await sessionCode();
    await updateSession(
      currentPage: _lastScreen ?? 'App: Live Chat',
      name: name,
      email: email,
    );

    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/chat/messages'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'sessionCode': code,
            'sender': 'visitor',
            'name': (name ?? '').trim(),
            'email': (email ?? '').trim(),
            'senderName': (name ?? '').trim(),
            'senderEmail': (email ?? '').trim(),
            'message': text,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Unable to send message.');
    }
  }

  void stopPresence() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }
}
