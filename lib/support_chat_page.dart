import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'tellme_live_chat_service.dart';
import 'user_provider.dart';

class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _chat = TellMeLiveChatService.instance;
  final List<TellMeChatMessage> _messages = [];
  Timer? _pollTimer;
  bool _loading = true;
  bool _sending = false;
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
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final user = context.read<UserProvider>();
    try {
      await _chat.startPresence(
        currentPage: 'App: Live Chat',
        name: user.userDisplayName,
        email: user.userEmail,
      );
    } catch (_) {
      // Message loading below will show a retry state if the API is unavailable.
    }
    await _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadMessages(silent: true);
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
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

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    final user = context.read<UserProvider>();

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _chat.sendMessage(
        message: text,
        name: user.userDisplayName,
        email: user.userEmail,
      );
      _ctrl.clear();
      await _loadMessages(silent: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Message was not sent. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('TellMe Live Chat'),
        backgroundColor: const Color(0xFF004AAD),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFFEAF4FF),
            child: const Text(
              'Chat directly with TellMe support. We will reply here while you are in the app.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (_error != null)
            Material(
              color: const Color(0xFFFFF1F2),
              child: ListTile(
                dense: true,
                leading:
                    const Icon(Icons.info_outline, color: Color(0xFFBE123C)),
                title: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFBE123C)),
                ),
                trailing: TextButton(
                  onPressed: () => _loadMessages(),
                  child: const Text('Retry'),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMessages,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Icon(
                              Icons.support_agent_rounded,
                              size: 54,
                              color: Color(0xFF004AAD),
                            ),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'Say hello. We usually reply quickly.',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final item = _messages[i];
                            final mine = !item.fromAdmin;
                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 12),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.78,
                                ),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? const Color(0xFF1565C0)
                                      : const Color(0xFFEAF4FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  item.message,
                                  style: TextStyle(
                                    color: mine ? Colors.white : Colors.black87,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
