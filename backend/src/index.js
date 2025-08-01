require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const cron = require('node-cron');
const { Pool } = require('pg');

// Import routes and middleware
const routes = require('./routes');
const auth = require('./middleware/auth');
const LocationService = require('./services/LocationService');

const app = express();
const PORT = process.env.PORT || 3000;

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

// Test database connection
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('Database connection failed:', err);
  } else {
    console.log('Database connected successfully');
  }
});

// Security middleware
app.use(helmet());

// CORS middleware
app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? ['https://your-frontend-domain.com'] 
    : ['http://localhost:3000', 'http://localhost:8080'],
  credentials: true
}));

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Request logging
app.use(auth.requestLogger);

// Global rate limiting
const globalRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: {
    success: false,
    message: 'Too many requests from this IP, please try again later.'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

app.use(globalRateLimit);

// API routes
app.use('/api', routes);

// Error handling middleware
app.use(auth.errorHandler);

// Scheduled tasks
const locationService = new LocationService();

// Clean up expired location sharing sessions every hour
cron.schedule('0 * * * *', async () => {
  try {
    console.log('Running scheduled cleanup of expired location sharing sessions...');
    await locationService.cleanupExpiredSessions();
  } catch (error) {
    console.error('Scheduled cleanup failed:', error);
  }
});

// Update user online status every 5 minutes
cron.schedule('*/5 * * * *', async () => {
  try {
    console.log('Updating user online status...');
    const query = `
      UPDATE users 
      SET is_online = false 
      WHERE last_seen < NOW() - INTERVAL '10 minutes'
    `;
    const result = await pool.query(query);
    console.log(`Updated ${result.rowCount} users to offline status`);
  } catch (error) {
    console.error('Failed to update user online status:', error);
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  pool.end();
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully');
  pool.end();
  process.exit(0);
});

// Start server
app.listen(PORT, () => {
  console.log(`SafeStep Backend API running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Database: ${process.env.DATABASE_URL ? 'Connected' : 'Not configured'}`);
  console.log(`mSpace: ${process.env.MSPACE_APPLICATION_ID ? 'Configured' : 'Not configured'}`);
});

module.exports = app; 