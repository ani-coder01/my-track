/**
 * Expense Autopsy — MongoDB Seed Script
 * Run: node seed_mongo.js
 * 
 * Seeds a full, realistic dataset for the "vikas@example.com" user so the
 * Flutter app has NO hardcoded fallback data.
 */

const { MongoClient } = require('mongodb');

const URI =
  'mongodb+srv://nickhasntlost_db_user:Pz03WjAzQ8pv7ygA@cluster0.mgoqoor.mongodb.net/expense_app?retryWrites=true&w=majority&appName=Cluster0';

const USER_EMAIL = 'vikas@example.com';

// ── 1. User profile document ──────────────────────────────────────────────────
const userDoc = {
  email: USER_EMAIL,
  profile: {
    name: 'Vikas Sharma',
    avatarInitials: 'VS',
    city: 'Mumbai',
    occupation: 'Software Engineer',
    monthlySalary: 95000,
    annualBonus: 150000,
  },
  sip: {
    monthlyAmount: 15000,
    annualReturn: 12,
    durationMonths: 180, // 15 years
  },
  createdAt: new Date(),
};

// ── 2. Expenses (linked to user by email as userId) ───────────────────────────
function daysAgo(n) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d;
}

const expenses = [
  // Food — Impulse
  { name: 'Swiggy dinners', amount: 450, frequency: 'weekly',   tag: 'impulse',   source: 'manual',     linkedPackage: 'in.swiggy.android',                    transactionDate: daysAgo(2)  },
  { name: 'Zomato lunch',   amount: 320, frequency: 'weekly',   tag: 'impulse',   source: 'sms_import', linkedPackage: 'com.application.zomato',               transactionDate: daysAgo(5)  },
  { name: 'Blinkit grocery',amount: 890, frequency: 'monthly',  tag: 'avoidable', source: 'sms_import', linkedPackage: 'com.grofers.customerapp',               transactionDate: daysAgo(10) },
  { name: 'Zepto midnight',  amount: 340, frequency: 'weekly',   tag: 'impulse',   source: 'manual',     linkedPackage: 'com.zeptconsumerapp',                  transactionDate: daysAgo(3)  },

  // Entertainment — Avoidable
  { name: 'Netflix subscription', amount: 649,  frequency: 'monthly', tag: 'avoidable', source: 'manual', transactionDate: daysAgo(1)  },
  { name: 'Amazon Prime',         amount: 299,  frequency: 'monthly', tag: 'avoidable', source: 'manual', transactionDate: daysAgo(12) },
  { name: 'Spotify Premium',      amount: 119,  frequency: 'monthly', tag: 'avoidable', source: 'manual', transactionDate: daysAgo(12) },
  { name: 'BookMyShow movies',    amount: 750,  frequency: 'monthly', tag: 'avoidable', source: 'manual', linkedPackage: 'com.bms.bmsapp', transactionDate: daysAgo(7) },

  // Shopping — Impulse
  { name: 'Myntra fashion haul',  amount: 2800, frequency: 'monthly', tag: 'impulse',   source: 'sms_import', linkedPackage: 'com.myntra.android',              transactionDate: daysAgo(15) },
  { name: 'Nykaa skincare',       amount: 1400, frequency: 'monthly', tag: 'impulse',   source: 'sms_import', linkedPackage: 'com.fsn.nykaa',                   transactionDate: daysAgo(20) },
  { name: 'Amazon impulse buys',  amount: 1800, frequency: 'monthly', tag: 'impulse',   source: 'manual',     linkedPackage: 'com.amazon.mShop.android.shopping', transactionDate: daysAgo(8) },
  { name: 'Ajio sale shopping',   amount: 3200, frequency: 'monthly', tag: 'impulse',   source: 'sms_import', linkedPackage: 'com.ril.ajio',                    transactionDate: daysAgo(25) },

  // Essential — Non-negotiable
  { name: 'Metro commute',        amount: 55,   frequency: 'daily',   tag: 'essential', source: 'manual', transactionDate: daysAgo(0) },
  { name: 'Electricity bill',     amount: 1800, frequency: 'monthly', tag: 'essential', source: 'manual', transactionDate: daysAgo(20) },
  { name: 'Internet broadband',   amount: 999,  frequency: 'monthly', tag: 'essential', source: 'manual', transactionDate: daysAgo(18) },
  { name: 'Gym membership',       amount: 1499, frequency: 'monthly', tag: 'essential', source: 'manual', transactionDate: daysAgo(30) },
  { name: 'Health insurance',     amount: 2400, frequency: 'monthly', tag: 'essential', source: 'manual', transactionDate: daysAgo(28) },
  { name: 'BigBasket essentials', amount: 3200, frequency: 'monthly', tag: 'essential', source: 'manual', linkedPackage: 'com.bigbasket.mobileapp', transactionDate: daysAgo(6) },
  { name: 'Cloud storage',        amount: 219,  frequency: 'monthly', tag: 'avoidable', source: 'manual', transactionDate: daysAgo(14) },
  { name: 'Weekend cafe runs',    amount: 900,  frequency: 'weekly',  tag: 'avoidable', source: 'manual', transactionDate: daysAgo(4)  },
].map(e => ({ ...e, userId: USER_EMAIL }));

// ── 3. Goals ──────────────────────────────────────────────────────────────────
const goals = [
  {
    userId: USER_EMAIL,
    name: 'Trip to Japan',
    targetAmount: 300000,
    savedAmount: 97000,
    targetDate: '2027-03-01',
    priority: 2,
    icon: '✈️',
    category: 'travel',
  },
  {
    userId: USER_EMAIL,
    name: 'Emergency fund (6 months)',
    targetAmount: 570000, // 6 × 95000
    savedAmount: 210000,
    targetDate: '2026-12-01',
    priority: 1,
    icon: '🛡️',
    category: 'safety',
  },
  {
    userId: USER_EMAIL,
    name: 'MacBook Pro upgrade',
    targetAmount: 180000,
    savedAmount: 45000,
    targetDate: '2026-10-01',
    priority: 3,
    icon: '💻',
    category: 'gadget',
  },
  {
    userId: USER_EMAIL,
    name: 'Home down-payment fund',
    targetAmount: 2000000,
    savedAmount: 320000,
    targetDate: '2029-01-01',
    priority: 1,
    icon: '🏠',
    category: 'housing',
  },
];

// ── 4. Monthly Snapshots (6 months history) ───────────────────────────────────
function monthKey(monthsBackFromNow) {
  const d = new Date();
  d.setMonth(d.getMonth() - monthsBackFromNow);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

const monthlySnapshots = [
  { month: monthKey(5), essential: 9953, avoidable: 4066, impulse: 7600, salary: 95000, nudgeSkips: 3, nudgeProceeds: 5 },
  { month: monthKey(4), essential: 10200, avoidable: 3890, impulse: 8200, salary: 95000, nudgeSkips: 5, nudgeProceeds: 3 },
  { month: monthKey(3), essential: 9800, avoidable: 4200, impulse: 6900, salary: 95000, nudgeSkips: 7, nudgeProceeds: 2 },
  { month: monthKey(2), essential: 10100, avoidable: 3600, impulse: 9100, salary: 95000, nudgeSkips: 4, nudgeProceeds: 6 },
  { month: monthKey(1), essential: 9600, avoidable: 4400, impulse: 7400, salary: 95000, nudgeSkips: 8, nudgeProceeds: 1 },
  { month: monthKey(0), essential: 9953, avoidable: 4066, impulse: 8540, salary: 95000, nudgeSkips: 6, nudgeProceeds: 3 },
].map(s => ({ ...s, userId: USER_EMAIL }));

// ── Runner ────────────────────────────────────────────────────────────────────
async function seed() {
  const client = new MongoClient(URI);
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    const db = client.db('expense_app');

    // ── Users ──
    const users = db.collection('users');
    await users.deleteMany({ email: USER_EMAIL });
    await users.insertOne(userDoc);
    console.log('✅ User seeded');

    // ── Expenses ──
    const expensesColl = db.collection('expenses');
    await expensesColl.deleteMany({ userId: USER_EMAIL });
    await expensesColl.insertMany(expenses);
    console.log(`✅ ${expenses.length} expenses seeded`);

    // ── Goals ──
    const goalsColl = db.collection('goals');
    await goalsColl.deleteMany({ userId: USER_EMAIL });
    await goalsColl.insertMany(goals);
    console.log(`✅ ${goals.length} goals seeded`);

    // ── Monthly Snapshots ──
    const snapshotsColl = db.collection('monthly_snapshots');
    await snapshotsColl.deleteMany({ userId: USER_EMAIL });
    await snapshotsColl.insertMany(monthlySnapshots);
    console.log(`✅ ${monthlySnapshots.length} monthly snapshots seeded`);

    console.log('\n🎉 All done! MongoDB is fully seeded for vikas@example.com');
  } catch (err) {
    console.error('❌ Seed failed:', err);
  } finally {
    await client.close();
  }
}

seed();
