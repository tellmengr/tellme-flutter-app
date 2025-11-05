import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportChatPage extends StatefulWidget {
  /// Set this to your admin's Firebase UID
  final String adminUid;
  const SupportChatPage({super.key, required this.adminUid});

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _ctrl = TextEditingController();
  bool _sending = false;

  String get _userUid => _auth.currentUser!.uid;

  String get _chatId {
    final a = widget.adminUid.compareTo(_userUid) < 0 ? widget.adminUid : _userUid;
    final b = widget.adminUid.compareTo(_userUid) < 0 ? _userUid : widget.adminUid;
    return '${a}_$b';
  }

  CollectionReference<Map<String, dynamic>> get _messagesCol =>
      _db.collection('chats').doc(_chatId).collection('messages');

  DocumentReference<Map<String, dynamic>> get _chatDoc =>
      _db.collection('chats').doc(_chatId);

  Future<void> _ensureChat() async {
    final snap = await _chatDoc.get();
    if (!snap.exists) {
      await _chatDoc.set({
        'members': [_userUid, widget.adminUid],
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await _ensureChat();
    final now = FieldValue.serverTimestamp();

    final batch = _db.batch();
    final msgRef = _messagesCol.doc();
    batch.set(msgRef, {
      'text': text,
      'senderId': _userUid,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'text',
    });
    batch.update(_chatDoc, {
      'lastMessage': text,
      'updatedAt': now,
    });

    await batch.commit();
    _ctrl.clear();
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Support'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesCol
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Say hello — we usually reply quickly.'),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    final mine = m['senderId'] == _userUid;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFF1565C0) : const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          m['text'] ?? '',
                          style: TextStyle(
                            color: mine ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
