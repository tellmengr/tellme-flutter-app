// lib/whatsapp_helper.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// ✅ Your WhatsApp support number in E.164 *without* the leading '+'
const kSupportWhatsApp = '2347054139575';

Future<void> openWhatsAppChat({
  String? phoneE164, // optional; falls back to kSupportWhatsApp
  String? prefill,
  BuildContext? context,
  bool preferWeb = false, // set true on emulator so it opens browser
}) async {
  final phone = (phoneE164 ?? kSupportWhatsApp).trim();
  final text  = Uri.encodeComponent(prefill ?? "Hi, I need help with my order.");
  final deep  = Uri.parse("whatsapp://send?phone=$phone&text=$text");
  final web   = Uri.parse("https://wa.me/$phone?text=$text");

  try {
    if (preferWeb && await canLaunchUrl(web)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(deep)) {
      await launchUrl(deep, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(web)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
      return;
    }
  } catch (_) {}

  if (context != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open WhatsApp on this device.")),
    );
  }
}
