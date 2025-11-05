import 'package:flutter/material.dart';

// 🎨 Brand Colors
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({Key? key}) : super(key: key);

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final List<Map<String, dynamic>> _faqs = [
    {
      'question': 'How do I track my order?',
      'answer': 'You can track your order by going to "My Orders" section in your profile. Click on any order to see detailed tracking information.',
      'category': 'Orders',
    },
    {
      'question': 'What is your return policy?',
      'answer': 'We offer a 30-day return policy on most items. Products must be unused and in original packaging. Contact customer support to initiate a return.',
      'category': 'Returns',
    },
    {
      'question': 'How long does shipping take?',
      'answer': 'Standard shipping takes 3-5 business days. Express shipping is available for 1-2 day delivery. Shipping times may vary based on your location.',
      'category': 'Shipping',
    },
    {
      'question': 'How can I change my delivery address?',
      'answer': 'Go to "Addresses" in your profile settings. You can add, edit, or set a default delivery address there.',
      'category': 'Account',
    },
    {
      'question': 'What payment methods do you accept?',
      'answer': 'We accept credit/debit cards (Visa, Mastercard, Amex), PayPal, and digital wallets like Apple Pay and Google Pay.',
      'category': 'Payment',
    },
    {
      'question': 'How do I cancel an order?',
      'answer': 'Orders can be cancelled within 1 hour of placement. Go to "My Orders", select the order, and click "Cancel Order". After processing begins, cancellations may not be possible.',
      'category': 'Orders',
    },
    {
      'question': 'Are there any shipping charges?',
      'answer': 'Free shipping on orders over \$50. Orders under \$50 have a flat shipping fee of \$5.99. Express shipping costs extra.',
      'category': 'Shipping',
    },
    {
      'question': 'How do I reset my password?',
      'answer': 'Click on "Forgot Password?" on the login page. Enter your email and we\'ll send you a reset link. You can also change your password in Privacy & Security settings.',
      'category': 'Account',
    },
  ];

  String _selectedCategory = 'All';

  List<String> get _categories {
    final cats = _faqs.map((faq) => faq['category'] as String).toSet().toList();
    return ['All', ...cats];
  }

  List<Map<String, dynamic>> get _filteredFaqs {
    if (_selectedCategory == 'All') return _faqs;
    return _faqs.where((faq) => faq['category'] == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Help Center',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryBlue, kAccentBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.help_outline_rounded,
                  size: 60,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                const Text(
                  'How can we help you?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search for help...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Category Filter
          Container(
            height: 50,
            margin: const EdgeInsets.symmetric(vertical: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedCategory = category);
                    },
                    selectedColor: kPrimaryBlue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),

          // FAQ List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredFaqs.length + 1,
              itemBuilder: (context, index) {
                if (index == _filteredFaqs.length) {
                  return _buildContactSection();
                }
                return _buildFaqItem(_filteredFaqs[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem(Map<String, dynamic> faq) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kPrimaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.help_outline,
              color: kPrimaryBlue,
              size: 20,
            ),
          ),
          title: Text(
            faq['question'],
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [
            Text(
              faq['answer'],
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactSection() {
    return Container(
      margin: const EdgeInsets.only(top: 24, bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Still need help?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Contact our support team',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildContactButton(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildContactButton(
                  icon: Icons.chat_outlined,
                  label: 'Live Chat',
                  onTap: () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: kPrimaryBlue.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: kPrimaryBlue, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kPrimaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
