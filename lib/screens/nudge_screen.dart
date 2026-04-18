// lib/screens/nudge_screen.dart
//
// Full-screen behavior-change nudge overlay.
// Shown when a watched spending app is detected as foreground.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/behavior_engine.dart';
import '../services/response_tracker.dart';
import '../main.dart';

class NudgeScreen extends StatefulWidget {
  final String packageName;
  final String appName;
  final int riskScore;

  const NudgeScreen({
    super.key,
    required this.packageName,
    required this.appName,
    required this.riskScore,
  });

  @override
  State<NudgeScreen> createState() => _NudgeScreenState();
}

class _NudgeScreenState extends State<NudgeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  bool _deciding = false;
  bool _showExpenseForm = false;
  late TextEditingController _amountCtrl;

  // Design tokens (match main.dart palette - WARM LIGHT THEME)
  static const kBg     = Color(0xFFFFFBF0);      // Warm cream background
  static const kSurface= Color(0xFFFFFFFF);      // Pure white
  static const kTeal   = Color(0xFF10B981);      // Fresh green
  static const kGreen  = Color(0xFF34D399);      // Mint green
  static const kRed    = Color(0xFFF87171);      // Coral red
  static const kAmber  = Color(0xFFFB923C);      // Warm amber
  static const kMuted  = Color(0xFF7D6B5F);      // Warm muted brown
  static const kBorder = Color(0xFFFFDFC9);      // Warm soft border

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeIn  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _amountCtrl = TextEditingController();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Color get _riskColor {
    if (widget.riskScore >= 75) return kRed;
    if (widget.riskScore >= 50) return kAmber;
    return kTeal;
  }

  String get _riskLabel {
    if (widget.riskScore >= 75) return '🔴  High Risk';
    if (widget.riskScore >= 50) return '🟡  Medium Risk';
    return '🟢  Low Risk';
  }

  WatchedApp? get _app => BehaviorEngine.watchedApps[widget.packageName];

  double get _avgSpend => _app?.avgSpend ?? 300;

  double _sipProjection(int years) {
    final monthly = _avgSpend;
    final months  = years * 12;
    const r       = 0.12 / 12;
    // FV of annuity
    return monthly * (math.pow(1 + r, months) - 1) / r * (1 + r);
  }

  String _fmtINR(double v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  // ── Decision handlers ──────────────────────────────────────────────────

  Future<void> _decide(NudgeDecision decision) async {
    if (_deciding) return;
    setState(() => _deciding = true);

    await ResponseTracker.record(NudgeEvent(
      packageName: widget.packageName,
      appName:     widget.appName,
      riskScore:   widget.riskScore,
      decision:    decision,
      timestamp:   DateTime.now(),
    ));

    if (mounted) {
      if (decision == NudgeDecision.proceeded) {
        // Show expense logging form instead of closing
        setState(() {
          _showExpenseForm = true;
          _deciding = false;
        });
      } else {
        Navigator.of(context).pop(decision);
      }
    }
  }

  Future<void> _logExpense() async {
    final state = AppStateProvider.of(context);
    final amount = double.tryParse(_amountCtrl.text);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid amount')),
      );
      return;
    }

    final expense = Expense(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: widget.appName,
      amount: amount,
      frequency: 'monthly',
      tag: 'impulse',
      linkedPackage: widget.packageName,
      source: 'nudge',
      transactionDate: DateTime.now(),
    );

    state.addExpense(expense);

    if (mounted) {
      Navigator.of(context).pop(NudgeDecision.proceeded);
      SystemNavigator.pop();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _slideUp,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildAppCard(),
                  const SizedBox(height: 16),
                  _buildCostCard(),
                  const SizedBox(height: 16),
                  _buildAlternativeCard(),
                  const Spacer(),
                  _buildButtons(),
                  const SizedBox(height: 12),
                  _buildDismiss(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ────────────────────────────────────────────────────────

  Widget _buildHeader() => Row(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: _riskColor.withOpacity(0.12),
          border: Border.all(color: _riskColor.withOpacity(0.3)),
        ),
        child: Text(_riskLabel,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: _riskColor)),
      ),
      const Spacer(),
      Text('Score: ${widget.riskScore}/100',
          style: const TextStyle(fontSize: 12, color: kMuted)),
    ],
  );

  Widget _buildAppCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: kSurface,
      border: Border.all(color: _riskColor.withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('You\'re about to open',
          style: TextStyle(fontSize: 13, color: kMuted)),
      const SizedBox(height: 6),
      Text(widget.appName,
          style: const TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: -0.8)),
      const SizedBox(height: 10),
      Text('Avg session spend • ${_fmtINR(_avgSpend)}',
          style: const TextStyle(fontSize: 13, color: kMuted)),
    ]),
  );

  Widget _buildCostCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: kRed.withOpacity(0.05),
      border: Border.all(color: kRed.withOpacity(0.15)),
    ),
    child: Row(children: [
      const Text('🔥', style: TextStyle(fontSize: 22)),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Annual cost of this habit',
            style: TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 2),
        Text(_fmtINR(_avgSpend * 12),
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: kRed)),
      ]),
    ]),
  );

  Widget _buildAlternativeCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: kTeal.withOpacity(0.05),
      border: Border.all(color: kTeal.withOpacity(0.15)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💡  Invest instead',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: kTeal)),
      const SizedBox(height: 12),
      Row(children: [
        _altTile('3 years', _sipProjection(3)),
        const SizedBox(width: 10),
        _altTile('5 years', _sipProjection(5)),
        const SizedBox(width: 10),
        _altTile('10 years', _sipProjection(10)),
      ]),
      const SizedBox(height: 10),
      Text('At 12% p.a. if you redirected ${_fmtINR(_avgSpend)}/mo into a SIP',
          style: const TextStyle(fontSize: 11, color: kMuted)),
    ]),
  );

  Widget _altTile(String label, double value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: kTeal.withOpacity(0.08),
      ),
      child: Column(children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: kMuted)),
        const SizedBox(height: 4),
        Text(_fmtINR(value),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: kTeal)),
      ]),
    ),
  );

  Widget _buildButtons() {
    if (_showExpenseForm) {
      return Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: kGreen.withOpacity(0.05),
            border: Border.all(color: kGreen.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Did you spend?', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kGreen)),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'How much? (₹)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kGreen),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showExpenseForm = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      border: Border.all(color: kMuted),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Skip', style: TextStyle(fontSize:13, color: kMuted, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _logExpense,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [kTeal, kGreen]),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Yes, log it', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ]);
    }

    return Column(children: [
      // Primary — skip
      SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: () => _decide(NudgeDecision.skipped),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [kTeal, kGreen]),
            ),
            child: const Center(
              child: Text("I'll skip it  ✓",
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Secondary — proceed
      SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: () => _decide(NudgeDecision.proceeded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: kRed.withOpacity(0.08),
              border: Border.all(color: kRed.withOpacity(0.2)),
            ),
            child: const Center(
              child: Text('Proceed anyway',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: kRed)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildDismiss() => GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Center(
      child: Text('Swipe up or tap to dismiss',
          style: TextStyle(fontSize: 11, color: kMuted.withOpacity(0.5))),
    ),
  );
}
