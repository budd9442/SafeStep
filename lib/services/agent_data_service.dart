import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'local_session.dart';

class AgentDataService {
  static Database? _database;
  static StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  static StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  static StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  
  static const String _tableName = 'agent_data';
  static const int _dataRetentionMinutes = 10;
  
  // Initialize database
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'agent_data.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Create agent_data table
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        data_type TEXT NOT NULL,
        data_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_agent_timestamp ON $_tableName(timestamp)');
    await db.execute('CREATE INDEX idx_agent_data_type ON $_tableName(data_type)');
    await db.execute('CREATE INDEX idx_agent_created_at ON $_tableName(created_at)');
  }

  // Start collecting all sensor data
  static Future<void> startDataCollection() async {
    print('🚀 [AGENT DATA] Starting comprehensive data collection');
    
    // Start accelerometer data collection
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      _saveSensorData('accelerometer', {
        'x': event.x,
        'y': event.y,
        'z': event.z,
        'magnitude': sqrt(event.x * event.x + event.y * event.y + event.z * event.z),
      });
    });

    // Start gyroscope data collection
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      _saveSensorData('gyroscope', {
        'x': event.x,
        'y': event.y,
        'z': event.z,
        'magnitude': sqrt(event.x * event.x + event.y * event.y + event.z * event.z),
      });
    });

    // Start magnetometer data collection
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      _saveSensorData('magnetometer', {
        'x': event.x,
        'y': event.y,
        'z': event.z,
        'magnitude': sqrt(event.x * event.x + event.y * event.y + event.z * event.z),
      });
    });

    print('✅ [AGENT DATA] Sensor data collection started');
  }

  // Stop collecting sensor data
  static Future<void> stopDataCollection() async {
    print('🛑 [AGENT DATA] Stopping data collection');
    
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _magnetometerSubscription?.cancel();
    
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _magnetometerSubscription = null;
    
    print('✅ [AGENT DATA] Data collection stopped');
  }

  // Save sensor data to database
  static Future<void> _saveSensorData(String dataType, Map<String, dynamic> data) async {
    try {
      final db = await database;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      await db.insert(_tableName, {
        'timestamp': timestamp,
        'data_type': dataType,
        'data_json': jsonEncode(data),
        'created_at': timestamp,
      });
    } catch (e) {
      print('❌ [AGENT DATA] Error saving sensor data: $e');
    }
  }

  // Get comprehensive data for AI agent (optimized for smaller payload)
  static Future<Map<String, dynamic>> getComprehensiveData() async {
    try {
      print('📊 [AGENT DATA] Collecting essential data for AI agent');
      
      // Get current location
      final locationData = await _getCurrentLocationData();
      
      // Get nearby safe places (limited to 3 closest)
      final safePlacesData = await _getNearbySafePlaces(locationData);
      
      // Get essential sensor data (summary only)
      final sensorData = await _getEssentialSensorData();
      
      // Get user context (essential info only)
      final userContext = await _getEssentialUserContext();
      
      final essentialData = {
        'location': locationData,
        'nearby_safe_places': safePlacesData.take(3).toList(), // Limit to 3
        'sensor_data': sensorData,
        'user_context': userContext,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      print('✅ [AGENT DATA] Essential data collected successfully');
      return essentialData;
      
    } catch (e) {
      print('❌ [AGENT DATA] Error collecting essential data: $e');
      return {
        'error': 'Failed to collect essential data: ${e.toString()}',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  // Get current location data
  static Future<Map<String, dynamic>> _getCurrentLocationData() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );
      
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      };
    } catch (e) {
      return {
        'error': 'Failed to get location: ${e.toString()}',
        'location_permission_status': await Geolocator.checkPermission().toString(),
      };
    }
  }

  // Get nearby safe places
  static Future<List<Map<String, dynamic>>> _getNearbySafePlaces(Map<String, dynamic> locationData) async {
    try {
      if (locationData.containsKey('error')) {
        return [];
      }
      
      // Query Firestore for nearby safe places
      final db = FirebaseFirestore.instance;
      final safePlaces = <Map<String, dynamic>>[];
      
      // Get police stations within 5km
      final policeQuery = await db.collection('safe_places')
          .where('type', isEqualTo: 'police_station')
          .limit(10)
          .get();
      
      for (final doc in policeQuery.docs) {
        final data = doc.data();
        final distance = _calculateDistance(
          locationData['latitude'],
          locationData['longitude'],
          data['latitude'],
          data['longitude'],
        );
        
        if (distance <= 5.0) { // Within 5km
          safePlaces.add({
            'type': 'police_station',
            'name': data['name'],
            'distance_km': distance,
          });
        }
      }
      
      // Get hospitals within 10km
      final hospitalQuery = await db.collection('safe_places')
          .where('type', isEqualTo: 'hospital')
          .limit(10)
          .get();
      
      for (final doc in hospitalQuery.docs) {
        final data = doc.data();
        final distance = _calculateDistance(
          locationData['latitude'],
          locationData['longitude'],
          data['latitude'],
          data['longitude'],
        );
        
        if (distance <= 10.0) { // Within 10km
          safePlaces.add({
            'type': 'hospital',
            'name': data['name'],
            'distance_km': distance,
          });
        }
      }
      
      // Sort by distance
      safePlaces.sort((a, b) => (a['distance_km'] as double).compareTo(b['distance_km'] as double));
      
      return safePlaces.take(5).toList(); // Return top 5 closest
      
    } catch (e) {
      print('❌ [AGENT DATA] Error getting nearby safe places: $e');
      return [];
    }
  }

  // Calculate distance between two points
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000; // Convert to km
  }

  // Get essential sensor data (summary only)
  static Future<Map<String, dynamic>> _getEssentialSensorData() async {
    try {
      final now = DateTime.now();
      final cutoffTime = now.subtract(Duration(minutes: _dataRetentionMinutes)).millisecondsSinceEpoch;
      
      final db = await database;
      
      // Get accelerometer data (last 50 readings only)
      final accelerometerData = await db.query(
        _tableName,
        where: 'data_type = ? AND timestamp >= ?',
        whereArgs: ['accelerometer', cutoffTime],
        orderBy: 'timestamp DESC',
        limit: 50, // Reduced from 100
      );
      
      if (accelerometerData.isEmpty) {
        return {'status': 'no_data'};
      }
      
      // Quick analysis
      final magnitudes = accelerometerData.map((e) {
        final sensorData = jsonDecode(e['data_json'] as String);
        return sensorData['magnitude'] as double;
      }).toList();
      
      final avgMagnitude = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
      final maxMagnitude = magnitudes.reduce((a, b) => a > b ? a : b);
      
      // Detect movement pattern
      final highMovementCount = magnitudes.where((m) => m > 15.0).length;
      final lowMovementCount = magnitudes.where((m) => m < 5.0).length;
      
      String movementPattern = 'normal';
      Map<String, bool> indicators = {};
      
      if (highMovementCount > 10) {
        movementPattern = 'high_activity';
        indicators['possible_running'] = avgMagnitude > 12.0;
      } else if (lowMovementCount > 50) {
        movementPattern = 'low_activity';
        indicators['possible_stationary'] = avgMagnitude < 6.0;
      }
      
      indicators['possible_fall'] = maxMagnitude > 25.0;
      
      return {
        'accelerometer': {
          'movement_pattern': movementPattern,
          'average_magnitude': avgMagnitude,
          'max_magnitude': maxMagnitude,
          'potential_indicators': indicators,
        },
      };
      
    } catch (e) {
      print('❌ [AGENT DATA] Error getting essential sensor data: $e');
      return {'error': 'Failed to get sensor data: ${e.toString()}'};
    }
  }

  // Get essential user context (minimal info)
  static Future<Map<String, dynamic>> _getEssentialUserContext() async {
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null) {
        return {'status': 'not_authenticated'};
      }
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(localUserId)
          .get();
      
      if (!userDoc.exists) {
        return {'status': 'user_not_found'};
      }
      
      final userData = userDoc.data()!;
      
      return {
        'name': userData['name'],
        'is_sharing_location': userData['sharingLocation'] ?? false,
        'emergency_contacts_count': (userData['emergencyContacts'] as List?)?.length ?? 0,
      };
      
    } catch (e) {
      return {
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  // Get sensor data from database
  static Future<Map<String, dynamic>> _getSensorData(int cutoffTime) async {
    try {
      final db = await database;
      
      // Get accelerometer data
      final accelerometerData = await db.query(
        _tableName,
        where: 'data_type = ? AND timestamp >= ?',
        whereArgs: ['accelerometer', cutoffTime],
        orderBy: 'timestamp DESC',
        limit: 100, // Last 100 readings
      );
      
      // Get gyroscope data
      final gyroscopeData = await db.query(
        _tableName,
        where: 'data_type = ? AND timestamp >= ?',
        whereArgs: ['gyroscope', cutoffTime],
        orderBy: 'timestamp DESC',
        limit: 100,
      );
      
      // Get magnetometer data
      final magnetometerData = await db.query(
        _tableName,
        where: 'data_type = ? AND timestamp >= ?',
        whereArgs: ['magnetometer', cutoffTime],
        orderBy: 'timestamp DESC',
        limit: 100,
      );
      
      // Process and analyze sensor data
      final accelerometerAnalysis = _analyzeAccelerometerData(accelerometerData);
      final gyroscopeAnalysis = _analyzeGyroscopeData(gyroscopeData);
      final magnetometerAnalysis = _analyzeMagnetometerData(magnetometerData);
      
      return {
        'accelerometer': {
          'raw_data_count': accelerometerData.length,
          'analysis': accelerometerAnalysis,
          'recent_readings': accelerometerData.take(10).map((e) => jsonDecode(e['data_json'] as String)).toList(),
        },
        'gyroscope': {
          'raw_data_count': gyroscopeData.length,
          'analysis': gyroscopeAnalysis,
          'recent_readings': gyroscopeData.take(10).map((e) => jsonDecode(e['data_json'] as String)).toList(),
        },
        'magnetometer': {
          'raw_data_count': magnetometerData.length,
          'analysis': magnetometerAnalysis,
          'recent_readings': magnetometerData.take(10).map((e) => jsonDecode(e['data_json'] as String)).toList(),
        },
        'data_period_minutes': _dataRetentionMinutes,
      };
      
    } catch (e) {
      print('❌ [AGENT DATA] Error getting sensor data: $e');
      return {
        'error': 'Failed to get sensor data: ${e.toString()}',
      };
    }
  }

  // Analyze accelerometer data for patterns
  static Map<String, dynamic> _analyzeAccelerometerData(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return {'status': 'no_data'};
    }
    
    final magnitudes = data.map((e) {
      final sensorData = jsonDecode(e['data_json']);
      return sensorData['magnitude'] as double;
    }).toList();
    
    final avgMagnitude = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final maxMagnitude = magnitudes.reduce((a, b) => a > b ? a : b);
    final minMagnitude = magnitudes.reduce((a, b) => a < b ? a : b);
    
    // Detect potential movement patterns
    final highMovementCount = magnitudes.where((m) => m > 15.0).length;
    final lowMovementCount = magnitudes.where((m) => m < 5.0).length;
    
    return {
      'average_magnitude': avgMagnitude,
      'max_magnitude': maxMagnitude,
      'min_magnitude': minMagnitude,
      'high_movement_readings': highMovementCount,
      'low_movement_readings': lowMovementCount,
      'movement_pattern': highMovementCount > 10 ? 'high_activity' : 
                         lowMovementCount > 50 ? 'low_activity' : 'normal',
      'potential_indicators': {
        'possible_fall': maxMagnitude > 25.0,
        'possible_running': avgMagnitude > 12.0 && highMovementCount > 20,
        'possible_stationary': avgMagnitude < 6.0 && lowMovementCount > 30,
      },
    };
  }

  // Analyze gyroscope data
  static Map<String, dynamic> _analyzeGyroscopeData(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return {'status': 'no_data'};
    }
    
    final rotations = data.map((e) {
      final sensorData = jsonDecode(e['data_json']);
      return sensorData['magnitude'] as double;
    }).toList();
    
    final avgRotation = rotations.reduce((a, b) => a + b) / rotations.length;
    final maxRotation = rotations.reduce((a, b) => a > b ? a : b);
    
    return {
      'average_rotation': avgRotation,
      'max_rotation': maxRotation,
      'rotation_pattern': avgRotation > 2.0 ? 'high_rotation' : 'low_rotation',
      'potential_indicators': {
        'possible_spinning': maxRotation > 5.0,
        'possible_turning': avgRotation > 1.0,
      },
    };
  }

  // Analyze magnetometer data
  static Map<String, dynamic> _analyzeMagnetometerData(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return {'status': 'no_data'};
    }
    
    final magneticFields = data.map((e) {
      final sensorData = jsonDecode(e['data_json']);
      return sensorData['magnitude'] as double;
    }).toList();
    
    final avgField = magneticFields.reduce((a, b) => a + b) / magneticFields.length;
    final maxField = magneticFields.reduce((a, b) => a > b ? a : b);
    
    return {
      'average_magnetic_field': avgField,
      'max_magnetic_field': maxField,
      'field_stability': maxField - avgField < 10.0 ? 'stable' : 'variable',
    };
  }

  // Get time and context data
  static Map<String, dynamic> _getTimeData() {
    final now = DateTime.now();
    
    return {
      'current_time': now.toIso8601String(),
      'timezone': now.timeZoneName,
      'hour': now.hour,
      'day_of_week': now.weekday,
      'is_weekend': now.weekday == DateTime.saturday || now.weekday == DateTime.sunday,
      'is_night': now.hour >= 22 || now.hour <= 6,
      'is_evening': now.hour >= 17 && now.hour < 22,
      'is_morning': now.hour >= 6 && now.hour < 12,
      'is_afternoon': now.hour >= 12 && now.hour < 17,
      'season_context': _getSeasonContext(now),
    };
  }

  // Get season context
  static String _getSeasonContext(DateTime date) {
    final month = date.month;
    if (month >= 3 && month <= 5) return 'spring';
    if (month >= 6 && month <= 8) return 'summer';
    if (month >= 9 && month <= 11) return 'autumn';
    return 'winter';
  }

  // Get user context
  static Future<Map<String, dynamic>> _getUserContext() async {
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null) {
        return {'status': 'not_authenticated'};
      }
      
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(localUserId)
          .get();
      
      if (!userDoc.exists) {
        return {'status': 'user_not_found'};
      }
      
      final userData = userDoc.data()!;
      
      return {
        'user_id': localUserId,
        'name': userData['name'],
        'phone_number': userData['phoneNumber'],
        'is_sharing_location': userData['sharingLocation'] ?? false,
        'profile_completion': userData['profileCompletion'] ?? 0,
        'last_known_location': userData['lastKnownLocation'],
        'emergency_contacts_count': (userData['emergencyContacts'] as List?)?.length ?? 0,
      };
      
    } catch (e) {
      return {
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  // Clean up old data
  static Future<void> cleanupOldData() async {
    try {
      final db = await database;
      final cutoffTime = DateTime.now()
          .subtract(Duration(minutes: _dataRetentionMinutes + 5))
          .millisecondsSinceEpoch;
      
      final deletedRows = await db.delete(
        _tableName,
        where: 'created_at < ?',
        whereArgs: [cutoffTime],
      );
      
      print('🧹 [AGENT DATA] Cleaned up $deletedRows old data records');
      
    } catch (e) {
      print('❌ [AGENT DATA] Error cleaning up old data: $e');
    }
  }

  // Close database
  static Future<void> close() async {
    await stopDataCollection();
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
