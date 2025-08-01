const LocationService = require('../services/LocationService');
const { Pool } = require('pg');
const { body, validationResult } = require('express-validator');

class LocationController {
  constructor() {
    this.locationService = new LocationService();
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
    });
  }

  // Update user location
  async updateLocation(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const userId = req.user.id;
      const { latitude, longitude, accuracy } = req.body;

      const result = await this.locationService.updateUserLocation(
        userId, 
        latitude, 
        longitude, 
        accuracy
      );

      res.json(result);
    } catch (error) {
      console.error('Update Location Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get current location
  async getCurrentLocation(req, res) {
    try {
      const userId = req.user.id;

      const location = await this.locationService.getUserLocation(userId);

      if (!location) {
        return res.status(404).json({
          success: false,
          message: 'No location data found'
        });
      }

      res.json({
        success: true,
        location
      });
    } catch (error) {
      console.error('Get Current Location Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Start location sharing
  async startLocationSharing(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const userId = req.user.id;
      const { contactIds, duration = '1h' } = req.body;

      if (!contactIds || !Array.isArray(contactIds) || contactIds.length === 0) {
        return res.status(400).json({
          success: false,
          message: 'At least one contact ID is required'
        });
      }

      const result = await this.locationService.startLocationSharing(
        userId, 
        contactIds, 
        duration
      );

      res.json(result);
    } catch (error) {
      console.error('Start Location Sharing Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Stop location sharing
  async stopLocationSharing(req, res) {
    try {
      const userId = req.user.id;

      const result = await this.locationService.stopLocationSharing(userId);

      res.json(result);
    } catch (error) {
      console.error('Stop Location Sharing Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get shared locations
  async getSharedLocations(req, res) {
    try {
      const userId = req.user.id;

      const sharedLocations = await this.locationService.getSharedLocations(userId);

      res.json({
        success: true,
        sharedLocations,
        count: sharedLocations.length
      });
    } catch (error) {
      console.error('Get Shared Locations Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get specific user's location
  async getUserLocation(req, res) {
    try {
      const requesterId = req.user.id;
      const targetUserId = req.params.userId;

      if (!targetUserId) {
        return res.status(400).json({
          success: false,
          message: 'User ID is required'
        });
      }

      const result = await this.locationService.getLocationForUser(requesterId, targetUserId);

      res.json(result);
    } catch (error) {
      console.error('Get User Location Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get location sharing status
  async getLocationSharingStatus(req, res) {
    try {
      const userId = req.user.id;

      const query = `
        SELECT contact_ids, duration, is_active, expires_at, created_at
        FROM location_sharing_sessions 
        WHERE user_id = $1 AND is_active = true
        AND (expires_at IS NULL OR expires_at > NOW())
      `;

      const result = await this.pool.query(query, [userId]);

      if (result.rows.length === 0) {
        return res.json({
          success: true,
          isSharing: false,
          session: null
        });
      }

      const session = result.rows[0];

      // Get contact details
      const contactQuery = `
        SELECT id, name, phone_number 
        FROM emergency_contacts 
        WHERE id = ANY($1)
      `;

      const contactsResult = await this.pool.query(contactQuery, [session.contact_ids]);
      const contacts = contactsResult.rows;

      res.json({
        success: true,
        isSharing: true,
        session: {
          ...session,
          contacts
        }
      });
    } catch (error) {
      console.error('Get Location Sharing Status Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get nearby users (for emergency situations)
  async getNearbyUsers(req, res) {
    try {
      const { latitude, longitude, radius = 5 } = req.query; // radius in km
      
      if (!latitude || !longitude) {
        return res.status(400).json({
          success: false,
          message: 'Latitude and longitude are required'
        });
      }

      // Simple distance calculation (for production, use PostGIS)
      const query = `
        SELECT ul.user_id, ul.latitude, ul.longitude, ul.timestamp,
               u.name, u.phone_number,
               SQRT(
                 POW(69.1 * (ul.latitude - $1), 2) + 
                 POW(69.1 * ($2 - ul.longitude) * COS(ul.latitude / 57.3), 2)
               ) AS distance_km
        FROM user_locations ul
        JOIN users u ON ul.user_id = u.id
        WHERE u.is_active = true
        AND ul.timestamp > NOW() - INTERVAL '30 minutes'
        HAVING distance_km <= $3
        ORDER BY distance_km
        LIMIT 20
      `;

      const result = await this.pool.query(query, [
        parseFloat(latitude), 
        parseFloat(longitude), 
        parseFloat(radius)
      ]);

      res.json({
        success: true,
        nearbyUsers: result.rows,
        count: result.rows.length
      });
    } catch (error) {
      console.error('Get Nearby Users Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Validation rules
  static validateUpdateLocation() {
    return [
      body('latitude')
        .isFloat({ min: -90, max: 90 })
        .withMessage('Invalid latitude'),
      body('longitude')
        .isFloat({ min: -180, max: 180 })
        .withMessage('Invalid longitude'),
      body('accuracy')
        .optional()
        .isFloat({ min: 0, max: 1000 })
        .withMessage('Invalid accuracy')
    ];
  }

  static validateStartLocationSharing() {
    return [
      body('contactIds')
        .isArray({ min: 1 })
        .withMessage('At least one contact ID is required'),
      body('contactIds.*')
        .isUUID()
        .withMessage('Invalid contact ID format'),
      body('duration')
        .optional()
        .isIn(['1h', '8h', 'always'])
        .withMessage('Duration must be 1h, 8h, or always')
    ];
  }
}

module.exports = LocationController; 