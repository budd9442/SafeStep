const axios = require('axios');
const { getFirestore, initializeFirebase, admin } = require('../config/firebase');

class LocationService {
  constructor() {
    this.db = null;
    this.activeSessions = new Map(); // Track active sharing sessions
    this.pollingIntervals = new Map(); // Track polling intervals for cleanup
    this.pollingIntervalMs = 10000; // 10 seconds
    this.clientTimeoutMs = 5000; // 5 seconds timeout for client requests
    this.maxRetries = 3; // Maximum retries for failed requests
  }

  // Lazy initialization of Firestore
  getDb() {
    if (!this.db) {
      try {
        this.db = getFirestore();
      } catch (error) {
        console.log('🔄 Firebase not initialized, attempting to initialize...');
        initializeFirebase();
        this.db = getFirestore();
      }
    }
    return this.db;
  }

  /**
   * Start location sharing for a client
   * @param {string} sessionId - Unique session identifier
   * @param {string} clientId - Client identifier
   * @param {string} phoneNumber - Client's phone number for mspace fallback
   * @param {Object} metadata - Additional session metadata
   */
  async startLocationSharing(sessionId, clientId, phoneNumber, metadata = {}) {
    try {
      console.log(`🚀 [LOCATION SERVICE] Starting location sharing for session: ${sessionId}`);
      
      // Create sharing session in database
      const sessionData = {
        sessionId,
        clientId,
        phoneNumber,
        status: 'active',
        startedAt: new Date(),
        lastLocationUpdate: null,
        totalLocationUpdates: 0,
        failedAttempts: 0,
        metadata: {
          ...metadata,
          createdAt: new Date(),
          updatedAt: new Date()
        }
      };

      await this.getDb().collection('location_sharing_sessions').doc(sessionId).set(sessionData);
      
      // Store session info in memory for quick access
      this.activeSessions.set(sessionId, {
        clientId,
        phoneNumber,
        metadata
      });

      console.log(`✅ [LOCATION SERVICE] Location sharing started for session: ${sessionId}`);
      return { success: true, sessionId, status: 'active' };
      
    } catch (error) {
      console.error(`❌ [LOCATION SERVICE] Failed to start location sharing:`, error);
      throw error;
    }
  }

  /**
   * Stop location sharing for a session
   * @param {string} sessionId - Session identifier to stop
   */
  async stopLocationSharing(sessionId) {
    try {
      console.log(`🛑 [LOCATION SERVICE] Stopping location sharing for session: ${sessionId}`);
      
      // Remove from active sessions
      this.activeSessions.delete(sessionId);

      // Update session status in database
      await this.getDb().collection('location_sharing_sessions').doc(sessionId).update({
        status: 'stopped',
        stoppedAt: new Date(),
        updatedAt: new Date()
      });

      console.log(`✅ [LOCATION SERVICE] Location sharing stopped for session: ${sessionId}`);
      return { success: true, sessionId, status: 'stopped' };
      
    } catch (error) {
      console.error(`❌ [LOCATION SERVICE] Failed to stop location sharing:`, error);
      throw error;
    }
  }

  /**
   * Receive location update from client (push-based)
   * @param {string} sessionId - Session identifier
   * @param {Object} locationData - Location data from client
   */
  async receiveLocationUpdate(sessionId, locationData) {
    try {
      console.log(`📍 [LOCATION SERVICE] Receiving location update for session: ${sessionId}`);
      
      // Validate session exists and is active
      const session = this.activeSessions.get(sessionId);
      if (!session) {
        throw new Error(`Session ${sessionId} not found or not active`);
      }

      // Validate location data
      if (!locationData.latitude || !locationData.longitude) {
        throw new Error('Invalid location data: missing latitude or longitude');
      }

      // Save location data to database
      await this.saveLocationData(sessionId, locationData, 'client');
      
      console.log(`✅ [LOCATION SERVICE] Location update received and saved for session: ${sessionId}`);
      return { success: true, message: 'Location update received successfully' };
      
    } catch (error) {
      console.error(`❌ [LOCATION SERVICE] Failed to receive location update:`, error);
      throw error;
    }
  }

  /**
   * Fallback: Fetch location from mspace API when client is unreachable
   * @param {string} phoneNumber - Phone number for mspace lookup
   * @param {string} sessionId - Session identifier for logging
   */
  async fetchFromMspace(phoneNumber, sessionId) {
    try {
      console.log(`🛰️ [LOCATION SERVICE] Fetching from mspace for phone: ${phoneNumber}`);
      
      // TODO: Implement actual mspace API call
      // This is a placeholder implementation
      const mspaceEndpoint = process.env.MSPACE_API_ENDPOINT || 'https://api.mspace.lk/location';
      
      const response = await axios.post(mspaceEndpoint, {
        phoneNumber: phoneNumber,
        requestId: sessionId,
        timestamp: new Date().toISOString()
      }, {
        timeout: this.clientTimeoutMs,
        headers: {
          'Authorization': `Bearer ${process.env.MSPACE_API_KEY}`,
          'Content-Type': 'application/json'
        }
      });

      if (response.status === 200 && response.data) {
        const locationData = {
          latitude: response.data.latitude,
          longitude: response.data.longitude,
          accuracy: response.data.accuracy || null,
          timestamp: response.data.timestamp || new Date(),
          altitude: response.data.altitude || null,
          speed: response.data.speed || null,
          heading: response.data.heading || null,
          source: 'mspace'
        };

        // Validate required fields
        if (locationData.latitude && locationData.longitude) {
          return locationData;
        } else {
          throw new Error('Invalid mspace location data: missing latitude or longitude');
        }
      } else {
        throw new Error(`Mspace API returned status ${response.status}`);
      }
      
    } catch (error) {
      console.error(`❌ [LOCATION SERVICE] Mspace API error:`, error.message);
      throw error;
    }
  }

  /**
   * Save location data to database
   * @param {string} sessionId - Session identifier
   * @param {Object} locationData - Location data to save
   * @param {string} source - Source of location data ('client' or 'mspace')
   */
  async saveLocationData(sessionId, locationData, source) {
    try {
      const locationRecord = {
        sessionId,
        ...locationData,
        source,
        receivedAt: new Date(),
        id: `${sessionId}_${Date.now()}`
      };

      // Save individual location record
      await this.getDb().collection('location_data').add(locationRecord);

      // Update session with latest location info
      await this.getDb().collection('location_sharing_sessions').doc(sessionId).update({
        lastLocationUpdate: new Date(),
        lastLocationData: locationData,
        totalLocationUpdates: admin.firestore.FieldValue.increment(1),
        failedAttempts: 0, // Reset failed attempts on successful update
        updatedAt: new Date()
      });

      console.log(`💾 [LOCATION SERVICE] Location data saved for session: ${sessionId} from ${source}`);
      
    } catch (error) {
      console.error(`❌ [LOCATION SERVICE] Failed to save location data:`, error);
      throw error;
    }
  }

  /**
   * Get location history for a session
   * @param {string} sessionId - Session identifier
   * @param {number} limit - Maximum number of records to return
   */
  async getLocationHistory(sessionId, limit = 100) {
    try {
      const query = await this.getDb().collection('location_data')
        .where('sessionId', '==', sessionId)
        .limit(limit)
        .get();

      const locationHistory = [];
      query.forEach(doc => {
        locationHistory.push({
          id: doc.id,
          ...doc.data()
        });
      });

      // Sort by receivedAt descending (client-side sorting to avoid index requirement)
      locationHistory.sort((a, b) => {
        const aTime = a.receivedAt?.toDate?.() || new Date(a.receivedAt);
        const bTime = b.receivedAt?.toDate?.() || new Date(b.receivedAt);
        return bTime - aTime;
      });

      return locationHistory;
      
    } catch (error) {
      console.error(`❌ [LOCATION SERVICE] Failed to get location history:`, error);
      throw error;
    }
  }

  /**
   * Get active sessions
   */
  getActiveSessions() {
    return Array.from(this.activeSessions.keys());
  }

  /**
   * Cleanup all sessions (for graceful shutdown)
   */
  async cleanup() {
    console.log(`🧹 [LOCATION SERVICE] Cleaning up all active sessions`);
    
    const activeSessionIds = Array.from(this.activeSessions.keys());
    
    for (const sessionId of activeSessionIds) {
      try {
        await this.stopLocationSharing(sessionId);
      } catch (error) {
        console.error(`❌ [LOCATION SERVICE] Failed to cleanup session ${sessionId}:`, error);
      }
    }
    
    console.log(`✅ [LOCATION SERVICE] Cleanup completed`);
  }
}

module.exports = LocationService;