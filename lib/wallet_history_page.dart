// lib/wallet_history_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'wallet_service.dart';
import 'user_provider.dart';

const _kGreen = Color(0xFF10B981);
const _kRed   = Color(0xFFEF4444);
const _kBlue  = Color(0xFF2563EB);
const _kGrey  = Color(0xFF64748B);

class WalletHistoryPage extends StatefulWidget {
  const WalletHistoryPage({super.key});
  @override
  State<WalletHistoryPage> createState() => _WalletHistoryPageState();
}

class _WalletHistoryPageState extends State<WalletHistoryPage> {
  final _wallet = WalletService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    try {
      int? userId;
      try {
        final u = context.read<UserProvider>().currentUser;
        if (u != null) userId = int.tryParse('${u['id']}');
      } catch (_) {}
      userId ??= 1; // TODO: remove fallback when provider always supplies id

      final res = await _wallet.getWalletTransactions(userId, limit: 50);
      if (res['success'] == true) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(res['transactions'] ?? const []);
          _loading = false;
        });
      } else {
        setState(() { _loading = false; _error = '${res['error'] ?? 'Failed to load'}'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ---- formatting helpers ----
  String _fmtAmount(dynamic v) {
    String symbol = '₦';
    num raw = 0;
    if (v is Map) {
      if (v['currency_symbol'] != null) {
        final s = '${v['currency_symbol']}';
        symbol = s.contains('&#8358;') ? '₦' : (s.isNotEmpty ? s : '₦');
      }
      if (v['raw'] is num) raw = v['raw'];
      if (raw == 0 && v['amount'] is num) raw = v['amount'];
      if (raw == 0 && v['value'] is num) raw = v['value'];
    } else if (v is num) {
      raw = v;
    } else if (v is String) {
      raw = num.tryParse(v.replaceAll(',', '')) ?? 0;
    }
    final f = NumberFormat('#,##0.00', 'en_US');
    return '$symbol${f.format(raw)}';
  }

  bool _isCredit(Map<String, dynamic> r) {
    final t = (r['type'] ?? r['txn_type'] ?? '').toString().toLowerCase();
    if (t.contains('credit') || t == 'cr') return true;
    if (t.contains('debit') || t == 'dr') return false;
    final a = r['amount'];
    num raw = 0;
    if (a is Map && a['raw'] is num) raw = a['raw'];
    if (a is num) raw = a;
    if (a is String) raw = num.tryParse(a.replaceAll(',', '')) ?? 0;
    return raw >= 0;
  }

  String _title(Map<String, dynamic> r) {
    final d = (r['description'] ?? r['note'] ?? '').toString();
    return d.isNotEmpty ? d : (_isCredit(r) ? 'Wallet Top-Up' : 'Wallet Debit');
  }

  String _date(Map<String, dynamic> r) {
    final raw = r['created_at'] ?? r['date'] ?? r['timestamp'];
    DateTime? dt;
    if (raw is int) dt = DateTime.fromMillisecondsSinceEpoch(raw > 2000000000 ? raw : raw * 1000);
    if (raw is String) dt ??= DateTime.tryParse(raw);
    dt ??= DateTime.now();
    return DateFormat('EEE, dd MMM yyyy • HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet History'), backgroundColor: _kBlue, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 8,
                itemBuilder: (_, __) => Container(
                  height: 74,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black12.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )
            : (_error != null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: _kRed, size: 48),
                          const SizedBox(height: 8),
                          const Text('Couldn’t load history', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _kGrey)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
                        ],
                      ),
                    ),
                  )
                : (_rows.isEmpty)
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No transactions yet'),
                        ),
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final isCr = _isCredit(r);
                          final amt = _fmtAmount(r['amount'] ?? r['value']);
                          return Card(
                            elevation: 0.8,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: (isCr ? _kGreen : _kRed).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(isCr ? Icons.south_west : Icons.north_east,
                                    color: isCr ? _kGreen : _kRed, size: 22),
                              ),
                              title: Text(_title(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${_date(r)}',
                                  style: const TextStyle(color: _kGrey, fontSize: 12.5)),
                              trailing: Text(
                                (isCr ? '+' : '−') + amt.replaceFirst('₦₦', '₦'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isCr ? _kGreen : _kRed,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
