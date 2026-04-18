// ══════════════════════════════════════════════════════════════════════════
//  EXPENSE AUTOPSY — Flutter port of My-track web app
//  Design tokens, typography and layout match the web exactly:
//    bg #050816 · teal #35f0d2 · green #7dff6c · blue #66b8ff
//    amber #f2c66d · red #ff7f8a · fonts: Space Grotesk + Plus Jakarta Sans
// ══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/behavior_engine.dart';
import 'services/monitor_service.dart';
import 'services/response_tracker.dart';
import 'services/app_open_tracker.dart';
import 'services/db_service.dart';
import 'services/sms_monitor.dart';
import 'services/sms_parser.dart';
import 'services/monthly_snapshot_service.dart';
import 'screens/nudge_screen.dart';
import 'screens/sms_review_sheet.dart';

// ─── Design tokens ──────────────────────────────────────────────────────────
const Color kBg = Color(0xFFFFFBF0); // Warm cream background
const Color kBgSoft = Color(0xFFFFFFFF); // Pure white
const Color kPanel = Color(0xFFFEF5E7); // Soft warm panel
const Color kPanelStrong = Color(0xFFFCEDDB); // Warmer panel accent
const Color kBorder = Color(0xFFFFDFC9); // Warm soft border
const Color kBorderStrong = Color(0xFFFFC9A8); // Warmer border
const Color kText = Color(0xFF2D1810); // Warm dark brown text
const Color kMuted = Color(0xFF7D6B5F); // Warm muted brown
const Color kMutedStrong = Color(0xFF5A4A3A); // Warm strong brown
const Color kTeal = Color(0xFF10B981); // Fresh green
const Color kGreen = Color(0xFF34D399); // Mint green
const Color kBlue = Color(0xFF3B82F6); // Sky blue
const Color kAmber = Color(0xFFFB923C); // Warm amber
const Color kRed = Color(0xFFF87171); // Coral red

// ─── Text styles ─────────────────────────────────────────────────────────────
TextStyle spaceGrotesk({
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color color = kText,
  double? letterSpacing,
}) => GoogleFonts.spaceGrotesk(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
);

TextStyle jakarta({
  double size = 14,
  FontWeight weight = FontWeight.w400,
  Color color = kText,
  double? letterSpacing,
}) => GoogleFonts.plusJakartaSans(
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: letterSpacing,
);

// ─── Demo data ───────────────────────────────────────────────────────────────
class Expense {
  final String id, name, frequency, tag;
  final double amount;
  final String? linkedPackage; // e.g. 'in.swiggy.android'
  final String source; // 'manual', 'sms_import', 'nudge'
  final DateTime transactionDate; // when the spend happened

  Expense({
    required this.id,
    required this.name,
    required this.amount,
    required this.frequency,
    required this.tag,
    this.linkedPackage,
    this.source = 'manual',
    DateTime? transactionDate,
  }) : transactionDate = transactionDate ?? DateTime.now();

  Expense copyWith({String? tag, String? source, DateTime? transactionDate}) =>
      Expense(
        id: id,
        name: name,
        amount: amount,
        frequency: frequency,
        tag: tag ?? this.tag,
        linkedPackage: linkedPackage,
        source: source ?? this.source,
        transactionDate: transactionDate ?? this.transactionDate,
      );
}

class Goal {
  final String id, name, targetDate;
  final double targetAmount, savedAmount;
  final int priority;
  const Goal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.targetDate,
    required this.priority,
    required this.savedAmount,
  });
}

// No hardcoded demo lists. All data is seeded in MongoDB and loaded in AppState._initData().


double _monthlyEquiv(double amount, String freq) {
  if (freq == 'daily') return amount * 30;
  if (freq == 'weekly') return amount * 52 / 12;
  return amount;
}

double _monthlyLeakage(List<Expense> expenses) => expenses
    .where((e) => e.tag != 'essential')
    .fold(0, (sum, e) => sum + _monthlyEquiv(e.amount, e.frequency));

double _monthlyTotal(List<Expense> expenses) =>
    expenses.fold(0, (sum, e) => sum + _monthlyEquiv(e.amount, e.frequency));

double _futureValue(double monthly, double annualRate, int months) {
  final r = annualRate / 100 / 12;
  if (r == 0) return monthly * months;
  return monthly * ((math.pow(1 + r, months) - 1) / r) * (1 + r);
}

String _fmtINR(double v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
  return '₹${v.toStringAsFixed(0)}';
}

// ─── App state (simple InheritedNotifier) ────────────────────────────────────
class AppState extends ChangeNotifier {
  List<Expense> expenses = [];
  List<Goal> goals = [];
  double monthlySalary = 0;
  double sipAmount = 0;
  double sipReturn = 12;
  int sipMonths = 120;

  String userName = 'User';
  String userEmail = 'vikas@example.com';
  String userOccupation = '';
  String userCity = '';
  bool isLoading = true;

  AppState() {
    _initData();
  }

  Future<void> _initData() async {
    try {
      // ── 1. User profile
      final userData = await DbService.fetchUserData(userEmail);
      if (userData != null) {
        final profile = userData['profile'] as Map<String, dynamic>? ?? {};
        final sip     = userData['sip']     as Map<String, dynamic>? ?? {};
        monthlySalary   = (profile['monthlySalary'] as num?)?.toDouble() ?? 0;
        userName        = profile['name']           as String? ?? 'User';
        userOccupation  = profile['occupation']     as String? ?? '';
        userCity        = profile['city']           as String? ?? '';
        sipAmount       = (sip['monthlyAmount']  as num?)?.toDouble() ?? 0;
        sipReturn       = (sip['annualReturn']   as num?)?.toDouble() ?? 12;
        sipMonths       = (sip['durationMonths'] as num?)?.toInt()    ?? 120;
      }

      // ── 2. Expenses from DB
      final expDocs = await DbService.fetchUserExpenses(userEmail);
      expenses = expDocs.map(_expenseFromDoc).toList();

      // ── 3. Goals from DB
      final goalDocs = await DbService.fetchUserGoals(userEmail);
      goals = goalDocs.map(_goalFromDoc).toList();
    } catch (e) {
      if (kDebugMode) print('AppState._initData error: $e');
    }
    isLoading = false;
    notifyListeners();
  }

  // ── Mappers ─────────────────────────────────────────────────────────────

  static Expense _expenseFromDoc(Map<String, dynamic> doc) {
    return Expense(
      id:              (doc['_id'] ?? doc['id']).toString(),
      name:            doc['name']      as String? ?? 'Unknown',
      amount:          (doc['amount']   as num?)?.toDouble() ?? 0,
      frequency:       doc['frequency'] as String? ?? 'monthly',
      tag:             doc['tag']       as String? ?? 'avoidable',
      linkedPackage:   doc['linkedPackage'] as String?,
      source:          doc['source']    as String? ?? 'manual',
      transactionDate: doc['transactionDate'] is DateTime
          ? doc['transactionDate'] as DateTime
          : DateTime.tryParse(doc['transactionDate']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static Goal _goalFromDoc(Map<String, dynamic> doc) {
    return Goal(
      id:           (doc['_id'] ?? doc['id']).toString(),
      name:         doc['name']         as String? ?? 'Goal',
      targetAmount: (doc['targetAmount'] as num?)?.toDouble() ?? 0,
      savedAmount:  (doc['savedAmount']  as num?)?.toDouble() ?? 0,
      targetDate:   doc['targetDate']   as String? ?? '',
      priority:     (doc['priority']    as num?)?.toInt()    ?? 1,
    );
  }

  void toggleExpenseTag(String id) {
    expenses = expenses.map((e) {
      if (e.id != id) return e;
      final next = e.tag == 'essential'
          ? 'avoidable'
          : e.tag == 'avoidable'
          ? 'impulse'
          : 'essential';
      return e.copyWith(tag: next);
    }).toList();
    notifyListeners();
  }

  void addExpense(Expense e) {
    expenses = [e, ...expenses];
    notifyListeners();
  }

  void removeExpense(String id) {
    expenses = expenses.where((e) => e.id != id).toList();
    notifyListeners();
  }

  void addGoal(Goal g) {
    goals = [g, ...goals];
    notifyListeners();
  }

  void removeGoal(String id) {
    goals = goals.where((g) => g.id != id).toList();
    notifyListeners();
  }

  void setSip({double? amount, double? ret, int? months}) {
    if (amount != null) sipAmount = amount;
    if (ret != null) sipReturn = ret;
    if (months != null) sipMonths = months;
    notifyListeners();
  }

  /// Update profile fields in-memory AND persist to MongoDB.
  Future<bool> updateProfile({
    required String name,
    required double salary,
    required double sip,
    required double ret,
    required int months,
    String occupation = '',
    String city = '',
  }) async {
    userName       = name;
    monthlySalary  = salary;
    sipAmount      = sip;
    sipReturn      = ret;
    sipMonths      = months;
    userOccupation = occupation;
    userCity       = city;
    notifyListeners();

    return DbService.updateUserProfile(
      userEmail,
      name:          name,
      monthlySalary: salary,
      sipAmount:     sip,
      sipReturn:     ret,
      sipMonths:     months,
      occupation:    occupation,
      city:          city,
    );
  }
}

class AppStateProvider extends InheritedNotifier<AppState> {
  const AppStateProvider({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);
  static AppState of(BuildContext ctx) =>
      ctx.dependOnInheritedWidgetOfExactType<AppStateProvider>()!.notifier!;
}

// ═══════════════════════════════════════════════════════════════════════════
//  ENTRY POINT
// ═══════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(AppStateProvider(state: AppState(), child: const ExpenseAutopsyApp()));
}

class ExpenseAutopsyApp extends StatelessWidget {
  const ExpenseAutopsyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Autopsy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.light(primary: kTeal, surface: kPanel),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(
          ThemeData.light().textTheme,
        ),
        useMaterial3: true,
        sliderTheme: SliderThemeData(
          activeTrackColor: kTeal,
          thumbColor: kTeal,
          inactiveTrackColor: kTeal.withOpacity(0.15),
          overlayColor: kTeal.withOpacity(0.10),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kPanel,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: kTeal.withOpacity(0.4), width: 1.5),
          ),
          hintStyle: jakarta(color: kMuted, size: 13),
          labelStyle: jakarta(color: kMuted, size: 13),
        ),
      ),
      home: const AppShell(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  APP SHELL — Bottom Navigation
// ═══════════════════════════════════════════════════════════════════════════
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;
  bool _nudgeActive = false;
  bool _smsSheetActive = false;

  // Throttle: only one nudge per app per 60 minutes
  final Map<String, DateTime> _lastNudge = {};

  // SMS Monitoring
  StreamSubscription<ParsedTransaction>? _smsSub;

  static const _pages = [
    DashboardPage(),
    ExpensesPage(),
    SimulatorPage(),
    GoalsPage(),
    InsightsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _initMonitor();
    _initSmsMonitoring();
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    super.dispose();
  }

  Future<void> _initMonitor() async {
    final hasUsage = await MonitorService.hasUsagePermission();
    final hasOverlay = await MonitorService.hasOverlayPermission();

    if (hasUsage) {
      MonitorService.setOnAppOpen(_onAppOpen);
      await MonitorService.startMonitor();
    } else {
      // Show permission prompt on first launch after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _showPermissionSheet(hasUsage, hasOverlay);
      });
    }
  }

  Future<void> _initSmsMonitoring() async {
    // Initialize SMS monitoring
    await SmsMonitor.init();

    // Listen to incoming SMS transactions
    _smsSub = SmsMonitor.stream.listen((transaction) {
      if (!mounted) return;
      _showSmsReviewSheet(transaction);
    });

    // Take monthly snapshot if needed
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        final state = AppStateProvider.of(context);
        MonthlySnapshotService.takeSnapshotIfNeeded(state);
      }
    });
  }

  void _showSmsReviewSheet(ParsedTransaction transaction) {
    if (_smsSheetActive) return;
    _smsSheetActive = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: kBgSoft,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (_) => SmsReviewSheet(
        transaction: transaction,
        onConfirm: (expense) {
          final state = AppStateProvider.of(context);
          state.addExpense(expense);
          Navigator.pop(context);
          _smsSheetActive = false;
        },
      ),
    ).then((_) {
      _smsSheetActive = false;
    });
  }

  Future<void> _onAppOpen(String pkg, String appName) async {
    if (_nudgeActive) return;

    // Record this app open regardless of nudge
    await AppOpenTracker.recordOpen(pkg);

    // Throttle — once per hour per app
    final lastTime = _lastNudge[pkg];
    if (lastTime != null &&
        DateTime.now().difference(lastTime).inMinutes < 60) {
      return;
    }

    final state = AppStateProvider.of(context);
    final openCount = await AppOpenTracker.openCountToday(pkg);
    final budgetUsed = state.monthlySalary > 0
        ? _monthlyTotal(state.expenses) / state.monthlySalary
        : 0.5;
    final leakage = _monthlyLeakage(state.expenses);

    final risk = BehaviorEngine.score(
      packageName: pkg,
      openCountToday: openCount,
      budgetUsedPct: budgetUsed,
      monthlyLeakage: leakage,
    );

    if (risk < 50) return; // below threshold — skip nudge

    _nudgeActive = true;
    _lastNudge[pkg] = DateTime.now();

    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) =>
            NudgeScreen(packageName: pkg, appName: appName, riskScore: risk),
      ),
    );
    _nudgeActive = false;
  }

  void _showPermissionSheet(bool hasUsage, bool hasOverlay) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B1120),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PermissionSheet(
        hasUsage: hasUsage,
        hasOverlay: hasOverlay,
        onGranted: _initMonitor,
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppState state) {
    return Drawer(
      backgroundColor: kBgSoft,
      child: Column(
        children: [
          // Header with profile
          Container(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
            decoration: BoxDecoration(
              color: kPanel,
              border: Border(bottom: BorderSide(color: kBorder)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [kTeal, kGreen]),
                  ),
                  child: Center(
                    child: Text(
                      state.userName.isNotEmpty
                          ? state.userName[0].toUpperCase()
                          : 'U',
                      style: spaceGrotesk(
                        size: 18,
                        weight: FontWeight.w700,
                        color: const Color(0xFF050816),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.userName,
                        style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${state.monthlySalary.toStringAsFixed(0)}/mo',
                        style: jakarta(size: 11, color: kMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Menu items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _drawerItem(
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  onTap: () {
                    setState(() => _tab = 0);
                    Navigator.pop(context);
                  },
                  selected: _tab == 0,
                ),
                _drawerItem(
                  icon: Icons.receipt_long_rounded,
                  label: 'Expenses',
                  onTap: () {
                    setState(() => _tab = 1);
                    Navigator.pop(context);
                  },
                  selected: _tab == 1,
                ),
                _drawerItem(
                  icon: Icons.candlestick_chart_rounded,
                  label: 'Simulator',
                  onTap: () {
                    setState(() => _tab = 2);
                    Navigator.pop(context);
                  },
                  selected: _tab == 2,
                ),
                _drawerItem(
                  icon: Icons.flag_rounded,
                  label: 'Goals',
                  onTap: () {
                    setState(() => _tab = 3);
                    Navigator.pop(context);
                  },
                  selected: _tab == 3,
                ),
                _drawerItem(
                  icon: Icons.lightbulb_rounded,
                  label: 'Insights',
                  onTap: () {
                    setState(() => _tab = 4);
                    Navigator.pop(context);
                  },
                  selected: _tab == 4,
                ),
                const Divider(color: Color(0x17FFFFFF), height: 20),
                _drawerItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  onTap: () {
                    Navigator.pop(context);
                    _showProfileModal(context, state);
                  },
                ),
                _drawerItem(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings coming soon')),
                    );
                  },
                ),
                _drawerItem(
                  icon: Icons.help_rounded,
                  label: 'Help',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Help & Support coming soon'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(icon, color: selected ? kTeal : kMuted, size: 22),
      title: Text(
        label,
        style: jakarta(
          size: 14,
          weight: FontWeight.w600,
          color: selected ? kTeal : kText,
        ),
      ),
      onTap: onTap,
      selected: selected,
      selectedTileColor: kTeal.withOpacity(0.08),
    );
  }

  void _showProfileModal(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _EditProfileSheet(state: state),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (AppStateProvider.of(context).isLoading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator(color: kTeal)),
      );
    }

    final state = AppStateProvider.of(context);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBgSoft,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Expense Autopsy',
          style: spaceGrotesk(size: 18, weight: FontWeight.w700),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: kTeal),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => _showProfileModal(context, state),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [kTeal, kGreen]),
                  boxShadow: [
                    BoxShadow(color: kTeal.withOpacity(0.3), blurRadius: 8),
                  ],
                ),
                child: Center(
                  child: Text(
                    state.userName.isNotEmpty
                        ? state.userName[0].toUpperCase()
                        : 'U',
                    style: spaceGrotesk(
                      size: 16,
                      weight: FontWeight.w700,
                      color: const Color(0xFF050816),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(context, state),
      body: _AmbientBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: KeyedSubtree(key: ValueKey(_tab), child: _pages[_tab]),
        ),
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: jakarta(size: 13, color: kMuted)),
        Text(
          value,
          style: spaceGrotesk(size: 13, weight: FontWeight.w700, color: kTeal),
        ),
      ],
    );
  }
}

// ─── Ambient gradient background ─────────────────────────────────────────────
class _AmbientBackground extends StatelessWidget {
  final Widget child;
  const _AmbientBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.7, -0.8),
                radius: 1.0,
                colors: [kTeal.withOpacity(0.07), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.7, -0.8),
                radius: 0.9,
                colors: [kBlue.withOpacity(0.07), Colors.transparent],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

/// Glass card matching the web's .card / .dashboard-panel
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  final double radius;
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? kBorder, width: 1),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x0AFFFFFF), Color(0x05FFFFFF)],
        ),
        color: kPanel.withOpacity(0.78),
      ),
      child: Stack(
        children: [
          // teal top-left glow matching ::before in CSS
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: RadialGradient(
                  center: const Alignment(-1, -1),
                  radius: 1.0,
                  colors: [kTeal.withOpacity(0.10), Colors.transparent],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Pill badge — matches web .pill
class Pill extends StatelessWidget {
  final String label;
  final String tone; // 'teal', 'positive', 'warning', 'default'
  const Pill({super.key, required this.label, this.tone = 'default'});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (tone) {
      case 'teal':
        bg = kTeal.withOpacity(0.12);
        fg = kTeal;
      case 'positive':
        bg = kGreen.withOpacity(0.12);
        fg = kGreen;
      case 'warning':
        bg = kAmber.withOpacity(0.12);
        fg = kAmber;
      default:
        bg = Colors.white.withOpacity(0.06);
        fg = kMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: bg,
        border: Border.all(color: fg.withOpacity(0.25), width: 1),
      ),
      child: Text(
        label,
        style: jakarta(size: 11, weight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Eyebrow label
class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: jakarta(
      size: 11,
      weight: FontWeight.w800,
      color: kTeal,
      letterSpacing: 2,
    ),
  );
}

/// Section header
class SectionHeader extends StatelessWidget {
  final String? eyebrow, description;
  final String title;
  const SectionHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 8)],
        Text(
          title,
          style: spaceGrotesk(
            size: 24,
            weight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(description!, style: jakarta(size: 13, color: kMuted)),
        ],
      ],
    );
  }
}

/// Metric row — matches web MetricRow component
class MetricRow extends StatelessWidget {
  final List<({String label, String value})> items;
  const MetricRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: jakarta(size: 11, color: kMuted)),
                  const SizedBox(height: 2),
                  Text(
                    item.value,
                    style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Progress bar — matches web ProgressBar
class ProgressBar extends StatelessWidget {
  final double value; // 0-100
  final String tone;
  const ProgressBar({super.key, required this.value, this.tone = 'positive'});

  @override
  Widget build(BuildContext context) {
    final col = tone == 'positive'
        ? kTeal
        : tone == 'warning'
        ? kAmber
        : kRed;
    return Container(
      height: 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: Colors.white.withOpacity(0.06),
      ),
      child: FractionallySizedBox(
        widthFactor: (value / 100).clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(colors: [col.withOpacity(0.7), col]),
          ),
        ),
      ),
    );
  }
}

/// Page scaffold with safe-area and scrollable content
class PageFrame extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  const PageFrame({super.key, required this.children, this.title});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: children,
      ),
    );
  }
}

/// Top app-bar matching .topnav pill style
class TopNav extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? trailing;
  const TopNav({super.key, required this.title, this.trailing});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: kBgSoft.withOpacity(0.78),
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          // Brand dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [kTeal, Color(0x66_35F0D2)],
              ),
              boxShadow: [
                BoxShadow(color: kTeal.withOpacity(0.8), blurRadius: 12),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: spaceGrotesk(size: 16, weight: FontWeight.w700)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  DASHBOARD PAGE — mirrors DashboardPage.tsx
// ═══════════════════════════════════════════════════════════════════════════
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  double _elapsed = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() => _elapsed += 0.1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final leakage = _monthlyLeakage(state.expenses);
    final total = _monthlyTotal(state.expenses);
    final perSec = leakage / 30 / 24 / 3600;
    final goneSince = perSec * _elapsed;
    final saveRate = state.monthlySalary > 0
        ? ((state.monthlySalary - total) / state.monthlySalary * 100)
        : 0.0;
    final score = _healthScore(state);

    return PageFrame(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Text(
          'Good evening, ${state.userName} 👋',
          style: spaceGrotesk(
            size: 22,
            weight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your money leaks are being tracked.',
          style: jakarta(size: 13, color: kMuted),
        ),
        const SizedBox(height: 20),

        // ── Top Row: Bleed + 3 stats ─────────────────────────────────────────
        _buildBleedCard(perSec, goneSince, leakage),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _StatBox(
                label: 'Salary',
                value: _fmtINR(state.monthlySalary),
                color: kGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatBox(
                label: 'Spent',
                value: _fmtINR(total),
                color: kRed,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatBox(
                label: 'Saved',
                value: '${saveRate.toStringAsFixed(0)}%',
                color: kTeal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Health Score ─────────────────────────────────────────────────────
        _buildScoreCard(score),
        const SizedBox(height: 16),

        // ── Income vs Expenses Chart ─────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Income vs Expenses',
                style: spaceGrotesk(size: 15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '6 months · all figures monthly',
                style: jakarta(size: 12, color: kMuted),
              ),
              const SizedBox(height: 16),
              _RealLineChart(
                latestSalary: state.monthlySalary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Category breakdown ───────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where it goes',
                style: spaceGrotesk(size: 15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              ..._catRows(state.expenses),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Monthly breakdown bar ────────────────────────────────────────────
        GlassCard(child: _buildSpendSplit(state.expenses)),
        const SizedBox(height: 12),

        // ── Top leaks ────────────────────────────────────────────────────────
        GlassCard(child: _buildTopLeaks(state.expenses)),
        const SizedBox(height: 12),

        // ── Nudge strip ──────────────────────────────────────────────────────
        _buildNudge(state.expenses),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildBleedCard(double perSec, double goneSince, double monthly) {
    return GlassCard(
      borderColor: kRed.withOpacity(0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: kRed,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MONEY LEAKING RIGHT NOW',
                style: jakarta(
                  size: 10,
                  color: kMuted,
                  weight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _fmtINR(perSec),
                  style: spaceGrotesk(
                    size: 28,
                    weight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                TextSpan(
                  text: '/sec',
                  style: jakarta(size: 13, color: kMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_fmtINR(goneSince)} gone since you opened this page',
            style: jakarta(size: 12, color: kMuted),
          ),
          const Divider(color: Color(0x10FFFFFF), height: 24),
          Row(
            children: [
              _BleedMeta(
                label: 'Monthly leakage',
                value: _fmtINR(monthly),
                color: kText,
              ),
              const SizedBox(width: 24),
              _BleedMeta(
                label: '10-year cost',
                value: _fmtINR(monthly * 120),
                color: kAmber,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(int score) {
    final label = score >= 75
        ? 'Excellent'
        : score >= 50
        ? 'Good'
        : score >= 30
        ? 'Fair'
        : 'Poor';
    return GlassCard(
      child: Row(
        children: [
          // Ring
          SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: _ScoreRingPainter(score),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: spaceGrotesk(size: 20, weight: FontWeight.w700),
                    ),
                    Text(label, style: jakarta(size: 9, color: kMuted)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial Health Score',
                  style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on leakage, SIP habits & goals',
                  style: jakarta(size: 12, color: kMuted),
                ),
                const SizedBox(height: 8),
                ProgressBar(
                  value: score.toDouble(),
                  tone: score >= 60 ? 'positive' : 'warning',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _catRows(List<Expense> expenses) {
    final cats = <String, double>{};
    for (final e in expenses) {
      final cat = _catOf(e.name);
      cats[cat] = (cats[cat] ?? 0) + _monthlyEquiv(e.amount, e.frequency);
    }
    final total = cats.values.fold(0.0, (a, b) => a + b);
    return cats.entries.map((entry) {
      final col = _catColor(entry.key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: col,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Text(
                entry.key,
                style: jakarta(size: 12, color: kMutedStrong),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: total > 0 ? entry.value / total : 0,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation(col),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 48,
              child: Text(
                _fmtINR(entry.value),
                textAlign: TextAlign.right,
                style: spaceGrotesk(size: 12, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildSpendSplit(List<Expense> expenses) {
    double essential = 0, avoidable = 0, impulse = 0;
    for (final e in expenses) {
      final m = _monthlyEquiv(e.amount, e.frequency);
      if (e.tag == 'essential') {
        essential += m;
      } else if (e.tag == 'avoidable')
        avoidable += m;
      else
        impulse += m;
    }
    final total = essential + avoidable + impulse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly breakdown',
          style: spaceGrotesk(size: 15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (total > 0) ...[
                  Flexible(
                    flex: (essential / total * 100).round(),
                    child: ColoredBox(
                      color: kGreen,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Flexible(
                    flex: (avoidable / total * 100).round(),
                    child: ColoredBox(
                      color: kAmber,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Flexible(
                    flex: (impulse / total * 100).round(),
                    child: ColoredBox(
                      color: kRed,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          children: [
            _LegendDot(color: kGreen, label: 'Essential ${_fmtINR(essential)}'),
            _LegendDot(color: kAmber, label: 'Avoidable ${_fmtINR(avoidable)}'),
            _LegendDot(color: kRed, label: 'Impulse ${_fmtINR(impulse)}'),
          ],
        ),
      ],
    );
  }

  Widget _buildTopLeaks(List<Expense> expenses) {
    final leaks =
        expenses
            .where((e) => e.tag != 'essential')
            .map(
              (e) => (
                name: e.name,
                mo: _monthlyEquiv(e.amount, e.frequency),
                tag: e.tag,
              ),
            )
            .toList()
          ..sort((a, b) => b.mo.compareTo(a.mo));
    final top = leaks.take(5).toList();
    final max = top.isNotEmpty ? top.first.mo : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top leaks',
          style: spaceGrotesk(size: 15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Avoidable & impulse expenses ranked by cost',
          style: jakarta(size: 12, color: kMuted),
        ),
        const SizedBox(height: 12),
        ...top.asMap().entries.map((entry) {
          final i = entry.key;
          final l = entry.value;
          final col = l.tag == 'impulse'
              ? kRed
              : l.tag == 'avoidable'
              ? kAmber
              : kGreen;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white.withOpacity(0.05),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: jakarta(size: 11, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        style: jakarta(size: 13, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: l.mo / max,
                          backgroundColor: Colors.white.withOpacity(0.04),
                          valueColor: AlwaysStoppedAnimation(col),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _fmtINR(l.mo),
                        style: spaceGrotesk(size: 13, weight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '/mo',
                        style: jakarta(size: 10, color: kMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: kRed.withOpacity(0.05),
            border: Border.all(color: kRed.withOpacity(0.12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '10-year compounded cost',
                style: jakarta(size: 12, color: kMuted),
              ),
              Text(
                _fmtINR(_monthlyLeakage(expenses) * 120),
                style: spaceGrotesk(
                  size: 14,
                  weight: FontWeight.w700,
                  color: kRed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNudge(List<Expense> expenses) {
    final leaks =
        expenses
            .where((e) => e.tag != 'essential')
            .map(
              (e) => (name: e.name, mo: _monthlyEquiv(e.amount, e.frequency)),
            )
            .toList()
          ..sort((a, b) => b.mo.compareTo(a.mo));
    final topLeak = leaks.isNotEmpty ? leaks.first : null;
    final msg = topLeak != null
        ? 'Skip ${topLeak.name} → ${_fmtINR(_futureValue(topLeak.mo, 12, 60))} in 5 years'
        : 'Add expenses to get insights.';

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: jakarta(size: 13))),
          const SizedBox(width: 8),
          Text(
            'Simulate →',
            style: jakarta(size: 12, color: kTeal, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  int _healthScore(AppState state) {
    int score = 50;
    final leakage = _monthlyLeakage(state.expenses);
    if (state.monthlySalary > 0) {
      final ratio = leakage / state.monthlySalary;
      if (ratio < 0.1) {
        score += 25;
      } else if (ratio < 0.2)
        score += 15;
      else if (ratio < 0.3)
        score += 5;
      else
        score -= 10;
    }
    if (state.sipAmount >= 5000) score += 15;
    if (state.sipAmount >= 10000) score += 10;
    return score.clamp(0, 100);
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.025),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: jakarta(size: 9, color: kMuted, letterSpacing: 0.8),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: spaceGrotesk(
              size: 16,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BleedMeta extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BleedMeta({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: jakarta(size: 10, color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text(
        value,
        style: spaceGrotesk(size: 14, weight: FontWeight.w700, color: color),
      ),
    ],
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 5),
      Text(label, style: jakarta(size: 11, color: kMuted)),
    ],
  );
}

class _ScoreRingPainter extends CustomPainter {
  final int score;
  const _ScoreRingPainter(this.score);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final sweep = 2 * math.pi * score / 100;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    // Arc
    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: [kTeal, kGreen, kBlue, kTeal],
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) => old.score != score;
}

// ──── Mini line chart (6 months) ────────────────────────────────────────────
class _RealLineChart extends StatelessWidget {
  final double latestSalary;
  const _RealLineChart({required this.latestSalary});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MonthlySnapshot>>(
      future: MonthlySnapshotService.getLast6Months(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: kTeal)),
          );
        }

        var snapshots = snapshot.data!;
        
        // If we don't have enough data, fallback gracefully or pad
        if (snapshots.isEmpty) {
          return SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _TwoLinePainter(
                income: [latestSalary, latestSalary],
                spend: [0.0, 0.0],
                max: latestSalary > 0 ? latestSalary : 1000,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [Text('No Data', style: jakarta(size: 10, color: kMuted))],
                  ),
                ),
              ),
            ),
          );
        }

        // Map data
        final months = snapshots.map((s) {
          final parts = s.month.split('-');
          if (parts.length == 2) {
            final m = int.tryParse(parts[1]) ?? 1;
            const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            return monthNames[m - 1];
          }
          return s.month;
        }).toList();

        final incomeData = snapshots.map((s) => s.salary).toList();
        final spendData = snapshots.map((s) => s.essential + s.avoidable + s.impulse).toList();
        
        // Single point graphs need 2 points visually for CustomPaint
        if (incomeData.length == 1) {
          months.insert(0, '');
          incomeData.insert(0, incomeData.first);
          spendData.insert(0, spendData.first);
        }

        final maxIncome = incomeData.reduce(math.max);
        final maxSpend = spendData.reduce(math.max);
        final maxVal = math.max(maxIncome, maxSpend);

        return SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _TwoLinePainter(
              income: incomeData,
              spend: spendData,
              max: maxVal == 0 ? 1 : maxVal,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: months
                      .map((m) => Text(m, style: jakarta(size: 10, color: kMuted)))
                      .toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TwoLinePainter extends CustomPainter {
  final List<double> income, spend;
  final double max;
  const _TwoLinePainter({
    required this.income,
    required this.spend,
    required this.max,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - 20;
    void drawLine(List<double> data, Color color) {
      final path = Path();
      for (int i = 0; i < data.length; i++) {
        final x = size.width * i / (data.length - 1);
        final y = h - (data[i] / max * h * 0.85);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    drawLine(income, kGreen);
    drawLine(spend, kRed);
  }

  @override
  bool shouldRepaint(_) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
//  EXPENSES PAGE — mirrors ExpensesPage.tsx
// ═══════════════════════════════════════════════════════════════════════════
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final _nameCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  String _freq = 'monthly';
  String _tag = 'avoidable';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  void _add(AppState state) {
    if (_nameCtrl.text.isEmpty || _amtCtrl.text.isEmpty) return;
    state.addExpense(
      Expense(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameCtrl.text.trim(),
        amount: double.tryParse(_amtCtrl.text) ?? 0,
        frequency: _freq,
        tag: _tag,
      ),
    );
    _nameCtrl.clear();
    _amtCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final totals = _calcTotals(state.expenses);

    return PageFrame(
      children: [
        const Pill(label: 'Expenses', tone: 'warning'),
        const SizedBox(height: 10),
        Text(
          'Tag every recurring cost once\nand let the app do the rest.',
          style: spaceGrotesk(
            size: 22,
            weight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 20),

        // ── Add form ──────────────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add expense',
                    style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                  ),
                  const Pill(label: 'Quick entry', tone: 'teal'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: jakarta(size: 13),
                      decoration: const InputDecoration(
                        hintText: 'Expense name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: TextInputType.number,
                      style: jakarta(size: 13),
                      decoration: const InputDecoration(hintText: 'Amount'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DropField(
                      value: _freq,
                      onChanged: (v) => setState(() => _freq = v!),
                      items: const ['daily', 'weekly', 'monthly'],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DropField(
                      value: _tag,
                      onChanged: (v) => setState(() => _tag = v!),
                      items: const ['essential', 'avoidable', 'impulse'],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: _PrimaryButton(
                  label: 'Add expense →',
                  onTap: () => _add(state),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Burn rate chips ──────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Burn rate',
                style: spaceGrotesk(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              MetricRow(
                items: [
                  (label: 'Per day', value: _fmtINR(totals['leakage']! / 30)),
                  (
                    label: 'Per hour',
                    value: _fmtINR(totals['leakage']! / 30 / 24),
                  ),
                  (
                    label: 'Per minute',
                    value: _fmtINR(totals['leakage']! / 30 / 24 / 60),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Expense list ─────────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Expense list',
                    style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                  ),
                  const Pill(label: 'Tap tag to cycle', tone: 'teal'),
                ],
              ),
              const SizedBox(height: 12),
              ...state.expenses.map(
                (e) => _ExpenseRow(
                  expense: e,
                  onToggle: () => state.toggleExpenseTag(e.id),
                  onDelete: () => state.removeExpense(e.id),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, double> _calcTotals(List<Expense> expenses) {
    double essential = 0, avoidable = 0, impulse = 0;
    for (final e in expenses) {
      final m = _monthlyEquiv(e.amount, e.frequency);
      if (e.tag == 'essential') {
        essential += m;
      } else if (e.tag == 'avoidable')
        avoidable += m;
      else
        impulse += m;
    }
    return {
      'essential': essential,
      'avoidable': avoidable,
      'impulse': impulse,
      'leakage': avoidable + impulse,
    };
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback onToggle, onDelete;
  const _ExpenseRow({
    required this.expense,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final col = expense.tag == 'essential'
        ? kGreen
        : expense.tag == 'avoidable'
        ? kAmber
        : kRed;
    final monthly = _monthlyEquiv(expense.amount, expense.frequency);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.name,
                  style: jakarta(size: 13, weight: FontWeight.w600),
                ),
                Text(
                  '${_fmtINR(monthly)}/mo · 10y: ${_fmtINR(monthly * 120)}',
                  style: jakarta(size: 11, color: kMuted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: col.withOpacity(0.10),
                border: Border.all(color: col.withOpacity(0.25)),
              ),
              child: Text(
                expense.tag,
                style: jakarta(size: 10, color: col, weight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: kRed.withOpacity(0.08),
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: kRed),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SIMULATOR PAGE — mirrors SimulatorPage.tsx
// ═══════════════════════════════════════════════════════════════════════════
class SimulatorPage extends StatefulWidget {
  const SimulatorPage({super.key});
  @override
  State<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends State<SimulatorPage> {
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);

    final now = _futureValue(state.sipAmount, state.sipReturn, state.sipMonths);
    final later = _futureValue(
      state.sipAmount,
      state.sipReturn,
      state.sipMonths - 6,
    );
    final lost = now - later;

    return PageFrame(
      children: [
        const Pill(label: 'Simulator', tone: 'positive'),
        const SizedBox(height: 10),
        Text(
          'Compare start today vs waiting,\nthen redirect leaks into SIPs.',
          style: spaceGrotesk(
            size: 22,
            weight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "The corpus drops hard when you delay. That's the whole pitch.",
          style: jakarta(size: 13, color: kMuted),
        ),
        const SizedBox(height: 20),

        // ── SIP sliders ───────────────────────────────────────────────────────
        GlassCard(
          child: Column(
            children: [
              _SliderRow(
                label: 'Monthly SIP',
                value: _fmtINR(state.sipAmount),
                slider: Slider(
                  value: state.sipAmount,
                  min: 1000,
                  max: 50000,
                  divisions: 98,
                  onChanged: (v) => state.setSip(amount: v),
                ),
              ),
              const SizedBox(height: 6),
              _SliderRow(
                label: 'Annual return',
                value: '${state.sipReturn.toStringAsFixed(1)}%',
                slider: Theme(
                  data: Theme.of(context).copyWith(
                    sliderTheme: SliderThemeData(
                      activeTrackColor: kBlue,
                      thumbColor: kBlue,
                    ),
                  ),
                  child: Slider(
                    value: state.sipReturn,
                    min: 6,
                    max: 18,
                    divisions: 24,
                    onChanged: (v) => state.setSip(ret: v),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _SliderRow(
                label: 'Duration',
                value: '${(state.sipMonths / 12).round()} years',
                slider: Slider(
                  value: state.sipMonths.toDouble(),
                  min: 12,
                  max: 240,
                  divisions: 19,
                  onChanged: (v) => state.setSip(months: v.round()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Comparison cards ─────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Start today vs later',
                    style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                  ),
                  const Pill(label: 'Compounding gap', tone: 'warning'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CompareBox(
                      label: 'Start now',
                      value: _fmtINR(now),
                      color: kTeal,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CompareBox(
                      label: 'Start 6 months later',
                      value: _fmtINR(later),
                      color: kAmber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: kRed.withOpacity(0.06),
                  border: Border.all(color: kRed.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.alarm_rounded, color: kRed, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lost by waiting 6 months',
                            style: jakarta(size: 11, color: kMuted),
                          ),
                          Text(
                            _fmtINR(lost),
                            style: spaceGrotesk(
                              size: 22,
                              weight: FontWeight.w700,
                              color: kRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Chart
              Text(
                'Corpus growth projection',
                style: jakarta(size: 12, color: kMuted),
              ),
              const SizedBox(height: 10),
              _SipChart(
                sip: state.sipAmount,
                rate: state.sipReturn,
                months: state.sipMonths,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Redirect leak ─────────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Redirect a leak',
                style: spaceGrotesk(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Every avoidable expense can be redirected into your SIP.',
                style: jakarta(size: 12, color: kMuted),
              ),
              const SizedBox(height: 14),
              ...state.expenses.where((e) => e.tag != 'essential').take(4).map((
                e,
              ) {
                final m = _monthlyEquiv(e.amount, e.frequency);
                final bonus = _futureValue(m, state.sipReturn, state.sipMonths);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: kTeal.withOpacity(0.03),
                    border: Border.all(color: kTeal.withOpacity(0.10)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        e.name,
                        style: jakarta(size: 13, weight: FontWeight.w600),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '→ +${_fmtINR(bonus)}',
                              style: spaceGrotesk(
                                size: 12,
                                weight: FontWeight.w700,
                                color: kTeal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label, value;
  final Widget slider;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: jakarta(size: 12, color: kMuted)),
          Text(
            value,
            style: spaceGrotesk(
              size: 13,
              weight: FontWeight.w700,
              color: kTeal,
            ),
          ),
        ],
      ),
      slider,
    ],
  );
}

class _CompareBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _CompareBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: color.withOpacity(0.04),
      border: Border.all(color: color.withOpacity(0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: jakarta(size: 11, color: kMuted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: spaceGrotesk(size: 17, weight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}

class _SipChart extends StatelessWidget {
  final double sip, rate;
  final int months;
  const _SipChart({
    required this.sip,
    required this.rate,
    required this.months,
  });

  @override
  Widget build(BuildContext context) {
    final points = List.generate(months, (i) {
      return _futureValue(sip, rate, i + 1);
    });
    final max = points.isNotEmpty ? points.last : 1.0;

    return SizedBox(
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(math.min(20, months), (i) {
          final idx = (i / 19 * (months - 1)).round();
          final val = points[idx] / max;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                height: 90 * val + 4,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [kTeal.withOpacity(0.5), kTeal],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  GOALS PAGE — mirrors GoalsPage.tsx
// ═══════════════════════════════════════════════════════════════════════════
class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});
  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  bool _showForm = false;

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);

    return PageFrame(
      children: [
        const Pill(label: 'Goals', tone: 'teal'),
        const SizedBox(height: 10),
        Text(
          'Turn target dates\ninto a monthly number.',
          style: spaceGrotesk(
            size: 22,
            weight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Each goal shows progress, required monthly saving, and invest vs save comparison.',
          style: jakarta(size: 13, color: kMuted),
        ),
        const SizedBox(height: 20),

        // ── Goal cards ──────────────────────────────────────────────────────
        ...state.goals.map((g) {
          final pct = g.targetAmount > 0 ? g.savedAmount / g.targetAmount : 0.0;
          final needed = _monthlySavingsRequired(
            g.targetAmount,
            g.savedAmount,
            g.targetDate,
          );
          final investResult = _futureValue(needed, 12, 24);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              borderColor: g.priority == 1 ? kAmber.withOpacity(0.18) : kBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          g.name,
                          style: spaceGrotesk(
                            size: 15,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Pill(
                        label: 'P${g.priority}',
                        tone: g.priority == 1 ? 'warning' : 'positive',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ProgressBar(
                    value: pct * 100,
                    tone: pct >= 0.5 ? 'positive' : 'warning',
                  ),
                  const SizedBox(height: 10),
                  MetricRow(
                    items: [
                      (label: 'Saved', value: _fmtINR(g.savedAmount)),
                      (label: 'Target', value: _fmtINR(g.targetAmount)),
                      (label: 'Need/mo', value: _fmtINR(needed)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: kBlue.withOpacity(0.04),
                      border: Border.all(color: kBlue.withOpacity(0.10)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Invest same amount → 2-year corpus',
                          style: jakarta(size: 11, color: kMuted),
                        ),
                        Text(
                          _fmtINR(investResult),
                          style: spaceGrotesk(
                            size: 13,
                            weight: FontWeight.w700,
                            color: kBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        // ── Suggested cuts ──────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suggested cuts',
                style: spaceGrotesk(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              ...[
                'Trim one delivery habit',
                'Remove duplicate subscriptions',
                'Redirect one impulse purchase',
              ].map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: kTeal,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(s, style: jakarta(size: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Add goal form (collapsible) ──────────────────────────────────────
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _showForm = !_showForm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kTeal.withOpacity(0.2)),
              color: kTeal.withOpacity(0.04),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _showForm ? Icons.expand_less : Icons.add_rounded,
                  color: kTeal,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _showForm ? 'Cancel' : 'Add new goal',
                  style: jakarta(
                    size: 13,
                    weight: FontWeight.w700,
                    color: kTeal,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showForm) ...[
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New goal',
                  style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  style: jakarta(size: 13),
                  decoration: const InputDecoration(hintText: 'Goal name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _targetCtrl,
                  keyboardType: TextInputType.number,
                  style: jakarta(size: 13),
                  decoration: const InputDecoration(hintText: 'Target amount'),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: _PrimaryButton(
                    label: 'Add goal',
                    onTap: () {
                      if (_nameCtrl.text.isEmpty || _targetCtrl.text.isEmpty)
                        return;
                      state.addGoal(
                        Goal(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: _nameCtrl.text.trim(),
                          targetAmount: double.tryParse(_targetCtrl.text) ?? 0,
                          targetDate: DateTime.now()
                              .add(const Duration(days: 365))
                              .toString()
                              .split(' ')[0],
                          priority: 2,
                          savedAmount: 0,
                        ),
                      );
                      setState(() => _showForm = false);
                      _nameCtrl.clear();
                      _targetCtrl.clear();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  double _monthlySavingsRequired(double target, double saved, String date) {
    try {
      final d = DateTime.parse(date);
      final months = d.difference(DateTime.now()).inDays / 30;
      if (months <= 0) return (target - saved);
      return (target - saved) / months;
    } catch (_) {
      return (target - saved) / 24;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  INSIGHTS PAGE — mirrors InsightsPage.tsx
// ═══════════════════════════════════════════════════════════════════════════
class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final leakage = _monthlyLeakage(state.expenses);
    final personality = _detectPersonality(
      leakage,
      state.monthlySalary,
      state.sipAmount,
    );

    final badges = [
      (
        name: 'Leak Finder',
        hint: 'Tagged 3 expenses correctly',
        unlocked: true,
      ),
      (name: 'SIP Starter', hint: 'Started a monthly SIP', unlocked: true),
      (
        name: 'No-Spend Week',
        hint: '7 days under avoidable spend',
        unlocked: false,
      ),
      (name: 'Goal Climber', hint: 'Kept 2 goals on track', unlocked: false),
    ];

    final recs = [
      (label: 'Cut Swiggy twice a week', saving: 3500.0),
      (label: 'Drop one OTT subscription', saving: 1299.0),
      (label: 'Move cloud to shared plan', saving: 299.0),
    ];

    return PageFrame(
      children: [
        const Pill(label: 'Insights', tone: 'teal'),
        const SizedBox(height: 10),
        Text(
          'Package habits into a personality,\nthen show the rupee consequence.',
          style: spaceGrotesk(
            size: 22,
            weight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 20),

        // ── Personality card ─────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Spending personality',
                    style: spaceGrotesk(size: 14, weight: FontWeight.w700),
                  ),
                  Pill(label: personality, tone: 'warning'),
                ],
              ),
              const SizedBox(height: 14),
              MetricRow(
                items: [
                  (
                    label: 'Savings streak',
                    value: '${_calculateSavingsStreak(state)} days',
                  ),
                  (label: 'Challenge', value: 'No-spend week'),
                  (
                    label: 'Saved so far',
                    value: _fmtINR(_calculateTotalSaved(state)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Stat metrics ─────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _InsightTile(
                label: '₹ saved from leaks',
                value: _fmtINR(leakage * 8),
                note: 'annualized',
                color: kTeal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InsightTile(
                label: '10-year corpus',
                value: _fmtINR(_futureValue(state.sipAmount, 12, 120)),
                note: 'from SIP',
                color: kBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InsightTile(
                label: 'Health score',
                value: _healthScoreLabel(state),
                note: personality,
                color: kGreen,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InsightTile(
                label: 'Avoidable share',
                value: state.monthlySalary > 0
                    ? '${(leakage / state.monthlySalary * 100).toStringAsFixed(0)}%'
                    : '0%',
                note: 'of monthly outflow',
                color: kAmber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Recommendations ──────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recommendations',
                style: spaceGrotesk(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...recs.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          r.label,
                          style: jakarta(size: 13, weight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: kTeal.withOpacity(0.08),
                          border: Border.all(color: kTeal.withOpacity(0.15)),
                        ),
                        child: Text(
                          _fmtINR(r.saving),
                          style: jakarta(
                            size: 11,
                            color: kTeal,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Badges wall ──────────────────────────────────────────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Badges wall',
                style: spaceGrotesk(size: 14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...badges.map(
                (b) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: b.unlocked
                        ? kTeal.withOpacity(0.06)
                        : Colors.white.withOpacity(0.02),
                    border: Border.all(
                      color: b.unlocked
                          ? kTeal.withOpacity(0.24)
                          : Colors.white.withOpacity(0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        b.unlocked
                            ? Icons.check_circle_rounded
                            : Icons.lock_rounded,
                        color: b.unlocked ? kTeal : kMuted,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.name,
                              style: jakarta(
                                size: 13,
                                weight: FontWeight.w700,
                                color: b.unlocked ? kText : kMuted,
                              ),
                            ),
                            Text(
                              b.hint,
                              style: jakarta(size: 11, color: kMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _detectPersonality(double leakage, double salary, double sip) {
    if (sip == 0) return 'SIP Neglector';
    if (salary > 0 && leakage / salary > 0.30) return 'Impulse Spender';
    return 'Disciplined Saver';
  }

  String _healthScoreLabel(AppState state) {
    final leakage = _monthlyLeakage(state.expenses);
    int score = 50;
    if (state.monthlySalary > 0) {
      final r = leakage / state.monthlySalary;
      if (r < 0.1) {
        score += 25;
      } else if (r < 0.2)
        score += 15;
      else if (r < 0.3)
        score += 5;
      else
        score -= 10;
    }
    if (state.sipAmount >= 5000) score += 15;
    if (state.sipAmount >= 10000) score += 10;
    return '$score / 100';
  }

  int _calculateSavingsStreak(AppState state) {
    // Placeholder: in real app would count consecutive skip days from ResponseTracker
    // For now, estimate based on SIP engagement
    return state.sipAmount > 0
        ? math.max(8, (state.sipAmount / 2000).toInt())
        : 0;
  }

  double _calculateTotalSaved(AppState state) {
    // Placeholder: sum of all skipped nudge decisions × avg spend
    // Would normally come from ResponseTracker.totalSaved()
    return _monthlyLeakage(state.expenses) *
        0.4; // Assume 40% saved through nudges
  }
}

class _InsightTile extends StatelessWidget {
  final String label, value, note;
  final Color color;
  const _InsightTile({
    required this.label,
    required this.value,
    required this.note,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      color: Colors.white.withOpacity(0.02),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: jakarta(size: 11, color: kMuted)),
        const SizedBox(height: 6),
        Text(
          value,
          style: spaceGrotesk(size: 18, weight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 2),
        Text(note, style: jakarta(size: 10, color: kMuted)),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  SHARED FORM WIDGETS
// ═══════════════════════════════════════════════════════════════════════════
class _DropField extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _DropField({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: kPanel,
        border: Border.all(color: kBorder),
      ),
      child: DropdownButton<String>(
        value: value,
        onChanged: onChanged,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: kPanelStrong,
        style: jakarta(size: 13),
        items: items
            .map(
              (i) => DropdownMenuItem(
                value: i,
                child: Text(i, style: jakarta(size: 13)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          gradient: const LinearGradient(colors: [kTeal, kGreen]),
          boxShadow: [
            BoxShadow(color: kTeal.withOpacity(0.22), blurRadius: 24),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: jakarta(
            size: 14,
            weight: FontWeight.w700,
            color: const Color(0xFF061015),
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
String _catOf(String name) {
  final n = name.toLowerCase();
  if (n.contains('swiggy') || n.contains('zomato') || n.contains('cafe'))
    return 'Food & Delivery';
  if (n.contains('netflix') ||
      n.contains('ott') ||
      n.contains('prime') ||
      n.contains('spotify'))
    return 'Subscriptions';
  if (n.contains('metro') || n.contains('uber') || n.contains('ola'))
    return 'Transport';
  if (n.contains('cloud') || n.contains('digital')) return 'Digital & Cloud';
  if (n.contains('gym') || n.contains('health')) return 'Fitness & Health';
  return 'Other';
}

Color _catColor(String cat) {
  switch (cat) {
    case 'Food & Delivery':
      return kRed;
    case 'Subscriptions':
      return kAmber;
    case 'Transport':
      return kBlue;
    case 'Digital & Cloud':
      return const Color(0xFFA78BFA);
    case 'Fitness & Health':
      return kGreen;
    default:
      return kMuted;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  PERMISSION ONBOARDING SHEET
// ═══════════════════════════════════════════════════════════════════════════
class _PermissionSheet extends StatelessWidget {
  final bool hasUsage;
  final bool hasOverlay;
  final VoidCallback onGranted;
  const _PermissionSheet({
    required this.hasUsage,
    required this.hasOverlay,
    required this.onGranted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
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

          // Title
          Text(
            'Enable Behavior Monitor',
            style: spaceGrotesk(size: 20, weight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Expense Autopsy needs two permissions to watch for spending traps in real time.',
            style: jakarta(size: 13, color: kMuted),
          ),
          const SizedBox(height: 24),

          // Permission 1
          _PermRow(
            icon: Icons.bar_chart_rounded,
            title: 'Usage Access',
            desc: 'Detect which app is open',
            granted: hasUsage,
            onTap: () async {
              await MonitorService.requestUsagePermission();
              Navigator.pop(context);
              await Future.delayed(const Duration(seconds: 1));
              onGranted();
            },
          ),
          const SizedBox(height: 12),

          // Permission 2
          _PermRow(
            icon: Icons.layers_rounded,
            title: 'Display over apps',
            desc: 'Show nudge overlay when needed',
            granted: hasOverlay,
            onTap: () async {
              await MonitorService.requestOverlayPermission();
              Navigator.pop(context);
              await Future.delayed(const Duration(seconds: 1));
              onGranted();
            },
          ),
          const SizedBox(height: 24),

          // CTA
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () async {
                if (!hasUsage) await MonitorService.requestUsagePermission();
                if (!hasOverlay)
                  await MonitorService.requestOverlayPermission();
                if (context.mounted) Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [kTeal, kGreen]),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Grant permissions →',
                  style: jakarta(
                    size: 15,
                    weight: FontWeight.w700,
                    color: const Color(0xFF061015),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Text(
                'Skip for now',
                style: jakarta(size: 13, color: kMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  final bool granted;
  final VoidCallback onTap;
  const _PermRow({
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: granted ? null : onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: granted ? kGreen.withOpacity(0.06) : kPanel,
        border: Border.all(color: granted ? kGreen.withOpacity(0.2) : kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (granted ? kGreen : kTeal).withOpacity(0.12),
            ),
            child: Icon(icon, size: 18, color: granted ? kGreen : kTeal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: jakarta(size: 13, weight: FontWeight.w700)),
                Text(desc, style: jakarta(size: 11, color: kMuted)),
              ],
            ),
          ),
          Icon(
            granted
                ? Icons.check_circle_rounded
                : Icons.arrow_forward_ios_rounded,
            size: granted ? 20 : 14,
            color: granted ? kGreen : kMuted,
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  EDIT PROFILE SHEET — saves to MongoDB via AppState.updateProfile()
// ═══════════════════════════════════════════════════════════════════════════

class _EditProfileSheet extends StatefulWidget {
  final AppState state;
  const _EditProfileSheet({required this.state});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey    = GlobalKey<FormState>();
  bool  _saving     = false;
  bool  _saved      = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _occupationCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _sipAmtCtrl;
  late final TextEditingController _sipRetCtrl;
  late final TextEditingController _sipMosCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _nameCtrl       = TextEditingController(text: s.userName);
    _occupationCtrl = TextEditingController(text: s.userOccupation);
    _cityCtrl       = TextEditingController(text: s.userCity);
    _salaryCtrl     = TextEditingController(text: s.monthlySalary.toStringAsFixed(0));
    _sipAmtCtrl     = TextEditingController(text: s.sipAmount.toStringAsFixed(0));
    _sipRetCtrl     = TextEditingController(text: s.sipReturn.toStringAsFixed(1));
    _sipMosCtrl     = TextEditingController(text: (s.sipMonths ~/ 12).toString());
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _occupationCtrl, _cityCtrl, _salaryCtrl, _sipAmtCtrl, _sipRetCtrl, _sipMosCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final salary = double.tryParse(_salaryCtrl.text.replaceAll(',', '')) ?? 0;
    final sip    = double.tryParse(_sipAmtCtrl.text.replaceAll(',', '')) ?? 0;
    final ret    = double.tryParse(_sipRetCtrl.text) ?? 12;
    final yrs    = int.tryParse(_sipMosCtrl.text) ?? 10;

    final ok = await widget.state.updateProfile(
      name:       _nameCtrl.text.trim(),
      salary:     salary,
      sip:        sip,
      ret:        ret,
      months:     yrs * 12,
      occupation: _occupationCtrl.text.trim(),
      city:       _cityCtrl.text.trim(),
    );

    if (mounted) {
      setState(() { _saving = false; _saved = ok; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? '✅ Profile saved!' : '❌ Save failed – check your connection'),
        backgroundColor: ok ? kGreen : kRed,
      ));
      if (ok) Navigator.of(context).pop();
    }
  }

  Widget _field(String label, TextEditingController ctrl, {
    TextInputType kbd = TextInputType.text,
    String? Function(String?)? validator,
    String hint = '',
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: jakarta(size: 11, color: kMuted, weight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl,
        keyboardType: kbd,
        validator: validator ?? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        style: jakarta(size: 14, weight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: jakarta(size: 13, color: kMuted),
          filled: true,
          fillColor: kBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kTeal, width: 1.5),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Handle
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 20),

              // Avatar + heading
              Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [kTeal, kGreen]),
                  ),
                  child: Center(
                    child: Text(
                      widget.state.userName.isNotEmpty ? widget.state.userName[0].toUpperCase() : 'U',
                      style: spaceGrotesk(size: 22, weight: FontWeight.w700, color: Color(0xFF050816)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Edit Profile', style: spaceGrotesk(size: 18, weight: FontWeight.w700)),
                  Text(widget.state.userEmail, style: jakarta(size: 12, color: kMuted)),
                ]),
              ]),
              const SizedBox(height: 24),

              // ── Personal Info ──────────────────────────────────────────────
              Text('Personal', style: jakarta(size: 11, color: kTeal, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              _field('Full Name', _nameCtrl, hint: 'e.g. Vikas Sharma'),
              const SizedBox(height: 12),
              _field('Occupation', _occupationCtrl, hint: 'e.g. Software Engineer',
                  validator: (_) => null),
              const SizedBox(height: 12),
              _field('City', _cityCtrl, hint: 'e.g. Mumbai',
                  validator: (_) => null),
              const SizedBox(height: 20),

              // ── Financial ─────────────────────────────────────────────────
              Text('Financial', style: jakarta(size: 11, color: kTeal, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              _field('Monthly Salary (₹)', _salaryCtrl,
                  kbd: TextInputType.number, hint: '95000',
                  validator: (v) => (double.tryParse(v?.replaceAll(',', '') ?? '') == null) ? 'Enter valid amount' : null),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field('SIP Amount (₹)', _sipAmtCtrl,
                    kbd: TextInputType.number, hint: '15000',
                    validator: (v) => (double.tryParse(v?.replaceAll(',', '') ?? '') == null) ? 'Invalid' : null)),
                const SizedBox(width: 12),
                Expanded(child: _field('Return (%/yr)', _sipRetCtrl,
                    kbd: TextInputType.number, hint: '12.0',
                    validator: (v) => (double.tryParse(v ?? '') == null) ? 'Invalid' : null)),
              ]),
              const SizedBox(height: 12),
              _field('SIP Duration (years)', _sipMosCtrl,
                  kbd: TextInputType.number, hint: '15',
                  validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter whole years' : null),
              const SizedBox(height: 28),

              // ── Save button ────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(colors: [kTeal, kGreen]),
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Save to Cloud ☁️',
                              style: jakarta(size: 15, weight: FontWeight.w700, color: Color(0xFF050816))),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
