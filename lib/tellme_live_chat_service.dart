import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TellMeChatMessage {
  final String id;
  final String sender;
  final String message;
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentType;
  final DateTime? createdAt;

  const TellMeChatMessage({
    required this.id,
    required this.sender,
    required this.message,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentType,
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
      attachmentUrl: _firstText(json, const [
        'attachmentUrl',
        'attachment_url',
        'fileUrl',
        'file_url',
        'mediaUrl',
        'media_url',
      ]),
      attachmentName: _firstText(json, const [
        'attachmentName',
        'attachment_name',
        'fileName',
        'file_name',
        'mediaName',
        'media_name',
        'originalName',
        'original_name',
      ]),
      attachmentType: _firstText(json, const [
        'attachmentType',
        'attachment_type',
        'mimeType',
        'mime_type',
        'contentType',
        'content_type',
        'mediaType',
        'media_type',
      ]),
      createdAt: createdRaw.isEmpty
          ? null
          : DateTime.tryParse(createdRaw.replaceFirst(' ', 'T')),
    );
  }

  static String? _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final attachments = json['attachments'];
    if (attachments is List && attachments.isNotEmpty) {
      final first = attachments.first;
      if (first is Map) {
        for (final key in keys) {
          final value = first[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    }

    return null;
  }
}

class TellMeChatUpload {
  const TellMeChatUpload({
    required this.path,
    required this.fileName,
  });

  final String path;
  final String fileName;
}

String _guessAttachmentType(String fileName) {
  final clean = fileName.split('?').first.split('#').first.toLowerCase();
  if (clean.endsWith('.jpg') || clean.endsWith('.jpeg')) return 'image/jpeg';
  if (clean.endsWith('.png')) return 'image/png';
  if (clean.endsWith('.webp')) return 'image/webp';
  if (clean.endsWith('.gif')) return 'image/gif';
  if (clean.endsWith('.bmp')) return 'image/bmp';
  if (clean.endsWith('.heic')) return 'image/heic';
  if (clean.endsWith('.heif')) return 'image/heif';
  if (clean.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}

class TellMeLiveChatService {
  TellMeLiveChatService._();

  static final TellMeLiveChatService instance = TellMeLiveChatService._();

  static const String _baseUrl = 'https://tellme.ng';
  static const String _sessionKey = 'tellme_mobile_chat_session_code';
  static const String _appVersion = '1.0.7';

  Timer? _presenceTimer;
  String? _lastScreen;
  String? _lastPageUrl;
  String? _lastProductSku;
  String? _lastProductId;
  String? _lastName;
  String? _lastEmail;
  String? _cachedPushToken;

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
    String? currentPageUrl,
    String? currentProductSku,
    String? currentProductId,
  }) async {
    _lastScreen = currentPage;
    await updateSession(
      currentPage: currentPage,
      name: name,
      email: email,
      currentPageUrl: currentPageUrl,
      currentProductSku: currentProductSku,
      currentProductId: currentProductId,
    );

    _presenceTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      final screen = _lastScreen;
      if (screen == null) return;
      unawaited(
        updateSession(
          currentPage: screen,
          name: _lastName,
          email: _lastEmail,
          currentPageUrl: _lastPageUrl,
          currentProductSku: _lastProductSku,
          currentProductId: _lastProductId,
        ),
      );
    });
  }

  Future<void> updateSession({
    required String currentPage,
    String? name,
    String? email,
    String? currentPageUrl,
    String? currentProductSku,
    String? currentProductId,
  }) async {
    _lastScreen = currentPage;
    _lastName = name;
    _lastEmail = email;
    _lastPageUrl = currentPageUrl;
    _lastProductSku = currentProductSku;
    _lastProductId = currentProductId;

    final code = await sessionCode();
    final pushToken = await _currentPushToken();
    final pageUrl = (currentPageUrl ?? '').trim();
    final productSku = (currentProductSku ?? '').trim();
    final productId = (currentProductId ?? '').trim();
    final payload = <String, dynamic>{
      'sessionCode': code,
      'name': (name ?? '').trim(),
      'email': (email ?? '').trim(),
      'clientSource': 'mobile_app',
      'platform': platform,
      'appVersion': _appVersion,
      'deviceId': code,
      'currentPage': currentPage,
      if (pageUrl.isNotEmpty) 'currentPageUrl': pageUrl,
      if (productSku.isNotEmpty) 'currentProductSku': productSku,
      if (productId.isNotEmpty) 'currentProductId': productId,
      if (pushToken.isNotEmpty) 'pushToken': pushToken,
    };

    await http
        .post(
          Uri.parse('$_baseUrl/api/chat/session'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));
  }

  Future<String> _currentPushToken() async {
    final cached = _cachedPushToken?.trim() ?? '';
    if (cached.isNotEmpty) return cached;

    try {
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 5));
      final clean = token?.trim() ?? '';
      if (clean.isNotEmpty) _cachedPushToken = clean;
      return clean;
    } catch (_) {
      return '';
    }
  }

  Future<void> updatePushToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty) return;

    _cachedPushToken = clean;
    await updateSession(
      currentPage: _lastScreen ?? 'App: Background',
      name: _lastName,
      email: _lastEmail,
      currentPageUrl: _lastPageUrl,
      currentProductSku: _lastProductSku,
      currentProductId: _lastProductId,
    );
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
        .where((item) =>
            item.message.trim().isNotEmpty ||
            (item.attachmentUrl?.trim().isNotEmpty ?? false) ||
            (item.attachmentName?.trim().isNotEmpty ?? false))
        .toList();
  }

  Future<void> sendMessage({
    required String message,
    String? name,
    String? email,
    TellMeChatUpload? attachment,
  }) async {
    final text = message.trim();
    if (text.isEmpty && attachment == null) return;

    final code = await sessionCode();
    await updateSession(
      currentPage: _lastScreen ?? 'App: Live Chat',
      name: name,
      email: email,
    );

    if (attachment != null) {
      final attachmentType = _guessAttachmentType(attachment.fileName);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/chat/messages'),
      )
        ..headers['Accept'] = 'application/json'
        ..fields['sessionCode'] = code
        ..fields['sender'] = 'visitor'
        ..fields['name'] = (name ?? '').trim()
        ..fields['email'] = (email ?? '').trim()
        ..fields['senderName'] = (name ?? '').trim()
        ..fields['senderEmail'] = (email ?? '').trim()
        ..fields['message'] = text.isEmpty ? 'Shared an attachment.' : text
        ..fields['attachmentName'] = attachment.fileName
        ..fields['fileName'] = attachment.fileName
        ..fields['originalName'] = attachment.fileName
        ..fields['attachmentType'] = attachmentType
        ..fields['mimeType'] = attachmentType
        ..files.add(
          await http.MultipartFile.fromPath(
            'attachment',
            attachment.path,
            filename: attachment.fileName,
          ),
        );

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Unable to send attachment (${response.statusCode}): ${response.body}',
        );
      }

      return;
    }

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
