const MSpaceService = require('../services/MSpaceService');
const LocationService = require('../services/LocationService');
const { Pool } = require('pg');
const { body, validationResult } = require('express-validator');

class EmergencyController {
  constructor() {
    this.mspaceService = new MSpaceService();
    this.locationService = new LocationService();
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
    });
  }

  // Create panic alert
  async createPanicAlert(req, res) {
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
      const { location, message, alertType = 'panic' } = req.body;

      // Create emergency alert
      const alertQuery = `
        INSERT INTO emergency_alerts 
        (user_id, alert_type, location_lat, location_lng, message, is_active, created_at)
        VALUES ($1, $2, $3, $4, $5, true, NOW())
        RETURNING *
      `;

      const alertResult = await this.pool.query(alertQuery, [
        userId, alertType, location.latitude, location.longitude, message
      ]);

      const alert = alertResult.rows[0];

      // Get user's emergency contacts
      const contactsQuery = `
        SELECT phone_number, name 
        FROM emergency_contacts 
        WHERE user_id = $1
      `;

      const contactsResult = await this.pool.query(contactsQuery, [userId]);
      const contacts = contactsResult.rows;

      if (contacts.length === 0) {
        return res.status(400).json({
          success: false,
          message: 'No emergency contacts found. Please add emergency contacts first.'
        });
      }

      // Send SMS to emergency contacts
      const phoneNumbers = contacts.map(contact => contact.phone_number);
      const smsMessage = `EMERGENCY: ${req.user.name || 'Your contact'} needs help! Location: https://maps.google.com/?q=${location.latitude},${location.longitude}${message ? ` Message: ${message}` : ''}`;

      try {
        const smsResult = await this.mspaceService.sendSMS(phoneNumbers, smsMessage);
        
        // Update alert with SMS message IDs
        await this.pool.query(`
          UPDATE emergency_alerts 
          SET mspace_message_id = $1 
          WHERE id = $2
        `, [smsResult.messageIds.join(','), alert.id]);

        res.json({
          success: true,
          alert: {
            id: alert.id,
            type: alert.alert_type,
            location: {
              latitude: alert.location_lat,
              longitude: alert.location_lng
            },
            message: alert.message,
            createdAt: alert.created_at
          },
          contactsNotified: contacts.length,
          messageIds: smsResult.messageIds
        });
      } catch (smsError) {
        console.error('SMS sending failed:', smsError);
        
        // Still return success but note SMS failure
        res.json({
          success: true,
          alert: {
            id: alert.id,
            type: alert.alert_type,
            location: {
              latitude: alert.location_lat,
              longitude: alert.location_lng
            },
            message: alert.message,
            createdAt: alert.created_at
          },
          warning: 'Alert created but SMS notification failed'
        });
      }
    } catch (error) {
      console.error('Create Panic Alert Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Cancel emergency alert
  async cancelAlert(req, res) {
    try {
      const { alertId } = req.body;
      const userId = req.user.id;

      const query = `
        UPDATE emergency_alerts 
        SET is_active = false, ended_at = NOW()
        WHERE id = $1 AND user_id = $2
        RETURNING *
      `;

      const result = await this.pool.query(query, [alertId, userId]);

      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Alert not found or not authorized'
        });
      }

      res.json({
        success: true,
        message: 'Emergency alert cancelled successfully'
      });
    } catch (error) {
      console.error('Cancel Alert Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to cancel alert'
      });
    }
  }

  // Get user's emergency alerts
  async getEmergencyAlerts(req, res) {
    try {
      const userId = req.user.id;

      const query = `
        SELECT id, alert_type, location_lat, location_lng, message, 
               is_active, created_at, ended_at, mspace_message_id
        FROM emergency_alerts 
        WHERE user_id = $1
        ORDER BY created_at DESC
      `;

      const result = await this.pool.query(query, [userId]);

      res.json({
        success: true,
        alerts: result.rows
      });
    } catch (error) {
      console.error('Get Emergency Alerts Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get emergency alerts'
      });
    }
  }

  // Send emergency SMS
  async sendEmergencySMS(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const { destinationAddresses, message } = req.body;
      const userId = req.user.id;

      if (!destinationAddresses || !Array.isArray(destinationAddresses) || destinationAddresses.length === 0) {
        return res.status(400).json({
          success: false,
          message: 'At least one destination address is required'
        });
      }

      if (!message || message.trim().length === 0) {
        return res.status(400).json({
          success: false,
          message: 'Message content is required'
        });
      }

      console.log(`Sending emergency SMS to: ${destinationAddresses.join(', ')}`);

      // Call mSpace SMS API
      const result = await this.mspaceService.sendSMS(destinationAddresses, message);
      
      // Store SMS record
      await this.storeSMSRecord(userId, destinationAddresses, message, result.messageIds);
      
      res.json({
        success: true,
        message: 'Emergency SMS sent successfully',
        messageIds: result.messageIds,
        statusDetail: result.statusDetail
      });
    } catch (error) {
      console.error('Emergency SMS Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Request location via mSpace
  async requestLocation(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const { requesterId, subscriberId } = req.body;
      
      if (!requesterId || !subscriberId) {
        return res.status(400).json({
          success: false,
          message: 'Requester ID and Subscriber ID are required'
        });
      }

      console.log(`Requesting location for: ${subscriberId} by: ${requesterId}`);

      // Use LocationService to get location (app or mSpace)
      const result = await this.locationService.getLocationForUser(requesterId, subscriberId);
      
      res.json({
        success: true,
        location: result.location,
        source: result.source,
        messageID: result.messageID
      });
    } catch (error) {
      console.error('Location Request Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get nearby danger zones
  async getNearbyDangerZones(req, res) {
    try {
      const { latitude, longitude, radius = 5 } = req.query;
      
      if (!latitude || !longitude) {
        return res.status(400).json({
          success: false,
          message: 'Latitude and longitude are required'
        });
      }

      const dangerZones = await this.locationService.getNearbyDangerZones(
        parseFloat(latitude), 
        parseFloat(longitude), 
        parseFloat(radius)
      );

      res.json({
        success: true,
        dangerZones,
        count: dangerZones.length
      });
    } catch (error) {
      console.error('Get Danger Zones Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get nearby danger zones'
      });
    }
  }

  // Report danger zone
  async reportDangerZone(req, res) {
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
      const { location, radius, description } = req.body;

      const query = `
        INSERT INTO danger_zones 
        (location_lat, location_lng, radius_meters, description, reported_by, created_at)
        VALUES ($1, $2, $3, $4, $5, NOW())
        RETURNING *
      `;

      const result = await this.pool.query(query, [
        location.latitude, 
        location.longitude, 
        radius, 
        description, 
        userId
      ]);

      res.json({
        success: true,
        dangerZone: result.rows[0],
        message: 'Danger zone reported successfully'
      });
    } catch (error) {
      console.error('Report Danger Zone Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to report danger zone'
      });
    }
  }

  // Helper methods
  async storeSMSRecord(userId, phoneNumbers, message, messageIds) {
    const query = `
      INSERT INTO emergency_alerts 
      (user_id, alert_type, message, mspace_message_id, created_at)
      VALUES ($1, 'sms', $2, $3, NOW())
    `;
    
    await this.pool.query(query, [userId, message, messageIds.join(',')]);
  }

  // Validation rules
  static validateCreatePanicAlert() {
    return [
      body('location.latitude')
        .isFloat({ min: -90, max: 90 })
        .withMessage('Invalid latitude'),
      body('location.longitude')
        .isFloat({ min: -180, max: 180 })
        .withMessage('Invalid longitude'),
      body('message')
        .optional()
        .isLength({ max: 500 })
        .withMessage('Message too long')
    ];
  }

  static validateSendSMS() {
    return [
      body('destinationAddresses')
        .isArray({ min: 1 })
        .withMessage('At least one destination address is required'),
      body('destinationAddresses.*')
        .isMobilePhone('any')
        .withMessage('Invalid phone number format'),
      body('message')
        .isLength({ min: 1, max: 160 })
        .withMessage('Message must be 1-160 characters')
    ];
  }

  static validateRequestLocation() {
    return [
      body('requesterId')
        .isUUID()
        .withMessage('Invalid requester ID'),
      body('subscriberId')
        .isUUID()
        .withMessage('Invalid subscriber ID')
    ];
  }

  static validateReportDangerZone() {
    return [
      body('location.latitude')
        .isFloat({ min: -90, max: 90 })
        .withMessage('Invalid latitude'),
      body('location.longitude')
        .isFloat({ min: -180, max: 180 })
        .withMessage('Invalid longitude'),
      body('radius')
        .isInt({ min: 10, max: 10000 })
        .withMessage('Radius must be 10-10000 meters'),
      body('description')
        .isLength({ min: 10, max: 500 })
        .withMessage('Description must be 10-500 characters')
    ];
  }
}

module.exports = EmergencyController; 