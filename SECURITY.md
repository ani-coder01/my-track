# MongoDB Credentials Security Guide

## ⚠️ CRITICAL SECURITY ISSUE

The MongoDB connection URI with hardcoded credentials is currently exposed in:
- `lib/services/db_service.dart` (line 5-6)

**Credentials exposed:**
- Username: `nickhasntlost_db_user`
- Password: `Pz03WjAzQ8pv7ygA`
- Cluster: `cluster0.mgoqoor.mongodb.net`

**Action Required:**
1. ✅ Rotate the MongoDB credentials immediately
2. ✅ Move to environment variables/secure config
3. ✅ Never commit credentials to git

## Solution: Use `flutter_dotenv`

### Step 1: Add dependency

```yaml
# pubspec.yaml
dependencies:
  flutter_dotenv: ^5.1.0
```

### Step 2: Create `.env.example` (commit this)

```env
# .env.example - Copy this to .env and fill in real values
# DO NOT COMMIT .env - add to .gitignore

MONGODB_URI=mongodb+srv://your_username:your_password@cluster0.mgoqoor.mongodb.net/expense_app?retryWrites=true&w=majority&appName=Cluster0
```

### Step 3: Create `.env` (add to .gitignore)

```env
# .env - DO NOT COMMIT THIS FILE
MONGODB_URI=mongodb+srv://YOUR_USERNAME:YOUR_PASSWORD@cluster0.mgoqoor.mongodb.net/expense_app?retryWrites=true&w=majority&appName=Cluster0
```

### Step 4: Update `.gitignore`

```gitignore
# Environment variables
.env
.env.local
.env.*.local
```

### Step 5: Update `main.dart` to load env vars

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  // ... rest of main
}
```

### Step 6: Update `DbService`

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DbService {
  static String? _loadUri() {
    final uri = dotenv.env['MONGODB_URI'];
    if (uri == null) {
      print('ERROR: MONGODB_URI not found in .env file');
      return null;
    }
    return uri;
  }

  static String get mongoUri => _loadUri() ??
    'mongodb+srv://error:error@localhost'; // fallback, won't work

  static Db? _db;

  static Future<void> connect() async {
    try {
      _db = await Db.create(mongoUri);
      await _db!.open();
      if (kDebugMode) {
        print('Connected to MongoDB!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error connecting to MongoDB: $e');
      }
    }
  }
  // ... rest of class
}
```

## Production Deployment

For production (Firebase, AWS, Google Cloud, etc.):

1. **Google Cloud / Firebase:**
   - Use Cloud Secret Manager
   - Load secrets at runtime

2. **AWS:**
   - Use AWS Secrets Manager or Parameter Store
   - Set as environment variables in Lambda/EC2

3. **GitHub Actions:**
   - Store secrets in GitHub Settings > Secrets
   - Reference as `${{ secrets.MONGODB_URI }}`

## Steps Taken So Far

- ✅ Created `watched_apps_registry.dart` to consolidate app list
- ✅ Updated `DbService` with enhanced query methods
- ✅ Created MongoDB setup script with 200+ dummy events
- ❌ **TODO:** Update `db_service.dart` to use `.env` variables
- ❌ **TODO:** Create `.env.example` file
- ❌ **TODO:** Add `flutter_dotenv` to pubspec.yaml
- ❌ **TODO:** Rotate MongoDB credentials

## Important Security Notes

1. **Never commit `.env` files** - Add to `.gitignore`
2. **Rotate credentials immediately** after exposure
3. **Use strong passwords** (minimum 20 characters, mixed case + numbers + symbols)
4. **Enable MongoDB IP Whitelist** - only allow your server IPs
5. **Use connection string encryption** when possible
6. **Audit MongoDB access logs** for unauthorized access

## Reference

- [Flutter Dotenv Package](https://pub.dev/packages/flutter_dotenv)
- [MongoDB Security Best Practices](https://docs.mongodb.com/realm/security/)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
