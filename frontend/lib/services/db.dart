import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseProvider {
  DatabaseProvider._();
  static final DatabaseProvider instance = DatabaseProvider._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'app.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            is_verified INTEGER DEFAULT 0,
            verification_code TEXT,
            created_at INTEGER DEFAULT 0
          );
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add new columns to existing users table
          await db.execute('ALTER TABLE users ADD COLUMN is_verified INTEGER DEFAULT 0');
          await db.execute('ALTER TABLE users ADD COLUMN verification_code TEXT');
          await db.execute('ALTER TABLE users ADD COLUMN created_at INTEGER DEFAULT 0');
        }
      },
    );
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _generateVerificationCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<Map<String, dynamic>> createUser({required String email, required String password}) async {
    final db = await database;
    try {
      final verificationCode = _generateVerificationCode();
      final hashedPassword = _hashPassword(password);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await db.insert('users', {
        'email': email.trim().toLowerCase(),
        'password': hashedPassword,
        'is_verified': 0,
        'verification_code': verificationCode,
        'created_at': now,
      });
      
      return {
        'success': true,
        'verification_code': verificationCode,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> validateUser({required String email, required String password}) async {
    final db = await database;
    final hashedPassword = _hashPassword(password);
    final rows = await db.query(
      'users',
      where: 'email = ? AND password = ?',
      whereArgs: [email.trim().toLowerCase(), hashedPassword],
      limit: 1,
    );
    
    if (rows.isEmpty) {
      return {'success': false, 'error': 'Invalid credentials'};
    }
    
    final user = rows.first;
    final isVerified = user['is_verified'] == 1;
    
    if (!isVerified) {
      return {'success': false, 'error': 'Email not verified', 'needs_verification': true};
    }
    
    return {'success': true, 'user_id': user['id']};
  }

  Future<bool> verifyEmail({required String email, required String code}) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'email = ? AND verification_code = ?',
      whereArgs: [email.trim().toLowerCase(), code],
      limit: 1,
    );
    
    if (rows.isEmpty) return false;
    
    await db.update(
      'users',
      {'is_verified': 1, 'verification_code': null},
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
    );
    
    return true;
  }

  // Session Management
  Future<void> saveSession({required String email, required int userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionData = {
      'email': email,
      'user_id': userId,
      'login_time': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString('user_session', jsonEncode(sessionData));
  }

  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionString = prefs.getString('user_session');
    
    if (sessionString == null) return null;
    
    try {
      final sessionData = jsonDecode(sessionString) as Map<String, dynamic>;
      final loginTime = sessionData['login_time'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      final daysSinceLogin = (now - loginTime) / (1000 * 60 * 60 * 24);
      
      if (daysSinceLogin > 3) {
        await clearSession();
        return null;
      }
      
      return sessionData;
    } catch (e) {
      await clearSession();
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_session');
  }

  // Preferences Management
  Future<void> savePreferences(Map<String, dynamic> preferences) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in preferences.entries) {
      if (entry.value is bool) {
        await prefs.setBool(entry.key, entry.value);
      } else if (entry.value is String) {
        await prefs.setString(entry.key, entry.value);
      } else if (entry.value is int) {
        await prefs.setInt(entry.key, entry.value);
      } else if (entry.value is double) {
        await prefs.setDouble(entry.key, entry.value);
      }
    }
  }

  Future<Map<String, dynamic>> getPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isDarkTheme': prefs.getBool('isDarkTheme') ?? false,
      'dataCollectionEnabled': prefs.getBool('dataCollectionEnabled') ?? false,
      'locationTrackingEnabled': prefs.getBool('locationTrackingEnabled') ?? true,
      'sensorDataEnabled': prefs.getBool('sensorDataEnabled') ?? false,
    };
  }

  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    // Clear database
    final db = await database;
    await db.delete('users');
  }
}


