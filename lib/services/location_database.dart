import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class LocationDatabase {
  static Database? _database;
  static const String _tableName = 'location_data';
  static const String _sessionTableName = 'location_sessions';
  static bool _isProcessing = false;

  // Initialize database
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Mutex to prevent concurrent database access
  static Future<T> _withMutex<T>(Future<T> Function() operation) async {
    // Simple mutex using a static boolean
    while (_isProcessing) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    
    _isProcessing = true;
    
    try {
      final result = await operation();
      return result;
    } finally {
      _isProcessing = false;
    }
  }

  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'location_data.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create location_data table
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        altitude REAL,
        speed REAL,
        heading REAL,
        timestamp INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Create location_sessions table
    await db.execute('''
      CREATE TABLE $_sessionTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT UNIQUE NOT NULL,
        user_id TEXT NOT NULL,
        client_id TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        metadata TEXT
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_location_session_id ON $_tableName(session_id)');
    await db.execute('CREATE INDEX idx_location_timestamp ON $_tableName(timestamp)');
    await db.execute('CREATE INDEX idx_session_user_id ON $_sessionTableName(user_id)');
    await db.execute('CREATE INDEX idx_session_active ON $_sessionTableName(is_active)');
  }

  // Save location data with transaction
  static Future<int> saveLocationData({
    required String sessionId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    double? heading,
    required int timestamp,
  }) async {
    return await _withMutex(() async {
      final db = await database;
      
      return await db.transaction((txn) async {
        return await txn.insert(_tableName, {
          'session_id': sessionId,
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'altitude': altitude,
          'speed': speed,
          'heading': heading,
          'timestamp': timestamp,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      });
    });
  }

  // Get location data for a session
  static Future<List<Map<String, dynamic>>> getLocationData(String sessionId, {int? limit}) async {
    final db = await database;
    
    String query = 'SELECT * FROM $_tableName WHERE session_id = ? ORDER BY timestamp DESC';
    List<dynamic> args = [sessionId];
    
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    
    return await db.rawQuery(query, args);
  }

  // Get latest location for a session
  static Future<Map<String, dynamic>?> getLatestLocation(String sessionId) async {
    final db = await database;
    
    final result = await db.query(
      _tableName,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    
    return result.isNotEmpty ? result.first : null;
  }

  // Create a new location session with transaction
  static Future<int> createSession({
    required String sessionId,
    required String userId,
    required String clientId,
    required String phoneNumber,
    String? metadata,
  }) async {
    return await _withMutex(() async {
      final db = await database;
      
      return await db.transaction((txn) async {
        return await txn.insert(_sessionTableName, {
          'session_id': sessionId,
          'user_id': userId,
          'client_id': clientId,
          'phone_number': phoneNumber,
          'is_active': 1,
          'started_at': DateTime.now().millisecondsSinceEpoch,
          'metadata': metadata,
        });
      });
    });
  }

  // End a location session
  static Future<int> endSession(String sessionId) async {
    final db = await database;
    
    return await db.update(
      _sessionTableName,
      {
        'is_active': 0,
        'ended_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // Get active session for a user
  static Future<Map<String, dynamic>?> getActiveSession(String userId) async {
    final db = await database;
    
    final result = await db.query(
      _sessionTableName,
      where: 'user_id = ? AND is_active = 1',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    
    return result.isNotEmpty ? result.first : null;
  }

  // Get all sessions for a user
  static Future<List<Map<String, dynamic>>> getUserSessions(String userId, {int? limit}) async {
    final db = await database;
    
    String query = 'SELECT * FROM $_sessionTableName WHERE user_id = ? ORDER BY started_at DESC';
    List<dynamic> args = [userId];
    
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    
    return await db.rawQuery(query, args);
  }

  // Get sessions for a specific user (alias for getUserSessions)
  static Future<List<Map<String, dynamic>>> getSessionsForUser(String userId) async {
    return await getUserSessions(userId);
  }

  // Get location data for a specific session
  static Future<List<Map<String, dynamic>>> getLocationDataForSession(String sessionId) async {
    return await getLocationData(sessionId);
  }

  // Delete old location data (cleanup)
  static Future<int> deleteOldLocationData({int daysOld = 30}) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(Duration(days: daysOld)).millisecondsSinceEpoch;
    
    return await db.delete(
      _tableName,
      where: 'created_at < ?',
      whereArgs: [cutoffTime],
    );
  }

  // Delete old sessions (cleanup)
  static Future<int> deleteOldSessions({int daysOld = 30}) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(Duration(days: daysOld)).millisecondsSinceEpoch;
    
    return await db.delete(
      _sessionTableName,
      where: 'started_at < ?',
      whereArgs: [cutoffTime],
    );
  }

  // Get database statistics
  static Future<Map<String, int>> getStats() async {
    final db = await database;
    
    final locationCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_tableName')
    ) ?? 0;
    
    final sessionCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_sessionTableName')
    ) ?? 0;
    
    final activeSessionCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $_sessionTableName WHERE is_active = 1')
    ) ?? 0;
    
    return {
      'location_records': locationCount,
      'total_sessions': sessionCount,
      'active_sessions': activeSessionCount,
    };
  }

  // Close database
  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}

