import 'package:flutter/material.dart';
import '../main.dart';
import '../services/sms_parser.dart';

class SmsReviewSheet extends StatefulWidget {
  final ParsedTransaction transaction;
  final Function(Expense) onConfirm;

  const SmsReviewSheet({
    Key? key,
    required this.transaction,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<SmsReviewSheet> createState() => _SmsReviewSheetState();
}

class _SmsReviewSheetState extends State<SmsReviewSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _amountCtrl;
  String _selectedTag = 'impulse';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.transaction.merchant);
    _amountCtrl = TextEditingController(text: widget.transaction.amount.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        color: kBgSoft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Import Transaction', style: spaceGrotesk(size: 18, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Detected from SMS', style: jakarta(size: 12, color: kMuted)),
            const SizedBox(height: 16),

            // Amount display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: kPanel,
                border: Border.all(color: kBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Amount', style: jakarta(size: 12, color: kMuted)),
                  Text('₹${widget.transaction.amount.toStringAsFixed(0)}',
                      style: spaceGrotesk(size: 16, weight: FontWeight.w700, color: kTeal)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Merchant name
            TextField(
              controller: _nameCtrl,
              style: jakarta(size: 13),
              decoration: InputDecoration(
                hintText: 'Merchant name',
                labelText: 'Merchant',
              ),
            ),
            const SizedBox(height: 12),

            // Amount field (editable)
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: jakarta(size: 13),
              decoration: InputDecoration(
                hintText: 'Amount (₹)',
                labelText: 'Adjust amount',
              ),
            ),
            const SizedBox(height: 16),

            // Tag selection
            Text('Category', style: jakarta(size: 12, color: kMuted, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _TagButton(
                  label: 'Essential',
                  icon: Icons.check_circle_outline,
                  color: kGreen,
                  isSelected: _selectedTag == 'essential',
                  onTap: () => setState(() => _selectedTag = 'essential'),
                ),
                const SizedBox(width: 8),
                _TagButton(
                  label: 'Avoidable',
                  icon: Icons.remove_circle,
                  color: kAmber,
                  isSelected: _selectedTag == 'avoidable',
                  onTap: () => setState(() => _selectedTag = 'avoidable'),
                ),
                const SizedBox(width: 8),
                _TagButton(
                  label: 'Impulse',
                  icon: Icons.cancel_outlined,
                  color: kRed,
                  isSelected: _selectedTag == 'impulse',
                  onTap: () => setState(() => _selectedTag = 'impulse'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kBorder),
                      ),
                      alignment: Alignment.center,
                      child: Text('Cancel',
                          style: jakarta(size: 13, weight: FontWeight.w600, color: kMuted)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final amount = double.tryParse(_amountCtrl.text) ?? widget.transaction.amount;
                      final linkedPkg = SmsParser.fuzzyMatchWatchedApp(_nameCtrl.text);

                      final expense = Expense(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: _nameCtrl.text.trim(),
                        amount: amount,
                        frequency: 'monthly',
                        tag: _selectedTag,
                        linkedPackage: linkedPkg,
                        source: 'sms_import',
                        transactionDate: widget.transaction.datetime,
                      );

                      widget.onConfirm(expense);
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(colors: [kTeal, kGreen]),
                      ),
                      alignment: Alignment.center,
                      child: Text('Add Expense',
                          style: jakarta(size: 13, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TagButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _TagButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? color.withOpacity(0.15) : kPanel,
            border: Border.all(color: isSelected ? color : kBorder),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(label, style: jakarta(size: 10, color: color, weight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
