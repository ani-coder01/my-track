# 💸 Expense Autopsy

> An intelligent personal finance app that **intercepts impulsive spending in real time** using Android system-level monitoring, SMS transaction parsing, behavioral nudges, and a MongoDB-backed financial dashboard.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Tech Stack](#tech-stack)
4. [Project Structure](#project-structure)
5. [Feature Documentation](#feature-documentation)
   - [Real-Time App Monitoring (Background Service)](#1-real-time-app-monitoring)
   - [Behavioral Nudge Engine](#2-behavioral-nudge-engine)
   - [Nudge Screen](#3-nudge-screen)
   - [Expense Capture — Post-Nudge Logging](#4-expense-capture--post-nudge-logging)
   - [SMS Transaction Parser](#5-sms-transaction-parser)
   - [SMS Monitor Service](#6-sms-monitor-service)
   - [SMS Review Sheet](#7-sms-review-sheet)
   - [Dashboard Page](#8-dashboard-page)
   - [Expenses Page](#9-expenses-page)
   - [Goals Page](#10-goals-page)
   - [Simulator (SIP Calculator)](#11-simulator-sip-calculator)
   - [Insights Page](#12-insights-page)
   - [Profile Edit Feature](#13-profile-edit-feature)
   - [Monthly Snapshot Service](#14-monthly-snapshot-service)
   - [Response Tracker](#15-response-tracker)
   - [MongoDB Database Service](#16-mongodb-database-service)
   - [App State Management](#17-app-state-management)
6. [Database Schema](#database-schema)
7. [Android Native Layer](#android-native-layer)
8. [Permissions Required](#permissions-required)
9. [Setup & Running](#setup--running)
10. [Seeding the Database](#seeding-the-database)
11. [Design System](#design-system)

---

## Overview

**Expense Autopsy** is a Flutter-based Android application that works as a behavioral-change tool for personal finance. Rather than just recording past expenses, it actively **intervenes at the moment of spending** — before a user can open a food delivery or shopping app — showing them the real long-term cost of that action.

The core loop is:

```
User opens Zomato/Swiggy/Amazon etc.
       ↓
Android UsageStats background service detects it within 1.5 seconds
       ↓
Risk Score computed (0–100) based on time, budget state, habit frequency
       ↓
Nudge Screen overlays the phone (if score ≥ 50)
       ↓
User skips or proceeds  →  logs expense to MongoDB  →  dashboard updates
```

Additionally, when a bank SMS arrives, it automatically parses the transaction and asks the user to classify it in a review sheet — keeping records 100% complete without manual entry.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter (Dart)                       │
│                                                          │
│  AppState (ChangeNotifier + InheritedNotifier)           │
│  ├── DashboardPage  ── _RealLineChart (MongoDB)          │
│  ├── ExpensesPage   ── add / remove / tag expenses       │
│  ├── GoalsPage      ── financial goal tracker            │
│  ├── SimulatorPage  ── SIP compound-interest calculator  │
│  └── InsightsPage   ── skip streaks / savings summary    │
│                                                          │
│  Services Layer                                          │
│  ├── DbService          ← → MongoDB Atlas                │
│  ├── BehaviorEngine     ← risk scorer                    │
│  ├── MonitorService     ← → Android via MethodChannel    │
│  ├── SmsMonitor         ← Android SMS (telephony pkg)    │
│  ├── SmsParser          ← regex transaction extractor    │
│  ├── ResponseTracker    ← SharedPreferences log          │
│  └── MonthlySnapshotService ← MongoDB + SharedPrefs      │
│                                                          │
│  Screens                                                 │
│  ├── NudgeScreen        ← app intercept overlay          │
│  └── SmsReviewSheet     ← SMS capture bottom sheet       │
└─────────────────────────────────────────────────────────┘
             │  MethodChannel + EventChannel
             ↓
┌─────────────────────────────────────────────────────────┐
│               Android Native (Kotlin)                    │
│  ├── AppMonitorService.kt  ← foreground service          │
│  │    polls UsageStatsManager every 1.5s                 │
│  ├── MonitorPlugin.kt      ← channel registrar           │
│  └── MainActivity.kt       ← entry point                 │
└─────────────────────────────────────────────────────────┘
             │
             ↓
┌────────────────────────┐
│  MongoDB Atlas          │
│  ├── users              │
│  ├── expenses           │
│  ├── goals              │
│  ├── monthly_snapshots  │
│  └── behavior_events    │
└────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI & Logic | Flutter 3.x (Dart) |
| State management | `ChangeNotifier` + `InheritedNotifier` |
| Database | MongoDB Atlas (`mongo_dart ^0.10.2`) |
| SMS | `telephony ^0.2.0` |
| Permissions | `permission_handler ^11.0.0` |
| Local cache | `shared_preferences ^2.2.3` |
| Notifications | `flutter_local_notifications ^17.0.0` |
| Fonts | `google_fonts` (Space Grotesk + Plus Jakarta Sans) |
| Android native | Kotlin (foreground service + UsageStatsManager) |
| Seeding | Node.js + `mongodb` npm package |

---

## Project Structure

```
expense_autopsy/
├── lib/
│   ├── main.dart                   # App entry, models, AppState, all page widgets
│   ├── screens/
│   │   ├── nudge_screen.dart       # Intercept overlay screen
│   │   └── sms_review_sheet.dart   # SMS capture bottom sheet
│   └── services/
│       ├── behavior_engine.dart    # Risk scorer + savings projections
│       ├── db_service.dart         # MongoDB CRUD operations
│       ├── monitor_service.dart    # Flutter ↔ Android channel bridge
│       ├── monthly_snapshot_service.dart  # Monthly aggregates
│       ├── response_tracker.dart   # Nudge event persistence
│       ├── sms_monitor.dart        # Real-time SMS listener
│       ├── sms_parser.dart         # Regex-based transaction extractor
│       └── watched_apps_registry.dart  # Consolidated app list
├── android/
│   └── app/src/main/kotlin/com/example/expense_autopsy/
│       ├── AppMonitorService.kt    # Foreground UsageStats service
│       ├── MonitorPlugin.kt        # MethodChannel + EventChannel
│       └── MainActivity.kt
├── seed_mongo.js                   # One-time database seeder (Node.js)
└── pubspec.yaml
```

---

## Feature Documentation

---

### 1. Real-Time App Monitoring

**Files:** `AppMonitorService.kt`, `MonitorPlugin.kt`, `lib/services/monitor_service.dart`

#### How it works

The Android `AppMonitorService` is a **foreground service** that uses `UsageStatsManager` to poll the currently active app every **1.5 seconds**. When a watched app is detected for the first time (to avoid re-triggering on the same session), it fires an event through an `EventChannel` to the Flutter layer.

#### `AppMonitorService.kt` — key functions

| Function | Description |
|---|---|
| `onStartCommand()` | Starts the foreground service with a persistent notification. Sets `running = true` and begins the polling loop via `Handler.post(pollingRunnable)`. |
| `pollingRunnable` | A `Runnable` that calls `checkForegroundApp()` every 1,500ms as long as the service is running. |
| `checkForegroundApp()` | Queries `UsageStatsManager` for the most recently used app. If it is in `WATCHED_APPS` and different from `lastApp`, sends `{package, app}` map to the Flutter event sink. |
| `buildNotification()` | Creates the persistent "Monitoring your spending habits…" notification required for foreground services on Android 8+. |
| `WATCHED_APPS` | A `mapOf(packageName → appDisplayName)` listing 14 monitored applications (Zomato, Swiggy, Blinkit, Zepto, Amazon, Flipkart, Myntra, Ajio, Nykaa, BookMyShow, BigBasket, PhonePe, Paytm, Google Pay). |

#### `MonitorPlugin.kt` — key functions

| Function | Description |
|---|---|
| `onAttachedToEngine()` | Registers both `MethodChannel('expense_autopsy/monitor')` and `EventChannel('expense_autopsy/monitor_events')` with the Flutter engine. |
| `onMethodCall()` | Handles 4 method calls: `checkUsagePermission`, `requestUsagePermission`, `checkOverlayPermission`, `requestOverlayPermission`, `startMonitor`, `stopMonitor`. |
| `onListen()` | Sets `AppMonitorService.eventSink` to the Flutter sink so Kotlin can push events to Dart. |
| `onCancel()` | Clears the event sink. |

#### `MonitorService.dart` — Flutter bridge

| Method | Description |
|---|---|
| `hasUsagePermission()` | Invokes `checkUsagePermission` method call. Returns `bool`. |
| `requestUsagePermission()` | Opens Android Usage Access settings screen. |
| `hasOverlayPermission()` | Returns whether `SYSTEM_ALERT_WINDOW` is granted. |
| `requestOverlayPermission()` | Opens Android overlay permission screen. |
| `startMonitor()` | Sends `startMonitor` method call and begins listening to the event stream. |
| `stopMonitor()` | Sends `stopMonitor` method call. |
| `setOnAppOpen(callback)` | Registers a `Function(packageName, appName)` called whenever a watched app is opened. |

---

### 2. Behavioral Nudge Engine

**File:** `lib/services/behavior_engine.dart`

The engine computes an impulse risk score (0–100) and projects the savings opportunity of skipping a purchase.

#### `WatchedApp` model

```dart
WatchedApp({
  required String name,       // Display name (e.g. 'Zomato')
  required double avgSpend,   // Average ₹ spend per session
  required String category,   // food | shopping | entertainment | payments | grocery
})
```

#### `BehaviorEngine.score()` — Risk Scoring Algorithm

Inputs: `packageName`, `openCountToday`, `budgetUsedPct` (0.0–1.0), `monthlyLeakage` (₹)

| Factor | Score Added | Condition |
|---|---|---|
| Base | +30 | Any watched-app open |
| Category: Shopping | +20 | `category == 'shopping'` |
| Category: Food | +15 | `category == 'food'` |
| Category: Entertainment | +10 | `category == 'entertainment'` |
| Category: Payments | +5 | `category == 'payments'` |
| Late night / early morning | +20 | Hour 22–24 or 0–5 |
| Evening | +10 | Hour 18–21 |
| High repeat opens (≥3 today) | +15 | |
| Moderate repeat opens (≥2 today) | +8 | |
| Budget nearly exhausted (≥80%) | +20 | |
| Budget under pressure (≥60%) | +10 | |
| High existing leakage (>₹10,000) | +10 | |
| Moderate leakage (>₹5,000) | +5 | |

Score is clamped to `[0, 100]`. The nudge screen is triggered when **score ≥ 50**.

#### `BehaviorEngine.sipAlternative(packageName, {years = 5})`

Calculates the future value of investing the app's average session spend every month for `years` years at **12% p.a.** using the annuity-due formula:

```
FV = monthly × [((1 + r)^n − 1) / r] × (1 + r)
```

where `r = 0.12 / 12`, `n = years × 12`. This is displayed on the nudge screen as **"What if you invested instead?"**

---

### 3. Nudge Screen

**File:** `lib/screens/nudge_screen.dart`

A full-screen overlay that appears (as a new Activity) when a high-risk app is opened.

#### Constructor

```dart
NudgeScreen({
  required String packageName,  // e.g. 'in.swiggy.android'
  required String appName,      // e.g. 'Swiggy'
  required int riskScore,       // 0–100
})
```

#### State variables

| Variable | Type | Description |
|---|---|---|
| `_deciding` | `bool` | Prevents duplicate taps while recording nudge event |
| `_showExpenseForm` | `bool` | If `true`, replaces buttons with "Did you spend?" form |
| `_amountCtrl` | `TextEditingController` | Amount input for post-nudge expense logging |

#### Key methods

| Method | Description |
|---|---|
| `_decide(NudgeDecision)` | Records the nudge event via `ResponseTracker.record()`. If `proceeded`, sets `_showExpenseForm = true` instead of closing. If `skipped`, pops the screen. |
| `_logExpense()` | Called when user confirms the "Did you spend?" form. Creates an `Expense` with `source: 'nudge'`, `tag: 'impulse'`, and calls `AppState.addExpense()`. Then pops the screen and minimizes via `SystemNavigator.pop()`. |
| `_buildAppCard()` | Shows the opened app name + average session spend. |
| `_buildCostCard()` | Shows annual cost of this habit (avgSpend × 12). |
| `_buildAlternativeCard()` | Shows SIP alternative calculation — what the money would grow to in 5 years. |
| `_buildButtons()` | Conditionally renders either the two action buttons ("I'll skip it" / "Proceed anyway") or the "Did you spend?" form depending on `_showExpenseForm`. |

#### Risk badge colors

| Score | Label | Color |
|---|---|---|
| ≥ 80 | CRITICAL | Red |
| ≥ 60 | HIGH RISK | Orange |
| ≥ 40 | MODERATE | Amber |
| < 40 | LOW | Green |

---

### 4. Expense Capture — Post-Nudge Logging

When a user taps **"Proceed anyway"** on the Nudge Screen, instead of immediately dismissing, a **"Did you spend?"** card slides up:

- A numeric text field asking for the actual amount spent
- **"Yes, log it"** (teal) → Creates an `Expense`:
  ```dart
  Expense(
    id: timestamp,
    name: appName,               // e.g. 'Swiggy'
    amount: enteredAmount,
    frequency: 'monthly',
    tag: 'impulse',
    source: 'nudge',
    linkedPackage: packageName,  // e.g. 'in.swiggy.android'
    transactionDate: DateTime.now(),
  )
  ```
  Then calls `AppState.addExpense()` and pops the screen.
- **"Skip"** → Pops normally without logging.

---

### 5. SMS Transaction Parser

**File:** `lib/services/sms_parser.dart`

#### `ParsedTransaction` model

```dart
ParsedTransaction({
  required String merchant,   // Extracted merchant name
  required double amount,     // Parsed ₹ amount
  required DateTime datetime, // Time of parsing
})
```

#### `SmsParser.parse(String smsBody)`

Runs 6 regex patterns in order. Returns the first `ParsedTransaction` match, or `null` if none match.

| Bank / Format | Regex Pattern | Example SMS |
|---|---|---|
| HDFC | `debited for Rs <amount> at <merchant>` | "Your HDFC a/c debited for Rs 349 at Zomato" |
| SBI | `debited with INR <amount>. Info: <merchant>` | "INR 599.00 debited. Info: SWIGGY" |
| ICICI | `Rs <amount> debited from … at <merchant>` | "Rs 1299 debited from XX1234 at Amazon" |
| Paytm/UPI | `paid Rs <amount> to <merchant>` | "You paid Rs 450 to Myntra" |
| Generic UPI | `UPI…Rs <amount>…to <merchant>` | "UPI-Dr Rs.899 to BIGBASKET" |
| Generic debit | `Rs <amount> deducted/debited … at/to/from <merchant>` | "Rs 200 deducted from wallet at PhonePe" |

Amount parsing strips Indian comma formatting (e.g., `1,50,000` → `150000.0`).

#### `SmsParser.fuzzyMatchWatchedApp(String merchant)`

Performs a **case-insensitive substring match** between the extracted merchant name and all entries in `BehaviorEngine.watchedApps`. Returns the matching package name, or `null` if no match.

```dart
// Example: merchant = "SWIGGY ORDER"
// Returns: "in.swiggy.android"
```

---

### 6. SMS Monitor Service

**File:** `lib/services/sms_monitor.dart`

Wraps the `telephony` package for real-time and historical SMS transaction capture.

#### Key methods

| Method | Description |
|---|---|
| `init()` | Requests `Permission.sms` via `permission_handler`. If granted, calls `Telephony.instance.listenIncomingSms()` with `listenInBackground: false`. Each incoming SMS is piped through `SmsParser.parse()`. Valid transactions are added to `_streamController`. |
| `get stream` | Returns `Stream<ParsedTransaction>` — the broadcast stream. The `AppShell` subscribes to this and shows `SmsReviewSheet` on each emission. |
| `scanRecent({int days = 7})` | Reads the inbox via `Telephony.instance.getInboxSms()`, filters messages from the last N days, and returns a list of all `ParsedTransaction`s extracted from them. |
| `dispose()` | Closes the `StreamController`. |

#### Throttling in AppShell

The `AppShell` uses a `bool _smsSheetActive` flag so only **one** `SmsReviewSheet` is shown at a time. The next sheet waits for the current one to be dismissed.

---

### 7. SMS Review Sheet

**File:** `lib/screens/sms_review_sheet.dart`

A modal bottom sheet shown when a bank SMS transaction is detected.

#### Constructor

```dart
SmsReviewSheet({
  required ParsedTransaction transaction,
  required Function(Expense) onConfirm,
})
```

#### UI Elements

| Element | Description |
|---|---|
| Amount display | Shows detected ₹ amount (read-only highlight) |
| Merchant field | Pre-filled, editable `TextField` for the merchant name |
| Amount field | Editable amount in case the regex slightly misread the value |
| Category buttons | Three toggle buttons — **Essential** (green), **Avoidable** (amber), **Impulse** (red) |
| Cancel | Dismisses without saving |
| Add Expense | Calls `onConfirm(expense)` with `source: 'sms_import'` and `linkedPackage` from fuzzy matching |

#### Expense created on confirm

```dart
Expense(
  id: timestamp,
  name: merchantName (edited),
  amount: editedAmount,
  frequency: 'monthly',
  tag: selectedTag,             // 'essential' | 'avoidable' | 'impulse'
  linkedPackage: fuzzyMatch,    // package name or null
  source: 'sms_import',
  transactionDate: transaction.datetime,
)
```

---

### 8. Dashboard Page

**File:** `lib/main.dart` → `DashboardPage`

The primary landing screen.

#### Sections

| Section | Description |
|---|---|
| **Money Leaking Right Now** | Animated live counter showing ₹/second bleeding rate based on monthly leakage ÷ seconds in a month. Updates every second with a ticker. |
| **Financial Health Score** | Score 0–100 calculated as `max(0, 100 − (leakage / salary × 100))`. Rendered as a gradient arc using `_ScoreRingPainter` (CustomPainter). |
| **Income vs Expenses Chart** | `_RealLineChart` — a `FutureBuilder` driving `_TwoLinePainter`. Calls `MonthlySnapshotService.getLast6Months()` and plots salary vs total spend for up to 6 months. Uses real MongoDB data; falls back to empty canvas if no snapshots. |
| **Category Breakdown** | Pie/percentage breakdown of Essential / Avoidable / Impulse monthly spending totals. |
| **Monthly Breakdown Bar** | Horizontal stacked bar showing 3-category split. |
| **Top Spending Leaks** | Ranked list of top 3 individual expenses by monthly-equivalent amount. |
| **Nudge Prompt Strip** | Summary of today's skipped nudges and total saved. |

#### Helper functions used on Dashboard

| Function | Description |
|---|---|
| `_monthlyEquiv(amount, freq)` | Converts daily/weekly/monthly amounts to a monthly equivalent: daily × 30, weekly × 52/12. |
| `_monthlyLeakage(expenses)` | Sum of monthly-equivalent amounts for non-essential expenses. |
| `_monthlyTotal(expenses)` | Sum of monthly-equivalent amounts for all expenses. |
| `_fmtINR(double)` | Formats numbers as ₹1.2K, ₹1.5L, ₹1.2Cr etc. |

---

### 9. Expenses Page

**File:** `lib/main.dart` → `ExpensesPage`

Full list of tracked expenses with inline editing capabilities.

#### Features

- **Add Expense** — bottom sheet form with fields: name, amount, frequency (daily/weekly/monthly), tag (essential/avoidable/impulse).
- **Remove Expense** — swipe-to-delete or trash icon.
- **Cycle Tag** — tap the colored badge to cycle through essential → avoidable → impulse → essential via `AppState.toggleExpenseTag(id)`.
- **Source Badge** — shows `manual`, `sms_import`, or `nudge` pill for each expense so the user knows how it was captured.
- **Monthly equivalent** shown alongside each expense.

---

### 10. Goals Page

**File:** `lib/main.dart` → `GoalsPage`

Financial goal tracker loaded fully from MongoDB.

#### Goal model

```dart
Goal({
  required String id,
  required String name,
  required double targetAmount,
  required double savedAmount,
  required String targetDate,    // ISO date string 'YYYY-MM-DD'
  required int priority,         // 1 = critical, 2 = important, 3 = nice-to-have
})
```

#### Features

- Progress bar per goal (savedAmount / targetAmount).
- Days remaining calculation from `targetDate`.
- Priority badges (P1 / P2 / P3).
- **Add Goal** bottom sheet: name, target amount, target date, priority.
- **Remove Goal** via swipe or delete.
- `AppState.addGoal()` / `AppState.removeGoal()` update in-memory state.

---

### 11. Simulator (SIP Calculator)

**File:** `lib/main.dart` → `SimulatorPage`

An interactive SIP (Systematic Investment Plan) compound interest calculator.

#### Inputs (live sliders)
- Monthly investment amount
- Expected annual return (%)
- Duration in years

#### Output
- **Total Invested** — `amount × months`
- **Estimated Returns** — `futureValue − totalInvested`
- **Future Value** — using `_futureValue()`:
  ```dart
  FV = monthly × [((1+r)^n − 1) / r] × (1+r)
  // r = annualRate / 12 / 100, n = months
  ```
- `_SipChart` — CustomPainter area chart showing growth curve over time.

The simulator is pre-seeded from `AppState.sipAmount`, `sipReturn`, and `sipMonths` loaded from MongoDB.

---

### 12. Insights Page

**File:** `lib/main.dart` → `InsightsPage`

Behavioral analytics powered by `ResponseTracker`.

#### Metrics displayed

| Metric | Source | Description |
|---|---|---|
| Total Nudges | `ResponseTracker.all()` | Total count of nudge events ever recorded |
| Skipped | `.where(decision == skipped)` | Count of impulses resisted |
| Proceeded | `.where(decision == proceeded)` | Count of impulses yielded to |
| Skip Rate % | skipped / total × 100 | Willpower percentage |
| Skip Streak | `ResponseTracker.skipStreak()` | Consecutive days with only skips (0 proceeds) |
| Total Saved | `ResponseTracker.totalSaved(avgSpendMap)` | Sum of avgSpend for every skipped nudge |
| Per-app breakdown | Grouped by `packageName` | Table of skip/proceed counts per watched app |

#### `ResponseTracker.skipStreak()` algorithm

Walks day-by-day backwards from today. A day counts toward the streak only if it has **at least one skip** and **zero proceeds**. Stops on the first day that breaks this rule.

---

### 13. Profile Edit Feature

**Files:** `lib/main.dart` → `_EditProfileSheet`, `lib/services/db_service.dart`

A full edit form accessible via the avatar icon in the Dashboard AppBar.

#### Fields

| Field | Validation | Saved to |
|---|---|---|
| Full Name | Required | `profile.name` |
| Occupation | Optional | `profile.occupation` |
| City | Optional | `profile.city` |
| Monthly Salary (₹) | Must be valid number | `profile.monthlySalary` |
| SIP Amount (₹) | Must be valid number | `sip.monthlyAmount` |
| Return % / year | Must be valid decimal | `sip.annualReturn` |
| SIP Duration (years) | Must be whole number | `sip.durationMonths` (× 12) |

#### Save flow

1. `_EditProfileSheetState._save()` validates the form.
2. Calls `AppState.updateProfile(...)`.
3. `AppState.updateProfile()`:
   - Updates all in-memory fields immediately.
   - Calls `notifyListeners()` → UI refreshes across all pages.
   - Calls `DbService.updateUserProfile()`.
4. `DbService.updateUserProfile()` executes a MongoDB `$set` patch using `modify.set(...)` for each field — never overwrites unrelated document data.
5. Shows a green `✅ Profile saved!` snackbar on success, or red `❌ Save failed` if the DB is unreachable.

---

### 14. Monthly Snapshot Service

**File:** `lib/services/monthly_snapshot_service.dart`

Stores aggregated monthly financial data for the Income vs Expenses chart.

#### `MonthlySnapshot` model

```dart
MonthlySnapshot({
  String month,           // 'YYYY-MM' format
  double essential,       // Total essential spend
  double avoidable,       // Total avoidable spend
  double impulse,         // Total impulse spend
  double salary,          // Monthly salary from profile
  int nudgeSkips,         // Nudges resisted that month
  int nudgeProceeds,      // Nudges yielded to that month
})
```

#### Key methods

| Method | Description |
|---|---|
| `takeSnapshotIfNeeded(AppState)` | Checks SharedPreferences for `last_snapshot_month`. If the current month is new, aggregates all expenses, counts nudge events from `ResponseTracker`, writes the snapshot as JSON to SharedPrefs under `snapshot_YYYY-MM`, and updates `last_snapshot_month`. Called from `AppShell.initState()` with a 3-second delay. |
| `getLast6Months({userId})` | **Priority 1:** Queries `monthly_snapshots` collection in MongoDB via `DbService.fetchMonthlySnapshots()`. If results exist, maps them to `MonthlySnapshot` objects. **Priority 2 (fallback):** Reads last 6 `snapshot_YYYY-MM` keys from SharedPreferences if MongoDB is unavailable. Returns sorted oldest-first. |

---

### 15. Response Tracker

**File:** `lib/services/response_tracker.dart`

Persists a capped log (last 500 events) of nudge decisions to `SharedPreferences`.

#### `NudgeEvent` model

```dart
NudgeEvent({
  String packageName,       // e.g. 'in.swiggy.android'
  String appName,           // e.g. 'Swiggy'
  int riskScore,            // 0–100
  NudgeDecision decision,   // skipped | proceeded
  DateTime timestamp,
})
```

#### Key methods

| Method | Description |
|---|---|
| `record(NudgeEvent)` | Appends event to the JSON list in SharedPrefs. Trims to last 500 if needed. |
| `all()` | Returns all stored `NudgeEvent`s. |
| `openCountToday(packageName)` | Counts how many nudge events exist for this package on today's date. Used by `BehaviorEngine.score()` for the "repeat opens" factor. |
| `totalSaved(avgSpendMap)` | Sums `avgSpendMap[packageName]` for every event with `decision == skipped`. |
| `skipStreak()` | Computes the longest current run of days where user only skipped (no proceeds). |

---

### 16. MongoDB Database Service

**File:** `lib/services/db_service.dart`

All MongoDB operations. Uses a singleton `Db` instance with auto-reconnect via `_ensureConnected()`.

#### Connection

```
mongodb+srv://<user>:<pass>@cluster0.mgoqoor.mongodb.net/expense_app
```

#### Key methods

| Method | Collection | Description |
|---|---|---|
| `connect()` | — | Opens the MongoDB connection. Called automatically. |
| `fetchUserData(email)` | `users` | Returns the full user document for the given email. |
| `updateUserProfile(email, {...})` | `users` | Patches `profile.*` and `sip.*` fields using `modify.set()`. Upserts if needed. |
| `fetchUserExpenses(userId)` | `expenses` | Returns all expense documents for the user. |
| `fetchUserGoals(userId)` | `goals` | Returns all goal documents for the user. |
| `fetchMonthlySnapshots(userId, count)` | `monthly_snapshots` | Returns last N snapshots sorted oldest-first. |
| `fetchBehaviorEvents(userId, daysBack)` | `behavior_events` | Returns behavior events from last N days. |
| `countSkippedDecisions(userId)` | `behavior_events` | Count of `decision == 'skipped'` events. |

---

### 17. App State Management

**File:** `lib/main.dart` → `AppState`

Single source of truth. Extends `ChangeNotifier`, wrapped in `AppStateProvider` (`InheritedNotifier`).

#### Fields

| Field | Type | Source |
|---|---|---|
| `expenses` | `List<Expense>` | MongoDB `expenses` collection |
| `goals` | `List<Goal>` | MongoDB `goals` collection |
| `monthlySalary` | `double` | MongoDB `users.profile.monthlySalary` |
| `sipAmount` | `double` | MongoDB `users.sip.monthlyAmount` |
| `sipReturn` | `double` | MongoDB `users.sip.annualReturn` |
| `sipMonths` | `int` | MongoDB `users.sip.durationMonths` |
| `userName` | `String` | MongoDB `users.profile.name` |
| `userEmail` | `String` | Hardcoded identifier (`vikas@example.com`) |
| `userOccupation` | `String` | MongoDB `users.profile.occupation` |
| `userCity` | `String` | MongoDB `users.profile.city` |
| `isLoading` | `bool` | `true` during initial DB fetch |

#### Initialization flow (`_initData`)

```
connect to MongoDB
  ↓
fetch user document  → populate profile/sip fields
  ↓
fetch expenses       → map via _expenseFromDoc()
  ↓
fetch goals          → map via _goalFromDoc()
  ↓
isLoading = false    → notifyListeners() → UI renders
```

#### Mutating methods

| Method | Description |
|---|---|
| `toggleExpenseTag(id)` | Cycles the tag: essential → avoidable → impulse → essential |
| `addExpense(Expense)` | Prepends to `expenses` list |
| `removeExpense(id)` | Filters out by id |
| `addGoal(Goal)` | Prepends to `goals` list |
| `removeGoal(id)` | Filters out by id |
| `setSip({amount, ret, months})` | Updates SIP parameters |
| `updateProfile({...})` | Updates all profile fields in memory + persists to MongoDB |

---

## Database Schema

### Collection: `users`

```json
{
  "email": "vikas@example.com",
  "profile": {
    "name": "Vikas Sharma",
    "occupation": "Software Engineer",
    "city": "Mumbai",
    "monthlySalary": 95000,
    "annualBonus": 150000
  },
  "sip": {
    "monthlyAmount": 15000,
    "annualReturn": 12,
    "durationMonths": 180
  },
  "createdAt": "ISODate"
}
```

### Collection: `expenses`

```json
{
  "userId": "vikas@example.com",
  "name": "Swiggy dinners",
  "amount": 450,
  "frequency": "weekly",
  "tag": "impulse",
  "source": "sms_import",
  "linkedPackage": "in.swiggy.android",
  "transactionDate": "ISODate"
}
```

`frequency` values: `daily`, `weekly`, `monthly`  
`tag` values: `essential`, `avoidable`, `impulse`  
`source` values: `manual`, `sms_import`, `nudge`

### Collection: `goals`

```json
{
  "userId": "vikas@example.com",
  "name": "Trip to Japan",
  "targetAmount": 300000,
  "savedAmount": 97000,
  "targetDate": "2027-03-01",
  "priority": 2,
  "icon": "✈️",
  "category": "travel"
}
```

### Collection: `monthly_snapshots`

```json
{
  "userId": "vikas@example.com",
  "month": "2025-10",
  "essential": 9953,
  "avoidable": 4066,
  "impulse": 7600,
  "salary": 95000,
  "nudgeSkips": 3,
  "nudgeProceeds": 5
}
```

### Collection: `behavior_events`

```json
{
  "userId": "vikas@example.com",
  "appName": "Swiggy",
  "packageName": "in.swiggy.android",
  "decision": "skipped",
  "timestamp": "ISODate"
}
```

---

## Android Native Layer

### Permissions in `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
    tools:ignore="ProtectedPermissions"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.RECEIVE_SMS"/>
<uses-permission android:name="android.permission.READ_SMS"/>
```

### `AppMonitorService` as a Foreground Service

Declared in manifest:
```xml
<service
    android:name=".AppMonitorService"
    android:foregroundServiceType="dataSync"
    android:exported="false"/>
```

### Desugaring

Required for `java.time` API support on older Android versions. Configured in `app/build.gradle.kts`:
```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
}
```

---

## Permissions Required

| Permission | Purpose | How to Grant |
|---|---|---|
| Usage Access | Detect which app is in the foreground | Settings → Apps → Special App Access → Usage Access → enable Expense Autopsy |
| Display Over Other Apps | Show Nudge Screen overlay | Settings → Apps → Special App Access → Display Over Other Apps → enable |
| SMS Read / Receive | Parse banking SMS transactions | Prompted at runtime |

The app shows a permission request sheet on first launch (and when Usage Access is not granted).

---

## Setup & Running

### Prerequisites

- Flutter 3.x SDK
- Android Studio with Android SDK 31+
- Node.js (for database seeding)
- A MongoDB Atlas cluster (connection string already configured in `db_service.dart`)

### Clone & Run

```bash
git clone https://github.com/ani-coder01/my-track
cd expense-autopsy-flutter

# Install Flutter dependencies
flutter pub get

# Connect your Android device via USB (enable USB debugging)
flutter run
```

### First-time Permissions

On first launch on your device:
1. Tap **"Enable Behavior Monitor"** in the bottom sheet that appears.
2. Grant **Usage Access** → enable Expense Autopsy.
3. Grant **Display Over Other Apps** → enable Expense Autopsy.
4. Grant **SMS** permission when prompted.

---

## Seeding the Database

The seed script inserts a complete, realistic dataset for `vikas@example.com`.

```bash
# From the project root
node seed_mongo.js
```

**What it seeds:**
- 1 user profile with salary, SIP settings, occupation, city
- 20 expenses across all categories (food, shopping, entertainment, essentials)
- 4 financial goals (Japan trip, Emergency fund, MacBook, Home down-payment)
- 6 months of historical spending snapshots for the dashboard chart

> ⚠️ The script deletes and re-inserts all records for `vikas@example.com` each time — safe to run repeatedly.

---

## Design System

### Color Palette (Light Mode — "Warm Cream")

| Token | Color | Hex | Usage |
|---|---|---|---|
| `kBg` | Warm cream | `#FFFBF0` | Page background |
| `kBgSoft` | Pure white | `#FFFFFF` | AppBar, cards |
| `kPanel` | Soft warm panel | `#FEF5E7` | Sheets, modals |
| `kTeal` | Fresh green | `#10B981` | Primary CTA, accents |
| `kGreen` | Mint green | `#34D399` | Gradient end, positive |
| `kBlue` | Sky blue | `#3B82F6` | Secondary accents |
| `kAmber` | Warm amber | `#FB923C` | Avoidable category |
| `kRed` | Coral red | `#F87171` | Impulse category, danger |
| `kMuted` | Warm brown | `#7D6B5F` | Secondary text |
| `kBorder` | Warm border | `#FFDFC9` | Card borders |

### Typography

| Style | Font | Usage |
|---|---|---|
| `spaceGrotesk(...)` | Space Grotesk | Headings, numbers, financial figures |
| `jakarta(...)` | Plus Jakarta Sans | Body text, labels, descriptions |

### Component Library

| Component | Description |
|---|---|
| `GlassCard` | Rounded card with subtle teal radial gradient, used for all dashboard panels |
| `Pill` | Color-coded badge widget — tones: `teal`, `positive`, `warning`, `default` |
| `Eyebrow` | Uppercase teal micro-heading (letter-spacing: 2) |
| `SectionHeader` | Eyebrow + large title + optional description |
| `MetricRow` | Horizontal row of label/value pairs for quick stats |
| `ProgressBar` | Slim colored progress bar with rounded caps |
| `PageFrame` | Standard page scaffold with SafeArea + scrollable content + padding |

---

## Data Flow Summary

```
MongoDB Atlas
    ↓ on startup
AppState._initData()
    ↓ populates
expenses, goals, profile, sip
    ↓ drives
All Pages (Dashboard, Expenses, Goals, Simulator, Insights)

User opens Zomato
    ↓
AppMonitorService (Kotlin, every 1.5s)
    ↓ EventChannel
MonitorService.dart → AppShell._onAppOpen()
    ↓
BehaviorEngine.score() → risk ≥ 50
    ↓
NudgeScreen pushed as new route
    ↓ user taps "Proceed"
_showExpenseForm = true
    ↓ user confirms amount
AppState.addExpense(source: 'nudge')

Bank SMS arrives
    ↓
SmsMonitor → SmsParser.parse()
    ↓
SmsReviewSheet shown
    ↓ user classifies + confirms
AppState.addExpense(source: 'sms_import')

User edits profile
    ↓
_EditProfileSheet validates
    ↓
AppState.updateProfile()
    ↓ simultaneously
notifyListeners() + DbService.updateUserProfile() → MongoDB $set
```

---

*Built with ❤️ as a behavior-change financial tool — Expense Autopsy v1.0*
