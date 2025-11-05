import 'package:flutter/material.dart';

// 🎨 Brand Colors
const kPrimaryBlue = Color(0xFF004AAD);
const kAccentBlue = Color(0xFF0096FF);
const kRed = Color(0xFFE53935);
const kGreen = Color(0xFF43A047);

class AddressesPage extends StatefulWidget {
  const AddressesPage({Key? key}) : super(key: key);

  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends State<AddressesPage> {
  // Mock addresses - replace with actual data from WooCommerce
  final List<Map<String, dynamic>> _addresses = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'My Addresses',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddAddressSheet(),
            tooltip: 'Add Address',
          ),
        ],
      ),
      body: _addresses.isEmpty
          ? _buildEmptyView()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _addresses.length,
              itemBuilder: (context, index) {
                return _buildAddressCard(_addresses[index], index);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAddressSheet(),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white, // ✅ readable label/icon
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Address'),
      ),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> address, int index) {
    final isDefault = address['is_default'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDefault ? Border.all(color: kPrimaryBlue, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        address['type'] == 'work'
                            ? Icons.work_outline
                            : Icons.home_outlined,
                        color: kPrimaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        address['label'] ?? 'Address',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kPrimaryBlue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    if (!isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 20),
                            SizedBox(width: 12),
                            Text('Set as Default'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: kRed),
                          SizedBox(width: 12),
                          Text('Delete', style: TextStyle(color: kRed)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showAddAddressSheet(address: address, index: index);
                    } else if (value == 'default') {
                      _setDefaultAddress(index);
                    } else if (value == 'delete') {
                      _deleteAddress(index);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              address['name'] ?? '',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              address['full_address'] ?? '',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            if (address['phone'] != null && (address['phone'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    address['phone'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPrimaryBlue.withOpacity(0.1),
            ),
            child: const Icon(
              Icons.location_on_outlined,
              size: 60,
              color: kPrimaryBlue,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Addresses Saved',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Add your delivery addresses for faster checkout',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ===== Bottom Sheet (overflow-safe) =========================================
  void _showAddAddressSheet({Map<String, dynamic>? address, int? index}) {
    final isEdit = address != null;

    final labelController = TextEditingController(text: address?['label']);
    final nameController = TextEditingController(text: address?['name']);
    final addressController = TextEditingController(text: address?['full_address']);
    final phoneController = TextEditingController(text: address?['phone']);
    String selectedType = address?['type'] ?? 'home';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _AddEditAddressSheet(
          isEdit: isEdit,
          initialType: selectedType,
          labelController: labelController,
          nameController: nameController,
          addressController: addressController,
          phoneController: phoneController,
          onConfirm: (payload) {
            setState(() {
              if (isEdit && index != null) {
                _addresses[index] = payload;
              } else {
                _addresses.add({
                  ...payload,
                  'is_default': _addresses.isEmpty, // first one default
                });
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isEdit ? 'Address updated!' : 'Address added!'),
                backgroundColor: kGreen,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }

  void _setDefaultAddress(int index) {
    setState(() {
      for (var i = 0; i < _addresses.length; i++) {
        _addresses[i]['is_default'] = i == index;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Default address updated!'),
        backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _deleteAddress(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Address'),
        content: const Text('Are you sure you want to delete this address?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _addresses.removeAt(index));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Address deleted!'),
                  backgroundColor: kRed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ====== SHEET WIDGETS =========================================================

class _AddEditAddressSheet extends StatefulWidget {
  final bool isEdit;
  final String initialType;
  final TextEditingController labelController;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final void Function(Map<String, dynamic> payload) onConfirm;

  const _AddEditAddressSheet({
    required this.isEdit,
    required this.initialType,
    required this.labelController,
    required this.nameController,
    required this.addressController,
    required this.phoneController,
    required this.onConfirm,
  });

  @override
  State<_AddEditAddressSheet> createState() => _AddEditAddressSheetState();
}

class _AddEditAddressSheetState extends State<_AddEditAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _type = widget.initialType;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + close
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.isEdit ? 'Edit Address' : 'Add New Address',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Type chips (wrap to avoid overflow)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _TypeChip(
                          label: 'Home',
                          icon: Icons.home_rounded,
                          selected: _type == 'home',
                          onTap: () => setState(() => _type = 'home'),
                        ),
                        _TypeChip(
                          label: 'Work',
                          icon: Icons.work_rounded,
                          selected: _type == 'work',
                          onTap: () => setState(() => _type = 'work'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    _Field(
                      controller: widget.labelController,
                      labelText: 'Label (e.g., Home, Office)',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a label' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    _Field(
                      controller: widget.nameController,
                      labelText: 'Full Name',
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter full name' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),

                    _Field(
                      controller: widget.addressController,
                      labelText: 'Full Address',
                      maxLines: 3,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter full address' : null,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: 12),

                    _Field(
                      controller: widget.phoneController,
                      labelText: 'Phone Number',
                      keyboardType: TextInputType.phone,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone number' : null,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: kPrimaryBlue,
                              foregroundColor: Colors.white, // ✅ readable text
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    widget.isEdit ? 'Update' : 'Add',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final payload = {
      'type': _type,
      'label': widget.labelController.text.trim(),
      'name': widget.nameController.text.trim(),
      'full_address': widget.addressController.text.trim(),
      'phone': widget.phoneController.text.trim(),
    };

    // TODO: wire to backend/provider
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;
    Navigator.pop(context); // close sheet
    widget.onConfirm(payload);
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kPrimaryBlue.withOpacity(0.12) : Colors.white,
          border: Border.all(
            color: selected ? kPrimaryBlue : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? kPrimaryBlue : Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? kPrimaryBlue : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _Field({
    required this.controller,
    required this.labelText,
    this.validator,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: labelText,
        alignLabelWithHint: maxLines > 1,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
