const { Pool } = require('pg');
const { body, validationResult } = require('express-validator');

class UserController {
  constructor() {
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
    });
  }

  // Emergency Contacts
  async getEmergencyContacts(req, res) {
    try {
      const userId = req.user.id;

      const query = `
        SELECT id, name, phone_number, relationship, created_at
        FROM emergency_contacts 
        WHERE user_id = $1
        ORDER BY created_at DESC
      `;

      const result = await this.pool.query(query, [userId]);

      res.json({
        success: true,
        contacts: result.rows,
        count: result.rows.length
      });
    } catch (error) {
      console.error('Get Emergency Contacts Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get emergency contacts'
      });
    }
  }

  async addEmergencyContact(req, res) {
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
      const { name, phoneNumber, relationship } = req.body;

      const query = `
        INSERT INTO emergency_contacts (user_id, name, phone_number, relationship, created_at)
        VALUES ($1, $2, $3, $4, NOW())
        RETURNING *
      `;

      const result = await this.pool.query(query, [userId, name, phoneNumber, relationship]);

      res.json({
        success: true,
        contact: result.rows[0],
        message: 'Emergency contact added successfully'
      });
    } catch (error) {
      console.error('Add Emergency Contact Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to add emergency contact'
      });
    }
  }

  async updateEmergencyContact(req, res) {
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
      const contactId = req.params.contactId;
      const { name, phoneNumber, relationship } = req.body;

      const query = `
        UPDATE emergency_contacts 
        SET name = COALESCE($1, name),
            phone_number = COALESCE($2, phone_number),
            relationship = COALESCE($3, relationship),
            updated_at = NOW()
        WHERE id = $4 AND user_id = $5
        RETURNING *
      `;

      const result = await this.pool.query(query, [name, phoneNumber, relationship, contactId, userId]);

      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Contact not found or not authorized'
        });
      }

      res.json({
        success: true,
        contact: result.rows[0],
        message: 'Emergency contact updated successfully'
      });
    } catch (error) {
      console.error('Update Emergency Contact Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to update emergency contact'
      });
    }
  }

  async deleteEmergencyContact(req, res) {
    try {
      const userId = req.user.id;
      const contactId = req.params.contactId;

      const query = `
        DELETE FROM emergency_contacts 
        WHERE id = $1 AND user_id = $2
        RETURNING *
      `;

      const result = await this.pool.query(query, [contactId, userId]);

      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Contact not found or not authorized'
        });
      }

      res.json({
        success: true,
        message: 'Emergency contact deleted successfully'
      });
    } catch (error) {
      console.error('Delete Emergency Contact Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to delete emergency contact'
      });
    }
  }

  // Reports
  async createReport(req, res) {
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
      const { type, location, description, severity } = req.body;

      const query = `
        INSERT INTO reports (user_id, type, location_lat, location_lng, description, severity, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, NOW())
        RETURNING *
      `;

      const result = await this.pool.query(query, [
        userId, type, location.latitude, location.longitude, description, severity
      ]);

      res.json({
        success: true,
        report: result.rows[0],
        message: 'Report created successfully'
      });
    } catch (error) {
      console.error('Create Report Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to create report'
      });
    }
  }

  async getReports(req, res) {
    try {
      const userId = req.user.id;
      const { status, type, limit = 20, offset = 0 } = req.query;

      let query = `
        SELECT id, type, location_lat, location_lng, description, severity, 
               status, created_at, updated_at
        FROM reports 
        WHERE user_id = $1
      `;

      const params = [userId];
      let paramIndex = 2;

      if (status) {
        query += ` AND status = $${paramIndex}`;
        params.push(status);
        paramIndex++;
      }

      if (type) {
        query += ` AND type = $${paramIndex}`;
        params.push(type);
        paramIndex++;
      }

      query += ` ORDER BY created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(parseInt(limit), parseInt(offset));

      const result = await this.pool.query(query, params);

      res.json({
        success: true,
        reports: result.rows,
        count: result.rows.length
      });
    } catch (error) {
      console.error('Get Reports Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get reports'
      });
    }
  }

  async getReport(req, res) {
    try {
      const userId = req.user.id;
      const reportId = req.params.reportId;

      const query = `
        SELECT id, type, location_lat, location_lng, description, severity, 
               status, created_at, updated_at
        FROM reports 
        WHERE id = $1 AND user_id = $2
      `;

      const result = await this.pool.query(query, [reportId, userId]);

      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Report not found or not authorized'
        });
      }

      res.json({
        success: true,
        report: result.rows[0]
      });
    } catch (error) {
      console.error('Get Report Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get report'
      });
    }
  }

  // Chat functionality
  async getChatConversations(req, res) {
    try {
      const userId = req.user.id;

      const query = `
        SELECT id, mode, language, created_at, updated_at
        FROM chat_conversations 
        WHERE user_id = $1
        ORDER BY updated_at DESC
      `;

      const result = await this.pool.query(query, [userId]);

      res.json({
        success: true,
        conversations: result.rows,
        count: result.rows.length
      });
    } catch (error) {
      console.error('Get Chat Conversations Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get chat conversations'
      });
    }
  }

  async createChatConversation(req, res) {
    try {
      const userId = req.user.id;
      const { mode = 'safe', language = 'auto' } = req.body;

      const query = `
        INSERT INTO chat_conversations (user_id, mode, language, created_at)
        VALUES ($1, $2, $3, NOW())
        RETURNING *
      `;

      const result = await this.pool.query(query, [userId, mode, language]);

      res.json({
        success: true,
        conversation: result.rows[0],
        message: 'Chat conversation created successfully'
      });
    } catch (error) {
      console.error('Create Chat Conversation Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to create chat conversation'
      });
    }
  }

  async getChatMessages(req, res) {
    try {
      const userId = req.user.id;
      const conversationId = req.params.conversationId;

      // Verify conversation belongs to user
      const convQuery = `
        SELECT id FROM chat_conversations 
        WHERE id = $1 AND user_id = $2
      `;

      const convResult = await this.pool.query(convQuery, [conversationId, userId]);

      if (convResult.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Conversation not found or not authorized'
        });
      }

      const query = `
        SELECT id, role, content, risk_analysis, created_at
        FROM chat_messages 
        WHERE conversation_id = $1
        ORDER BY created_at ASC
      `;

      const result = await this.pool.query(query, [conversationId]);

      res.json({
        success: true,
        messages: result.rows,
        count: result.rows.length
      });
    } catch (error) {
      console.error('Get Chat Messages Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get chat messages'
      });
    }
  }

  async addChatMessage(req, res) {
    try {
      const userId = req.user.id;
      const conversationId = req.params.conversationId;
      const { role, content, riskAnalysis } = req.body;

      // Verify conversation belongs to user
      const convQuery = `
        SELECT id FROM chat_conversations 
        WHERE id = $1 AND user_id = $2
      `;

      const convResult = await this.pool.query(convQuery, [conversationId, userId]);

      if (convResult.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'Conversation not found or not authorized'
        });
      }

      const query = `
        INSERT INTO chat_messages (conversation_id, role, content, risk_analysis, created_at)
        VALUES ($1, $2, $3, $4, NOW())
        RETURNING *
      `;

      const result = await this.pool.query(query, [conversationId, role, content, riskAnalysis]);

      // Update conversation timestamp
      await this.pool.query(`
        UPDATE chat_conversations 
        SET updated_at = NOW()
        WHERE id = $1
      `, [conversationId]);

      res.json({
        success: true,
        message: result.rows[0],
        message: 'Chat message added successfully'
      });
    } catch (error) {
      console.error('Add Chat Message Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to add chat message'
      });
    }
  }

  // Validation rules
  static validateEmergencyContact() {
    return [
      body('name')
        .isLength({ min: 2, max: 100 })
        .withMessage('Name must be 2-100 characters'),
      body('phoneNumber')
        .isMobilePhone('any')
        .withMessage('Invalid phone number format'),
      body('relationship')
        .optional()
        .isLength({ max: 50 })
        .withMessage('Relationship too long')
    ];
  }

  static validateCreateReport() {
    return [
      body('type')
        .isIn(['harassment', 'assault', 'theft', 'other'])
        .withMessage('Invalid report type'),
      body('location.latitude')
        .isFloat({ min: -90, max: 90 })
        .withMessage('Invalid latitude'),
      body('location.longitude')
        .isFloat({ min: -180, max: 180 })
        .withMessage('Invalid longitude'),
      body('description')
        .isLength({ min: 10, max: 1000 })
        .withMessage('Description must be 10-1000 characters'),
      body('severity')
        .optional()
        .isIn(['low', 'medium', 'high', 'critical'])
        .withMessage('Invalid severity level')
    ];
  }

  static validateChatMessage() {
    return [
      body('role')
        .isIn(['user', 'ai'])
        .withMessage('Invalid message role'),
      body('content')
        .isLength({ min: 1, max: 5000 })
        .withMessage('Message content must be 1-5000 characters'),
      body('riskAnalysis')
        .optional()
        .isLength({ max: 1000 })
        .withMessage('Risk analysis too long')
    ];
  }
}

module.exports = UserController; 