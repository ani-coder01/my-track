// scripts/mongodb_setup.js
// MongoDB setup script to create collections and insert dummy data
// Run with: mongosh < mongodb_setup.js

use expense_app

// ═══════════════════════════════════════════════════════════════════════════
//  SCHEMA DESIGN
// ═══════════════════════════════════════════════════════════════════════════

// Drop existing collections
db.users.drop()
db.behavior_events.drop()
db.goals.drop()
db.transactions.drop()

// ─── Create users collection ─────────────────────────────────────────────
db.createCollection('users', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['email', 'profile'],
      properties: {
        _id: { bsonType: 'objectId' },
        email: { bsonType: 'string' },
        profile: {
          bsonType: 'object',
          required: ['name', 'monthlySalary'],
          properties: {
            name: { bsonType: 'string' },
            monthlySalary: { bsonType: 'double' },
            createdAt: { bsonType: 'date' }
          }
        },
        sip: {
          bsonType: 'object',
          properties: {
            monthlyAmount: { bsonType: 'double' },
            annualReturn: { bsonType: 'double' },
            durationMonths: { bsonType: 'int' }
          }
        }
      }
    }
  }
})

// ─── Create behavior_events collection ───────────────────────────────────
db.createCollection('behavior_events', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['userId', 'packageName', 'decision', 'timestamp'],
      properties: {
        _id: { bsonType: 'objectId' },
        userId: { bsonType: 'objectId' },
        packageName: { bsonType: 'string' },
        appName: { bsonType: 'string' },
        decision: { enum: ['skipped', 'proceeded'] },
        riskScore: { bsonType: 'int' },
        timestamp: { bsonType: 'date' }
      }
    }
  }
})

// ─── Create goals collection ────────────────────────────────────────────
db.createCollection('goals', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      properties: {
        _id: { bsonType: 'objectId' },
        userId: { bsonType: 'objectId' },
        name: { bsonType: 'string' },
        targetAmount: { bsonType: 'double' },
        savedAmount: { bsonType: 'double' },
        targetDate: { bsonType: 'date' },
        priority: { bsonType: 'int' }
      }
    }
  }
})

// ─── Create transactions collection ────────────────────────────────────
db.createCollection('transactions', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      properties: {
        _id: { bsonType: 'objectId' },
        userId: { bsonType: 'objectId' },
        amount: { bsonType: 'double' },
        category: { bsonType: 'string' },
        timestamp: { bsonType: 'date' }
      }
    }
  }
})

// ═══════════════════════════════════════════════════════════════════════════
//  CREATE INDEXES
// ═══════════════════════════════════════════════════════════════════════════

// Fast queries for behavior events
db.behavior_events.createIndex({ userId: 1, timestamp: -1 })
db.behavior_events.createIndex({ userId: 1, packageName: 1, timestamp: -1 })
db.behavior_events.createIndex({ timestamp: -1 })

// Fast queries for goals
db.goals.createIndex({ userId: 1, targetDate: 1 })

// Fast user lookups
db.users.createIndex({ email: 1 }, { unique: true })

// ═══════════════════════════════════════════════════════════════════════════
//  INSERT DUMMY DATA
// ═══════════════════════════════════════════════════════════════════════════

// Main test user
const testUserId = db.users.insertOne({
  email: 'vikas@example.com',
  profile: {
    name: 'Vikas',
    monthlySalary: 85000,
    createdAt: new Date('2024-01-01')
  },
  sip: {
    monthlyAmount: 12000,
    annualReturn: 12,
    durationMonths: 120
  }
}).insertedId

// Additional users (50 more)
const userEmails = []
for (let i = 1; i <= 50; i++) {
  const email = `user${i}@example.com`
  userEmails.push(email)
  db.users.insertOne({
    email: email,
    profile: {
      name: `User ${i}`,
      monthlySalary: 50000 + Math.random() * 100000,
      createdAt: new Date(2024, 0, Math.floor(Math.random() * 30) + 1)
    },
    sip: {
      monthlyAmount: 5000 + Math.random() * 30000,
      annualReturn: 10 + Math.random() * 8,
      durationMonths: 60 + Math.floor(Math.random() * 120)
    }
  })
}

// Insert 200+ behavior events for test user
const watchedApps = [
  { pkg: 'com.application.zomato', name: 'Zomato' },
  { pkg: 'in.swiggy.android', name: 'Swiggy' },
  { pkg: 'com.grofers.customerapp', name: 'Blinkit' },
  { pkg: 'com.zeptconsumerapp', name: 'Zepto' },
  { pkg: 'com.amazon.mShop.android.shopping', name: 'Amazon' },
  { pkg: 'com.flipkart.android', name: 'Flipkart' },
  { pkg: 'com.myntra.android', name: 'Myntra' },
  { pkg: 'com.phonepe.app', name: 'PhonePe' }
]

const eventsToInsert = []
const baseDate = new Date(2026, 3, 1) // April 1, 2026

for (let day = 0; day < 30; day++) {
  for (let eventIdx = 0; eventIdx < 7; eventIdx++) {
    const app = watchedApps[Math.floor(Math.random() * watchedApps.length)]
    const decision = Math.random() > 0.3 ? 'skipped' : 'proceeded'
    const timestamp = new Date(baseDate)
    timestamp.setDate(timestamp.getDate() + day)
    timestamp.setHours(Math.floor(Math.random() * 24))
    timestamp.setMinutes(Math.floor(Math.random() * 60))

    eventsToInsert.push({
      userId: testUserId,
      packageName: app.pkg,
      appName: app.name,
      decision: decision,
      riskScore: Math.floor(30 + Math.random() * 70),
      timestamp: timestamp
    })
  }
}

db.behavior_events.insertMany(eventsToInsert)

// Insert goals for test user
db.goals.insertMany([
  {
    userId: testUserId,
    name: 'Trip to Japan',
    targetAmount: 250000,
    savedAmount: 72000,
    targetDate: new Date('2027-09-01'),
    priority: 2
  },
  {
    userId: testUserId,
    name: 'Emergency fund',
    targetAmount: 400000,
    savedAmount: 168000,
    targetDate: new Date('2026-12-01'),
    priority: 1
  },
  {
    userId: testUserId,
    name: 'New Laptop',
    targetAmount: 150000,
    savedAmount: 45000,
    targetDate: new Date('2026-08-15'),
    priority: 3
  }
])

// Insert sample behavior events for other users (5 events each)
for (const email of userEmails.slice(0, 20)) {
  const userId = db.users.findOne({ email: email })._id
  const userEvents = []
  for (let i = 0; i < 5; i++) {
    const app = watchedApps[Math.floor(Math.random() * watchedApps.length)]
    userEvents.push({
      userId: userId,
      packageName: app.pkg,
      appName: app.name,
      decision: Math.random() > 0.4 ? 'skipped' : 'proceeded',
      riskScore: Math.floor(40 + Math.random() * 60),
      timestamp: new Date()
    })
  }
  db.behavior_events.insertMany(userEvents)
}

// ═══════════════════════════════════════════════════════════════════════════
//  VERIFY DATA
// ═══════════════════════════════════════════════════════════════════════════

print('✓ Collections created')
print(`✓ Users: ${db.users.countDocuments()} documents`)
print(`✓ Behavior Events: ${db.behavior_events.countDocuments()} documents`)
print(`✓ Goals: ${db.goals.countDocuments()} documents`)
print(`✓ Indexes created on behavior_events and users`)

print('\n✓ Setup complete!')
print(`\nTest user email: vikas@example.com`)
print(`Sample users: ${userEmails.slice(0, 5).join(', ')}`)
