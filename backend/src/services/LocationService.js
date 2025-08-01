const MSpaceService = require('./MSpaceService');
const { Pool } = require('pg');

class LocationService {
  constructor() {
    this.mspaceService = new MSpaceService();
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
    });
  }

  // Update user location from app
  async updateUserLocation(userId, latitude, longitude, accuracy = null) {
    try {
      const query = `
        INSERT INTO user_locations (user_id, latitude, longitude, accuracy, timestamp, source)
        VALUES ($1, $2, $3, $4, NOW(), 'app')
        ON CONFLICT (user_id) 
        DO UPDATE SET 
          latitude = $2, 
          longitude = $3, 
          accuracy = $4, 
          timestamp = NOW()
      `;
      
      await this.pool.query(query, [userId, latitude, longitude, accuracy]);
      
      // Update user's online status
      await this.pool.query(`
        UPDATE users 
        SET is_online = true, last_seen = NOW() 
        WHERE id = $1
      `, [userId]);

      return { success: true, message: 'Location updated successfully' };
    } catch (error) {
      console.error('Error updating user location:', error);
      throw new Error('Failed to update location');
    }
  }

  // Get user's current location
  async getUserLocation(userId) {
    try {
      const query = `
        SELECT latitude, longitude, accuracy, timestamp, source
        FROM user_locations 
        WHERE user_id = $1 
        ORDER BY timestamp DESC 
        LIMIT 1
      `;
      
      const result = await this.pool.query(query, [userId]);
      
      if (result.rows.length === 0) {
        return null;
      }
      
      return result.rows[0];
    } catch (error) {
      console.error('Error getting user location:', error);
      throw new Error('Failed to get user location');
    }
  }

  // Start location sharing
  async startLocationSharing(userId, contactIds, duration = '1h') {
    try {
      let expiresAt = null;
      
      if (duration === '1h') {
        expiresAt = new Date(Date.now() + 60 * 60 * 1000);
      } else if (duration === '8h') {
        expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000);
      }
      // 'always' means no expiration

      const query = `
        INSERT INTO location_sharing_sessions (user_id, contact_ids, duration, is_active, expires_at)
        VALUES ($1, $2, $3, true, $4)
        ON CONFLICT (user_id) 
        DO UPDATE SET 
          contact_ids = $2,
          duration = $3,
          is_active = true,
          expires_at = $4,
          updated_at = NOW()
      `;
      
      await this.pool.query(query, [userId, contactIds, duration, expiresAt]);
      
      return { success: true, message: 'Location sharing started' };
    } catch (error) {
      console.error('Error starting location sharing:', error);
      throw new Error('Failed to start location sharing');
    }
  }

  // Stop location sharing
  async stopLocationSharing(userId) {
    try {
      const query = `
        UPDATE location_sharing_sessions 
        SET is_active = false, updated_at = NOW()
        WHERE user_id = $1
      `;
      
      await this.pool.query(query, [userId]);
      
      return { success: true, message: 'Location sharing stopped' };
    } catch (error) {
      console.error('Error stopping location sharing:', error);
      throw new Error('Failed to stop location sharing');
    }
  }

  // Get shared locations for a user
  async getSharedLocations(userId) {
    try {
      const query = `
        SELECT lss.*, u.name as user_name, u.phone_number
        FROM location_sharing_sessions lss
        JOIN users u ON lss.user_id = u.id
        WHERE $1 = ANY(lss.contact_ids) AND lss.is_active = true
        AND (lss.expires_at IS NULL OR lss.expires_at > NOW())
      `;
      
      const result = await this.pool.query(query, [userId]);
      
      // Get current locations for each shared user
      const sharedLocations = [];
      
      for (const session of result.rows) {
        const location = await this.getUserLocation(session.user_id);
        if (location) {
          sharedLocations.push({
            ...session,
            currentLocation: location
          });
        }
      }
      
      return sharedLocations;
    } catch (error) {
      console.error('Error getting shared locations:', error);
      throw new Error('Failed to get shared locations');
    }
  }

  // Request location via mSpace for offline users
  async requestLocationViaMSpace(requesterId, subscriberId) {
    try {
      // Check if user is online first
      const userQuery = `
        SELECT is_online, last_seen 
        FROM users 
        WHERE id = $1
      `;
      
      const userResult = await this.pool.query(userQuery, [subscriberId]);
      
      if (userResult.rows.length === 0) {
        throw new Error('User not found');
      }
      
      const user = userResult.rows[0];
      const lastSeen = new Date(user.last_seen);
      const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
      
      // If user is online and seen recently, don't use mSpace
      if (user.is_online && lastSeen > fiveMinutesAgo) {
        return { 
          success: true, 
          message: 'User is online, use app location',
          source: 'app'
        };
      }
      
      // Get user's phone number
      const phoneQuery = `
        SELECT phone_number 
        FROM users 
        WHERE id = $1
      `;
      
      const phoneResult = await this.pool.query(phoneQuery, [subscriberId]);
      const requesterPhoneResult = await this.pool.query(phoneQuery, [requesterId]);
      
      if (phoneResult.rows.length === 0 || requesterPhoneResult.rows.length === 0) {
        throw new Error('Phone number not found');
      }
      
      const subscriberPhone = phoneResult.rows[0].phone_number;
      const requesterPhone = requesterPhoneResult.rows[0].phone_number;
      
      // Request location via mSpace
      const mspaceResult = await this.mspaceService.requestLocation(
        requesterPhone, 
        subscriberPhone
      );
      
      // Store the location request
      const insertQuery = `
        INSERT INTO mspace_location_requests 
        (requester_id, subscriber_id, mspace_message_id, status, latitude, longitude, timestamp)
        VALUES ($1, $2, $3, 'COMPLETED', $4, $5, $6)
      `;
      
      await this.pool.query(insertQuery, [
        requesterId,
        subscriberId,
        mspaceResult.messageID,
        mspaceResult.latitude,
        mspaceResult.longitude,
        mspaceResult.timestamp
      ]);
      
      // Also store as user location
      await this.pool.query(`
        INSERT INTO user_locations (user_id, latitude, longitude, timestamp, source)
        VALUES ($1, $2, $3, $4, 'mspace')
      `, [subscriberId, mspaceResult.latitude, mspaceResult.longitude, mspaceResult.timestamp]);
      
      return {
        success: true,
        location: {
          latitude: mspaceResult.latitude,
          longitude: mspaceResult.longitude,
          timestamp: mspaceResult.timestamp,
          subscriberState: mspaceResult.subscriberState
        },
        source: 'mspace'
      };
    } catch (error) {
      console.error('Error requesting location via mSpace:', error);
      throw new Error(`Failed to request location: ${error.message}`);
    }
  }

  // Get location for a user (app or mSpace)
  async getLocationForUser(requesterId, targetUserId) {
    try {
      // First try to get from app
      const appLocation = await this.getUserLocation(targetUserId);
      
      if (appLocation && appLocation.source === 'app') {
        const locationAge = Date.now() - new Date(appLocation.timestamp).getTime();
        const fiveMinutes = 5 * 60 * 1000;
        
        // If location is recent (within 5 minutes), use it
        if (locationAge < fiveMinutes) {
          return {
            success: true,
            location: appLocation,
            source: 'app'
          };
        }
      }
      
      // If no recent app location, try mSpace
      return await this.requestLocationViaMSpace(requesterId, targetUserId);
    } catch (error) {
      console.error('Error getting location for user:', error);
      throw new Error(`Failed to get location: ${error.message}`);
    }
  }

  // Clean up expired location sharing sessions
  async cleanupExpiredSessions() {
    try {
      const query = `
        UPDATE location_sharing_sessions 
        SET is_active = false, updated_at = NOW()
        WHERE expires_at IS NOT NULL 
        AND expires_at < NOW() 
        AND is_active = true
      `;
      
      const result = await this.pool.query(query);
      console.log(`Cleaned up ${result.rowCount} expired location sharing sessions`);
      
      return result.rowCount;
    } catch (error) {
      console.error('Error cleaning up expired sessions:', error);
      throw new Error('Failed to cleanup expired sessions');
    }
  }

  // Get nearby danger zones
  async getNearbyDangerZones(latitude, longitude, radiusKm = 5) {
    try {
      // Simple distance calculation (for production, use PostGIS)
      const query = `
        SELECT *, 
          SQRT(
            POW(69.1 * (latitude - $1), 2) + 
            POW(69.1 * ($2 - longitude) * COS(latitude / 57.3), 2)
          ) AS distance_km
        FROM danger_zones 
        WHERE is_active = true
        HAVING distance_km <= $3
        ORDER BY distance_km
      `;
      
      const result = await this.pool.query(query, [latitude, longitude, radiusKm]);
      
      return result.rows;
    } catch (error) {
      console.error('Error getting nearby danger zones:', error);
      throw new Error('Failed to get nearby danger zones');
    }
  }
}

module.exports = LocationService; 