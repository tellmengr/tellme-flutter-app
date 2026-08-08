// lib/wallet_history_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'user_provider.dart';
import 'wallet_service.dart';

const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kBlue = Color(0xFF2563EB);
const _kGrey = Color(0xFF64748B);

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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _load() async {
    _safeSetState(() {
      _loading = true;
      _error = null;
    });

    try {
      int? userId;
      final user = context.read<UserProvider>().currentUser;
      if (user != null) {
        userId = int.tryParse('${user['id']}');
      }

      final res = await _wallet.getWalletTransactions(userId, limit: 50);
      if (res['success'] == true) {
        _safeSetState(() {
          _rows = List<Map<String, dynamic>>.from(
            res['transactions'] ?? const [],
          );
          _loading = false;
        });
      } else {
        _safeSetState(() {
          _loading = false;
          _error = '${res['error'] ?? 'Failed to load wallet history'}';
        });
      }
    } catch (e) {
      _safeSetState(() {
        _loading = false;
        _error = 'Wallet history could not be loaded. Please try again.';
      });
    }
  }

  String _fmtAmount(dynamic value) {
    num raw = 0;
    if (value is Map) {
      if (value['raw'] is num) raw = value['raw'];
      if (raw == 0 && value['amount'] is num) raw = value['amount'];
      if (raw == 0 && value['value'] is num) raw = value['value'];
    } else if (value is num) {
      raw = value;
    } else if (value is String) {
      raw = num.tryParse(value.replaceAll(',', '')) ?? 0;
    }

    return 'NGN ${NumberFormat('#,##0.00', 'en_US').format(raw.abs())}';
  }

  bool _isCredit(Map<String, dynamic> row) {
    final type =
        (row['type'] ?? row['txn_type'] ?? '').toString().toLowerCase();
    if (type.contains('credit') || type == 'cr') return true;
    if (type.contains('debit') || type == 'dr') return false;

    final amount = row['amount'];
    num raw = 0;
    if (amount is Map && amount['raw'] is num) raw = amount['raw'];
    if (amount is num) raw = amount;
    if (amount is String) raw = num.tryParse(amount.replaceAll(',', '')) ?? 0;
    return raw >= 0;
  }

  String _title(Map<String, dynamic> row) {
    final description = (row['description'] ?? row['note'] ?? '').toString();
    if (description.isNotEmpty) return description;
    return _isCredit(row) ? 'Wallet Top-Up' : 'Wallet Debit';
  }

  String _date(Map<String, dynamic> row) {
    final raw = row['created_at'] ?? row['date'] ?? row['timestamp'];
    DateTime? date;
    if (raw is int) {
      date = DateTime.fromMillisecondsSinceEpoch(
        raw > 2000000000 ? raw : raw * 1000,
      );
    }
    if (raw is String) date ??= DateTime.tryParse(raw);
    date ??= DateTime.now();
    return DateFormat('EEE, dd MMM yyyy, HH:mm').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet History'),
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView.builder(
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
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: _kRed, size: 48),
                const SizedBox(height: 8),
                const Text(
                  'Could not load history',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _kGrey),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No transactions yet'),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _rows.length,
      itemBuilder: (_, index) {
        final row = _rows[index];
        final isCredit = _isCredit(row);
        final amount = _fmtAmount(row['amount'] ?? row['value']);

        return Card(
          elevation: 0.8,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isCredit ? _kGreen : _kRed).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCredit ? Icons.south_west : Icons.north_east,
                color: isCredit ? _kGreen : _kRed,
                size: 22,
              ),
            ),
            title: Text(
              _title(row),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _date(row),
              style: const TextStyle(color: _kGrey, fontSize: 12.5),
            ),
            trailing: Text(
              '${isCredit ? '+' : '-'}$amount',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isCredit ? _kGreen : _kRed,
              ),
            ),
          ),
        );
      },
    );
  }
}
