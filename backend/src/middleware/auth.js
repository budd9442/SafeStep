const jwt = require('jsonwebtoken');
const { Pool } = require('pg');

class AuthMiddleware {
  constructor() {
    this.pool = new Pool({
      connectionString: process.env.DATABASE_URL,
    });
  }

  // Verify JWT token
  async verifyToken(req, res, next) {
    try {
      const authHeader = req.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({
          success: false,
          message: 'Access token required'
        });
      }

      const token = authHeader.substring(7); // Remove 'Bearer ' prefix
      
      if (!token) {
        return res.status(401).json({
          success: false,
          message: 'Access token required'
        });
      }

      // Verify token
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      
      // Get user from database
      const query = `
        SELECT id, phone_number, name, email, subscription_status, is_active
        FROM users 
        WHERE id = $1 AND is_active = true
      `;
      
      const result = await this.pool.query(query, [decoded.userId]);
      
      if (result.rows.length === 0) {
        return res.status(401).json({
          success: false,
          message: 'Invalid or expired token'
        });
      }
      
      const user = result.rows[0];
      
      // Add user to request object
      req.user = {
        id: user.id,
        phoneNumber: user.phone_number,
        name: user.name,
        email: user.email,
        subscriptionStatus: user.subscription_status
      };
      
      next();
    } catch (error) {
      console.error('Token verification error:', error);
      
      if (error.name === 'JsonWebTokenError') {
        return res.status(401).json({
          success: false,
          message: 'Invalid token'
        });
      }
      
      if (error.name === 'TokenExpiredError') {
        return res.status(401).json({
          success: false,
          message: 'Token expired'
        });
      }
      
      res.status(500).json({
        success: false,
        message: 'Authentication failed'
      });
    }
  }

  // Optional token verification (for public endpoints that can work with or without auth)
  async optionalAuth(req, res, next) {
    try {
      const authHeader = req.headers.authorization;
      
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        // No token provided, continue without user
        req.user = null;
        return next();
      }

      const token = authHeader.substring(7);
      
      if (!token) {
        req.user = null;
        return next();
      }

      // Verify token
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      
      // Get user from database
      const query = `
        SELECT id, phone_number, name, email, subscription_status, is_active
        FROM users 
        WHERE id = $1 AND is_active = true
      `;
      
      const result = await this.pool.query(query, [decoded.userId]);
      
      if (result.rows.length === 0) {
        req.user = null;
        return next();
      }
      
      const user = result.rows[0];
      
      // Add user to request object
      req.user = {
        id: user.id,
        phoneNumber: user.phone_number,
        name: user.name,
        email: user.email,
        subscriptionStatus: user.subscription_status
      };
      
      next();
    } catch (error) {
      // If token verification fails, continue without user
      req.user = null;
      next();
    }
  }

  // Rate limiting middleware
  rateLimit(options = {}) {
    const windowMs = options.windowMs || 15 * 60 * 1000; // 15 minutes
    const max = options.max || 100; // limit each IP to 100 requests per windowMs
    const message = options.message || 'Too many requests from this IP';
    
    const requests = new Map();
    
    return (req, res, next) => {
      const ip = req.ip;
      const now = Date.now();
      
      // Clean up old entries
      for (const [key, timestamp] of requests.entries()) {
        if (now - timestamp > windowMs) {
          requests.delete(key);
        }
      }
      
      // Check if IP has exceeded limit
      const userRequests = requests.get(ip) || [];
      const recentRequests = userRequests.filter(timestamp => now - timestamp < windowMs);
      
      if (recentRequests.length >= max) {
        return res.status(429).json({
          success: false,
          message: message
        });
      }
      
      // Add current request
      recentRequests.push(now);
      requests.set(ip, recentRequests);
      
      next();
    };
  }

  // CORS middleware
  cors() {
    return (req, res, next) => {
      res.header('Access-Control-Allow-Origin', '*');
      res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
      
      if (req.method === 'OPTIONS') {
        res.sendStatus(200);
      } else {
        next();
      }
    };
  }

  // Error handling middleware
  errorHandler(err, req, res, next) {
    console.error('Error:', err);
    
    if (err.name === 'ValidationError') {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: err.errors
      });
    }
    
    if (err.name === 'UnauthorizedError') {
      return res.status(401).json({
        success: false,
        message: 'Unauthorized'
      });
    }
    
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }

  // Request logging middleware
  requestLogger(req, res, next) {
    const start = Date.now();
    
    res.on('finish', () => {
      const duration = Date.now() - start;
      console.log(`${req.method} ${req.originalUrl} ${res.statusCode} ${duration}ms`);
    });
    
    next();
  }
}

module.exports = new AuthMiddleware(); 