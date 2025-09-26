const express = require('express');
const { getFirestore, initializeFirebase } = require('../config/firebase');
const LocationService = require('../services/locationService');

const router = express.Router();
const locationService = new LocationService();

// Lazy initialization helper for Firestore
const getDb = () => {
  try {
    return getFirestore();
  } catch (error) {
    console.log('🔄 Firebase not initialized in routes, attempting to initialize...');
    initializeFirebase();
    return getFirestore();
  }
};

// Validation middleware
const validateLocationSharingRequest = (req, res, next) => {
  const { clientId, phoneNumber } = req.body;
  
  if (!clientId || !phoneNumber) {
    return res.status(400).json({
      error: 'Missing required fields',
      code: 'MISSING_FIELDS',
      message: 'clientId and phoneNumber are required',
      required: ['clientId', 'phoneNumber']
    });
  }

  // Validate phone number format
  const phoneRegex = /^tel:\+?94[0-9]{9}$/;
  if (!phoneRegex.test(phoneNumber)) {
    return res.status(400).json({
      error: 'Invalid phone number format',
      code: 'INVALID_PHONE',
      message: 'phoneNumber must be in tel: format (e.g., tel:+94712345678)'
    });
  }

  next();
};

// POST /api/location/start - Start location sharing
router.post('/start', validateLocationSharingRequest, async (req, res) => {
  try {
    const { clientId, phoneNumber, metadata = {} } = req.body;
    
    console.log(`🚀 [LOCATION API] Starting location sharing for client: ${clientId}`);
    console.log(`📱 Phone number: ${phoneNumber}`);

    // Generate unique session ID
    const sessionId = `session_${clientId}_${Date.now()}`;
    
    // Start location sharing (push-based, no client endpoint needed)
    const result = await locationService.startLocationSharing(
      sessionId,
      clientId,
      phoneNumber,
      {
        ...metadata,
        requestIP: req.ip,
        userAgent: req.get('User-Agent'),
        startedBy: req.body.startedBy || 'unknown'
      }
    );

    console.log(`✅ [LOCATION API] Location sharing started successfully: ${sessionId}`);

    res.status(201).json({
      success: true,
      message: 'Location sharing started successfully',
      data: {
        sessionId: result.sessionId,
        status: result.status,
        phoneNumber
      }
    });

  } catch (error) {
    console.error(`❌ [LOCATION API] Failed to start location sharing:`, error);
    
    res.status(500).json({
      error: 'Failed to start location sharing',
      code: 'START_FAILED',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// POST /api/location/stop - Stop location sharing
router.post('/stop', async (req, res) => {
  try {
    const { sessionId } = req.body;
    
    if (!sessionId) {
      return res.status(400).json({
        error: 'Missing sessionId',
        code: 'MISSING_SESSION_ID',
        message: 'sessionId is required to stop location sharing'
      });
    }

    console.log(`🛑 [LOCATION API] Stopping location sharing for session: ${sessionId}`);

    const result = await locationService.stopLocationSharing(sessionId);

    console.log(`✅ [LOCATION API] Location sharing stopped successfully: ${sessionId}`);

    res.json({
      success: true,
      message: 'Location sharing stopped successfully',
      data: {
        sessionId: result.sessionId,
        status: result.status
      }
    });

  } catch (error) {
    console.error(`❌ [LOCATION API] Failed to stop location sharing:`, error);
    
    res.status(500).json({
      error: 'Failed to stop location sharing',
      code: 'STOP_FAILED',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// GET /api/location/session/:sessionId - Get session details
router.get('/session/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    
    console.log(`📊 [LOCATION API] Getting session details for: ${sessionId}`);

    const db = getDb();
    const sessionDoc = await db.collection('location_sharing_sessions').doc(sessionId).get();

    if (!sessionDoc.exists) {
      return res.status(404).json({
        error: 'Session not found',
        code: 'SESSION_NOT_FOUND',
        message: `No session found with ID: ${sessionId}`
      });
    }

    const sessionData = sessionDoc.data();
    
    // Check if session is currently active
    const isActive = locationService.getActiveSessions().includes(sessionId);

    res.json({
      success: true,
      data: {
        ...sessionData,
        isActive,
        sessionId
      }
    });

  } catch (error) {
    console.error(`❌ [LOCATION API] Failed to get session details:`, error);
    
    res.status(500).json({
      error: 'Failed to get session details',
      code: 'GET_SESSION_FAILED',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// GET /api/location/history/:sessionId - Get location history for a session
router.get('/history/:sessionId', async (req, res) => {
  try {
    const { sessionId } = req.params;
    const { limit = 100 } = req.query;
    
    console.log(`📈 [LOCATION API] Getting location history for session: ${sessionId}`);

    const locationHistory = await locationService.getLocationHistory(sessionId, parseInt(limit));

    res.json({
      success: true,
      data: {
        sessionId,
        totalRecords: locationHistory.length,
        history: locationHistory
      }
    });

  } catch (error) {
    console.error(`❌ [LOCATION API] Failed to get location history:`, error);
    
    res.status(500).json({
      error: 'Failed to get location history',
      code: 'GET_HISTORY_FAILED',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// GET /api/location/sessions - Get all active sessions
router.get('/sessions', async (req, res) => {
  try {
    console.log(`📋 [LOCATION API] Getting all active sessions`);

    const activeSessions = locationService.getActiveSessions();
    
    // Get detailed session information from database
    const db = getDb();
    const sessionsData = [];
    
    for (const sessionId of activeSessions) {
      try {
        const sessionDoc = await db.collection('location_sharing_sessions').doc(sessionId).get();
        if (sessionDoc.exists) {
          sessionsData.push({
            sessionId,
            ...sessionDoc.data()
          });
        }
      } catch (error) {
        console.warn(`⚠️ [LOCATION API] Failed to get data for session ${sessionId}:`, error.message);
      }
    }

    res.json({
      success: true,
      data: {
        activeSessions: activeSessions,
        totalActive: activeSessions.length,
        sessionsData: sessionsData
      }
    });

  } catch (error) {
    console.error(`❌ [LOCATION API] Failed to get active sessions:`, error);
    
    res.status(500).json({
      error: 'Failed to get active sessions',
      code: 'GET_SESSIONS_FAILED',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// POST /api/location/update - Receive location update from client
router.post('/update', async (req, res) => {
  try {
    const { sessionId, locationData } = req.body;
    
    if (!sessionId) {
      return res.status(400).json({
        error: 'Missing sessionId',
        code: 'MISSING_SESSION_ID',
        message: 'sessionId is required'
      });
    }

    if (!locationData) {
      return res.status(400).json({
        error: 'Missing locationData',
        code: 'MISSING_LOCATION_DATA',
        message: 'locationData is required'
      });
    }

    console.log(`📍 [LOCATION API] Receiving location update for session: ${sessionId}`);

    // Receive location update from client
    const result = await locationService.receiveLocationUpdate(sessionId, locationData);

    res.json({
      success: true,
      message: 'Location update received successfully',
      data: {
        sessionId,
        timestamp: new Date().toISOString()
      }
    });

  } catch (error) {
    console.error(`❌ [LOCATION API] Failed to receive location update:`, error);
    
    res.status(400).json({
      error: 'Failed to receive location update',
      code: 'UPDATE_FAILED',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Health check for location service
router.get('/health', (req, res) => {
  const activeSessions = locationService.getActiveSessions();
  
  res.json({
    success: true,
    service: 'Location Service',
    status: 'healthy',
    data: {
      activeSessions: activeSessions.length,
      pollingInterval: locationService.pollingIntervalMs,
      clientTimeout: locationService.clientTimeoutMs,
      maxRetries: locationService.maxRetries,
      timestamp: new Date().toISOString()
    }
  });
});

module.exports = router;
