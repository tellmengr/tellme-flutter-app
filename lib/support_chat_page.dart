import 'dart:async';
import 'dart:io';

import 'package:email_validator/email_validator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tellme_live_chat_service.dart';
import 'user_provider.dart';

class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  static const _guestNameKey = 'tellme_guest_chat_name';
  static const _guestEmailKey = 'tellme_guest_chat_email';
  static const _maxAttachmentBytes = 8 * 1024 * 1024;

  final _messageCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _chat = TellMeLiveChatService.instance;
  final List<TellMeChatMessage> _messages = [];

  Timer? _pollTimer;
  PlatformFile? _selectedFile;
  bool _loading = true;
  bool _sending = false;
  bool _savingIdentity = false;
  bool _needsIdentity = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _hasGuestIdentity {
    return _nameCtrl.text.trim().length >= 2 &&
        EmailValidator.validate(_emailCtrl.text.trim());
  }

  String _activeName(UserProvider user) {
    if (user.isLoggedIn) return user.userDisplayName;
    return _nameCtrl.text.trim();
  }

  String _activeEmail(UserProvider user) {
    if (user.isLoggedIn) return user.userEmail;
    return _emailCtrl.text.trim();
  }

  Future<void> _start() async {
    await _loadGuestIdentity();
    if (!mounted) return;

    final user = context.read<UserProvider>();
    if (!user.isLoggedIn && !_hasGuestIdentity) {
      setState(() {
        _needsIdentity = true;
        _loading = false;
      });
      return;
    }

    await _connectAndLoad();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMessages(silent: true);
    });
  }

  Future<void> _loadGuestIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _nameCtrl.text = prefs.getString(_guestNameKey) ?? '';
    _emailCtrl.text = prefs.getString(_guestEmailKey) ?? '';
  }

  Future<void> _connectAndLoad() async {
    final user = context.read<UserProvider>();
    try {
      await _chat.startPresence(
        currentPage: 'App: Live Chat',
        name: _activeName(user),
        email: _activeEmail(user),
      );
    } catch (_) {
      // Message loading below will show a retry state if the API is unavailable.
    }

    await _loadMessages();
  }

  Future<void> _saveGuestIdentity() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.length < 2) {
      setState(() =>
          _error = 'Please enter your name so support knows who you are.');
      return;
    }

    if (!EmailValidator.validate(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _savingIdentity = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guestNameKey, name);
      await prefs.setString(_guestEmailKey, email);

      if (!mounted) return;
      setState(() {
        _needsIdentity = false;
        _loading = true;
      });

      await _connectAndLoad();
      _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        _loadMessages(silent: true);
      });
    } finally {
      if (mounted) setState(() => _savingIdentity = false);
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_needsIdentity) return;

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final nextMessages = await _chat.messages();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(nextMessages);
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load chat. Pull to retry.';
      });
    }
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );

      final file = result?.files.single;
      if (file == null) return;

      if (file.path == null || file.path!.trim().isEmpty) {
        setState(() => _error = 'This file cannot be attached on this device.');
        return;
      }

      if (file.size > _maxAttachmentBytes) {
        setState(() => _error = 'Please choose a file smaller than 8 MB.');
        return;
      }

      setState(() {
        _selectedFile = file;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Unable to choose file. Please try again.');
    }
  }

  Future<void> _send() async {
    final user = context.read<UserProvider>();
    if (!user.isLoggedIn && !_hasGuestIdentity) {
      setState(() {
        _needsIdentity = true;
        _error = 'Please enter your name and email before starting chat.';
      });
      return;
    }

    final text = _messageCtrl.text.trim();
    final selectedFile = _selectedFile;
    if ((text.isEmpty && selectedFile == null) || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _chat.sendMessage(
        message: text,
        name: _activeName(user),
        email: _activeEmail(user),
        attachment: selectedFile?.path == null
            ? null
            : TellMeChatUpload(
                path: selectedFile!.path!,
                fileName: selectedFile.name,
              ),
      );
      _messageCtrl.clear();
      setState(() => _selectedFile = null);
      await _loadMessages(silent: true);
    } catch (error) {
      if (!mounted) return;
      final detail = error.toString().replaceFirst('Exception: ', '').trim();
      setState(() {
        _error = selectedFile == null
            ? 'Message was not sent. Please try again.'
            : detail.isNotEmpty
                ? detail
                : 'Attachment was not sent. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openAttachment(String url) async {
    final uri = Uri.tryParse(_absoluteChatAttachmentUrl(url));
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final canChat = user.isLoggedIn || !_needsIdentity;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FB),
      appBar: AppBar(
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TellMe Support'),
            SizedBox(height: 2),
            Text(
              'Live chat',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF004AAD),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _ChatIntro(
            name:
                user.isLoggedIn ? user.userDisplayName : _nameCtrl.text.trim(),
            email: user.isLoggedIn ? user.userEmail : _emailCtrl.text.trim(),
            isGuest: !user.isLoggedIn,
          ),
          if (!user.isLoggedIn && _needsIdentity)
            _GuestIdentityCard(
              nameController: _nameCtrl,
              emailController: _emailCtrl,
              saving: _savingIdentity,
              onContinue: _saveGuestIdentity,
            ),
          if (_error != null)
            _ErrorBanner(message: _error!, onRetry: _loadMessages),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMessages,
              child: !canChat
                  ? ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 44),
                      children: const [
                        Icon(Icons.lock_person_rounded,
                            size: 54, color: Color(0xFF004AAD)),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Tell us who you are to begin.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    )
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 72,
                              ),
                              children: const [
                                Icon(
                                  Icons.support_agent_rounded,
                                  size: 54,
                                  color: Color(0xFF004AAD),
                                ),
                                SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    'Say hello. We usually reply quickly.',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              controller: _scrollCtrl,
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 12, 20),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                return _ChatBubble(
                                  message: _messages[index],
                                  onOpenAttachment: _openAttachment,
                                );
                              },
                            ),
            ),
          ),
          _Composer(
            controller: _messageCtrl,
            selectedFile: _selectedFile,
            enabled: canChat,
            sending: _sending,
            onAttach: _pickAttachment,
            onClearAttachment: () => setState(() => _selectedFile = null),
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ChatIntro extends StatelessWidget {
  const _ChatIntro({
    required this.name,
    required this.email,
    required this.isGuest,
  });

  final String name;
  final String email;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim();
    final cleanEmail = email.trim();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E7F7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded,
                color: Color(0xFF004AAD)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Customer support',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  cleanEmail.isNotEmpty
                      ? '${isGuest ? "Guest" : "Signed in"}: $cleanName - $cleanEmail'
                      : 'We reply here and can continue by email.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFF475569), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _OnlinePill(),
        ],
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE8FFF1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Color(0xFF16A34A)),
          SizedBox(width: 5),
          Text(
            'Online',
            style: TextStyle(
              color: Color(0xFF047857),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestIdentityCard extends StatelessWidget {
  const _GuestIdentityCard({
    required this.nameController,
    required this.emailController,
    required this.saving,
    required this.onContinue,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final bool saving;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E7F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Before we start',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter your name and email so support can identify you and follow up.',
            style: TextStyle(color: Color(0xFF475569)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : onContinue,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(saving ? 'Saving...' : 'Continue to chat'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF1F2),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.info_outline, color: Color(0xFFBE123C)),
        title: Text(message, style: const TextStyle(color: Color(0xFFBE123C))),
        trailing: TextButton(
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ),
    );
  }
}

String _absoluteChatAttachmentUrl(String url) {
  final clean = url.trim();
  if (clean.isEmpty) return '';
  if (clean.startsWith('//')) return 'https:$clean';

  final uri = Uri.tryParse(clean);
  if (uri != null && uri.hasScheme) return clean;

  if (clean.startsWith('/')) return 'https://tellme.ng$clean';
  return 'https://tellme.ng/$clean';
}

String _attachmentSourceKey(String url, String name) {
  return (name.isNotEmpty ? name : url)
      .split('?')
      .first
      .split('#')
      .first
      .toLowerCase();
}

bool _hasImageExtension(String source) {
  return source.endsWith('.jpg') ||
      source.endsWith('.jpeg') ||
      source.endsWith('.png') ||
      source.endsWith('.webp') ||
      source.endsWith('.gif') ||
      source.endsWith('.bmp') ||
      source.endsWith('.heic') ||
      source.endsWith('.heif');
}

bool _hasKnownNonImageExtension(String source) {
  return source.endsWith('.pdf') ||
      source.endsWith('.doc') ||
      source.endsWith('.docx') ||
      source.endsWith('.xls') ||
      source.endsWith('.xlsx') ||
      source.endsWith('.zip') ||
      source.endsWith('.rar') ||
      source.endsWith('.txt') ||
      source.endsWith('.csv');
}

bool _shouldTryImagePreview({
  required String url,
  required String name,
  required String type,
}) {
  final cleanType = type.toLowerCase();
  if (cleanType.startsWith('image/')) return true;

  final source = _attachmentSourceKey(url, name);
  if (_hasImageExtension(source)) return true;
  if (_hasKnownNonImageExtension(source)) return false;

  return true;
}

bool _isLocalImageFile(PlatformFile file) {
  return _hasImageExtension(_attachmentSourceKey('', file.name));
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.onOpenAttachment,
  });

  final TellMeChatMessage message;
  final Future<void> Function(String url) onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final mine = !message.fromAdmin;
    final hasText = message.message.trim().isNotEmpty;
    final attachmentUrl = message.attachmentUrl?.trim() ?? '';
    final absoluteAttachmentUrl = _absoluteChatAttachmentUrl(attachmentUrl);
    final attachmentName = message.attachmentName?.trim() ??
        (attachmentUrl.isNotEmpty ? 'Open attachment' : '');
    final attachmentType = message.attachmentType?.trim() ?? '';
    final showImagePreview = attachmentUrl.isNotEmpty &&
        _shouldTryImagePreview(
          url: attachmentUrl,
          name: attachmentName,
          type: attachmentType,
        );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: const Color(0xFFD8E7F7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasText)
              Text(
                message.message,
                style: TextStyle(
                  color: mine ? Colors.white : const Color(0xFF0F172A),
                  height: 1.35,
                ),
              ),
            if (attachmentUrl.isNotEmpty) ...[
              if (hasText) const SizedBox(height: 8),
              if (showImagePreview)
                InkWell(
                  onTap: () => onOpenAttachment(absoluteAttachmentUrl),
                  borderRadius: BorderRadius.circular(14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 260,
                        maxHeight: 230,
                      ),
                      color: mine
                          ? Colors.white.withOpacity(0.14)
                          : const Color(0xFFEAF4FF),
                      child: Image.network(
                        absoluteAttachmentUrl,
                        width: 260,
                        height: 190,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;

                          return const SizedBox(
                            width: 220,
                            height: 150,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return _AttachmentButton(
                            mine: mine,
                            label: attachmentName,
                            onTap: () =>
                                onOpenAttachment(absoluteAttachmentUrl),
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                _AttachmentButton(
                  mine: mine,
                  label: attachmentName,
                  onTap: () => onOpenAttachment(absoluteAttachmentUrl),
                ),
              if (showImagePreview && attachmentName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  attachmentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mine ? Colors.white70 : const Color(0xFF475569),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({
    required this.mine,
    required this.label,
    required this.onTap,
  });

  final bool mine;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              mine ? Colors.white.withOpacity(0.14) : const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file_rounded,
              size: 18,
              color: mine ? Colors.white : const Color(0xFF004AAD),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label.isEmpty ? 'Open attachment' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mine ? Colors.white : const Color(0xFF004AAD),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.selectedFile,
    required this.enabled,
    required this.sending,
    required this.onAttach,
    required this.onClearAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final PlatformFile? selectedFile;
  final bool enabled;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onClearAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final selected = selectedFile;
    final selectedIsImage = selected != null && _isLocalImageFile(selected);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFD8E7F7))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    if (selectedIsImage && selected.path != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(selected.path!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.insert_drive_file_rounded,
                              color: Color(0xFF004AAD),
                            );
                          },
                        ),
                      )
                    else
                      const Icon(
                        Icons.insert_drive_file_rounded,
                        color: Color(0xFF004AAD),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selected.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onClearAttachment,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach file',
                  onPressed: enabled && !sending ? onAttach : null,
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !sending,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: enabled
                          ? 'Type a message...'
                          : 'Enter your details first',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: enabled && !sending ? onSend : null,
                  icon: sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
