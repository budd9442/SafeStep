const MSpaceService = require('../services/MSpaceService');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const { body, validationResult } = require('express-validator');

class AuthController {
  constructor() {
    this.mspaceService = new MSpaceService();
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
    });
  }

  // Request OTP
  async requestOTP(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const { phoneNumber } = req.body;
      
      // Validate phone number format for Sri Lanka
      if (!phoneNumber || !phoneNumber.match(/^\+94\d{9}$/)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid phone number format. Use +94XXXXXXXXX format'
        });
      }

      console.log(`Requesting OTP for: ${phoneNumber}`);

      // Generate random OTP
      const otp = this.mspaceService.generateOTP();
      
      // Send OTP via SMS
      const smsResult = await this.mspaceService.sendOTPSMS(phoneNumber, otp);
      
      // Store OTP session in database
      await this.storeOTPSession(phoneNumber, otp);
      
      res.json({
        success: true,
        message: 'OTP sent successfully to your mobile number',
        messageIds: smsResult.messageIds
      });
    } catch (error) {
      console.error('OTP Request Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Verify OTP
  async verifyOTP(req, res) {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const { phoneNumber, otp } = req.body;
      
      if (!phoneNumber || !otp) {
        return res.status(400).json({
          success: false,
          message: 'Phone number and OTP are required'
        });
      }

      console.log(`Verifying OTP for: ${phoneNumber}`);

      // Verify OTP from database
      const otpSession = await this.verifyOTPSession(phoneNumber, otp);
      
      if (!otpSession) {
        return res.status(400).json({
          success: false,
          message: 'Invalid or expired OTP'
        });
      }

      // Create or update user
      const user = await this.createOrUpdateUser(phoneNumber);
      
      // Generate JWT token
      const token = this.generateJWT(user);
      
      res.json({
        success: true,
        token,
        user: {
          id: user.id,
          phoneNumber: user.phone_number,
          name: user.name
        },
        message: 'OTP verified successfully'
      });
    } catch (error) {
      console.error('OTP Verify Error:', error);
      res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Refresh token
  async refreshToken(req, res) {
    try {
      const { refreshToken } = req.body;
      
      if (!refreshToken) {
        return res.status(400).json({
          success: false,
          message: 'Refresh token is required'
        });
      }

      // Verify refresh token
      const decoded = jwt.verify(refreshToken, process.env.JWT_SECRET);
      
      // Get user from database
      const userQuery = `
        SELECT * FROM users WHERE id = $1 AND is_active = true
      `;
      
      const userResult = await this.pool.query(userQuery, [decoded.userId]);
      
      if (userResult.rows.length === 0) {
        return res.status(401).json({
          success: false,
          message: 'Invalid refresh token'
        });
      }
      
      const user = userResult.rows[0];
      
      // Generate new token
      const newToken = this.generateJWT(user);
      
      res.json({
        success: true,
        token: newToken,
        user: {
          id: user.id,
          phoneNumber: user.phone_number,
          name: user.name
        }
      });
    } catch (error) {
      console.error('Token Refresh Error:', error);
      res.status(401).json({
        success: false,
        message: 'Invalid refresh token'
      });
    }
  }

  // Logout
  async logout(req, res) {
    try {
      const { deviceId } = req.body;
      const userId = req.user.id;
      
      if (deviceId) {
        // Invalidate session
        await this.pool.query(`
          UPDATE user_sessions 
          SET is_active = false, updated_at = NOW()
          WHERE user_id = $1 AND device_id = $2
        `, [userId, deviceId]);
      }
      
      res.json({
        success: true,
        message: 'Logged out successfully'
      });
    } catch (error) {
      console.error('Logout Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to logout'
      });
    }
  }

  // Get user profile
  async getProfile(req, res) {
    try {
      const userId = req.user.id;
      
      const query = `
        SELECT id, phone_number, name, email, date_of_birth, profile_picture_url, 
               subscription_status, is_online, last_seen, created_at
        FROM users 
        WHERE id = $1 AND is_active = true
      `;
      
      const result = await this.pool.query(query, [userId]);
      
      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'User not found'
        });
      }
      
      res.json({
        success: true,
        user: result.rows[0]
      });
    } catch (error) {
      console.error('Get Profile Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to get profile'
      });
    }
  }

  // Update user profile
  async updateProfile(req, res) {
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
      const { name, email, dateOfBirth, profilePictureUrl } = req.body;
      
      const query = `
        UPDATE users 
        SET name = COALESCE($1, name),
            email = COALESCE($2, email),
            date_of_birth = COALESCE($3, date_of_birth),
            profile_picture_url = COALESCE($4, profile_picture_url),
            updated_at = NOW()
        WHERE id = $5 AND is_active = true
        RETURNING *
      `;
      
      const result = await this.pool.query(query, [
        name, email, dateOfBirth, profilePictureUrl, userId
      ]);
      
      if (result.rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: 'User not found'
        });
      }
      
      res.json({
        success: true,
        user: result.rows[0],
        message: 'Profile updated successfully'
      });
    } catch (error) {
      console.error('Update Profile Error:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to update profile'
      });
    }
  }

  // Helper methods
  async storeOTPSession(phoneNumber, otp) {
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes
    
    const query = `
      INSERT INTO mspace_otp_sessions 
      (phone_number, reference_no, status, expires_at, created_at)
      VALUES ($1, $2, 'PENDING', $3, NOW())
      ON CONFLICT (phone_number) 
      DO UPDATE SET 
        reference_no = $2, 
        status = 'PENDING', 
        expires_at = $3, 
        attempts = 0,
        updated_at = NOW()
    `;
    
    await this.pool.query(query, [phoneNumber, otp, expiresAt]);
  }

  async verifyOTPSession(phoneNumber, otp) {
    const query = `
      SELECT * FROM mspace_otp_sessions 
      WHERE phone_number = $1 
      AND reference_no = $2 
      AND status = 'PENDING' 
      AND expires_at > NOW()
      AND attempts < 3
    `;
    
    const result = await this.pool.query(query, [phoneNumber, otp]);
    
    if (result.rows.length === 0) {
      // Increment attempts for failed verification
      await this.pool.query(`
        UPDATE mspace_otp_sessions 
        SET attempts = attempts + 1, updated_at = NOW()
        WHERE phone_number = $1
      `, [phoneNumber]);
      
      return null;
    }
    
    // Mark OTP as used
    await this.pool.query(`
      UPDATE mspace_otp_sessions 
      SET status = 'VERIFIED', updated_at = NOW()
      WHERE phone_number = $1 AND reference_no = $2
    `, [phoneNumber, otp]);
    
    return result.rows[0];
  }

  async createOrUpdateUser(phoneNumber) {
    const query = `
      INSERT INTO users (phone_number, subscription_status, created_at)
      VALUES ($1, 'REGISTERED', NOW())
      ON CONFLICT (phone_number) 
      DO UPDATE SET 
        subscription_status = 'REGISTERED',
        updated_at = NOW()
      RETURNING *
    `;
    
    const result = await this.pool.query(query, [phoneNumber]);
    return result.rows[0];
  }

  generateJWT(user) {
    return jwt.sign(
      { 
        userId: user.id, 
        phoneNumber: user.phone_number
      },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
    );
  }

  // Validation rules
  static validateRequestOTP() {
    return [
      body('phoneNumber')
        .isMobilePhone('any')
        .withMessage('Invalid phone number format')
    ];
  }

  static validateVerifyOTP() {
    return [
      body('phoneNumber')
        .isMobilePhone('any')
        .withMessage('Invalid phone number format'),
      body('otp')
        .isLength({ min: 6, max: 6 })
        .withMessage('OTP must be 6 digits')
        .isNumeric()
        .withMessage('OTP must contain only numbers')
    ];
  }

  static validateUpdateProfile() {
    return [
      body('name')
        .optional()
        .isLength({ min: 2, max: 100 })
        .withMessage('Name must be 2-100 characters'),
      body('email')
        .optional()
        .isEmail()
        .withMessage('Invalid email format'),
      body('dateOfBirth')
        .optional()
        .isISO8601()
        .withMessage('Invalid date format')
    ];
  }
}

module.exports = AuthController; 