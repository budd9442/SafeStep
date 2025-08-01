const express = require('express');
const AuthController = require('../controllers/AuthController');
const EmergencyController = require('../controllers/EmergencyController');
const LocationController = require('../controllers/LocationController');
const UserController = require('../controllers/UserController');
const auth = require('../middleware/auth');

const router = express.Router();

// Initialize controllers
const authController = new AuthController();
const emergencyController = new EmergencyController();
const locationController = new LocationController();
const userController = new UserController();

// Health check
router.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'SafeStep API is running',
    timestamp: new Date().toISOString()
  });
});

// Authentication routes
router.post('/auth/request-otp', 
  auth.rateLimit({ windowMs: 60 * 1000, max: 5 }), // 5 requests per minute
  AuthController.validateRequestOTP(),
  authController.requestOTP.bind(authController)
);

router.post('/auth/verify-otp',
  auth.rateLimit({ windowMs: 60 * 1000, max: 10 }), // 10 requests per minute
  AuthController.validateVerifyOTP(),
  authController.verifyOTP.bind(authController)
);

router.post('/auth/refresh-token',
  auth.rateLimit({ windowMs: 60 * 1000, max: 20 }),
  authController.refreshToken.bind(authController)
);

router.post('/auth/logout',
  auth.verifyToken,
  authController.logout.bind(authController)
);

// User routes (protected)
router.get('/users/profile',
  auth.verifyToken,
  authController.getProfile.bind(authController)
);

router.post('/users/profile',
  auth.verifyToken,
  AuthController.validateUpdateProfile(),
  authController.updateProfile.bind(authController)
);

// Emergency contacts
router.get('/users/emergency-contacts',
  auth.verifyToken,
  userController.getEmergencyContacts.bind(userController)
);

router.post('/users/emergency-contacts',
  auth.verifyToken,
  userController.addEmergencyContact.bind(userController)
);

router.put('/users/emergency-contacts/:contactId',
  auth.verifyToken,
  userController.updateEmergencyContact.bind(userController)
);

router.delete('/users/emergency-contacts/:contactId',
  auth.verifyToken,
  userController.deleteEmergencyContact.bind(userController)
);

// Emergency routes (protected)
router.post('/emergency/panic-alert',
  auth.verifyToken,
  auth.rateLimit({ windowMs: 60 * 1000, max: 3 }), // 3 panic alerts per minute
  EmergencyController.validateCreatePanicAlert(),
  emergencyController.createPanicAlert.bind(emergencyController)
);

router.post('/emergency/cancel-alert',
  auth.verifyToken,
  emergencyController.cancelAlert.bind(emergencyController)
);

router.get('/emergency/alerts',
  auth.verifyToken,
  emergencyController.getEmergencyAlerts.bind(emergencyController)
);

router.post('/emergency/send-sms',
  auth.verifyToken,
  auth.rateLimit({ windowMs: 60 * 1000, max: 10 }), // 10 SMS per minute
  EmergencyController.validateSendSMS(),
  emergencyController.sendEmergencySMS.bind(emergencyController)
);

router.post('/emergency/request-location',
  auth.verifyToken,
  EmergencyController.validateRequestLocation(),
  emergencyController.requestLocation.bind(emergencyController)
);

// Danger zones
router.get('/emergency/danger-zones',
  auth.optionalAuth,
  emergencyController.getNearbyDangerZones.bind(emergencyController)
);

router.post('/emergency/danger-zones',
  auth.verifyToken,
  EmergencyController.validateReportDangerZone(),
  emergencyController.reportDangerZone.bind(emergencyController)
);

// Location routes (protected)
router.post('/location/update',
  auth.verifyToken,
  auth.rateLimit({ windowMs: 60 * 1000, max: 60 }), // 60 location updates per minute
  locationController.updateLocation.bind(locationController)
);

router.get('/location/current',
  auth.verifyToken,
  locationController.getCurrentLocation.bind(locationController)
);

router.post('/location/start-sharing',
  auth.verifyToken,
  locationController.startLocationSharing.bind(locationController)
);

router.post('/location/stop-sharing',
  auth.verifyToken,
  locationController.stopLocationSharing.bind(locationController)
);

router.get('/location/shared',
  auth.verifyToken,
  locationController.getSharedLocations.bind(locationController)
);

router.get('/location/user/:userId',
  auth.verifyToken,
  locationController.getUserLocation.bind(locationController)
);

// Reports
router.post('/reports',
  auth.verifyToken,
  userController.createReport.bind(userController)
);

router.get('/reports',
  auth.verifyToken,
  userController.getReports.bind(userController)
);

router.get('/reports/:reportId',
  auth.verifyToken,
  userController.getReport.bind(userController)
);

// Chat routes (for AI chat history)
router.get('/chat/conversations',
  auth.verifyToken,
  userController.getChatConversations.bind(userController)
);

router.post('/chat/conversations',
  auth.verifyToken,
  userController.createChatConversation.bind(userController)
);

router.get('/chat/conversations/:conversationId/messages',
  auth.verifyToken,
  userController.getChatMessages.bind(userController)
);

router.post('/chat/conversations/:conversationId/messages',
  auth.verifyToken,
  userController.addChatMessage.bind(userController)
);

// mSpace webhook for SMS delivery reports
router.post('/mspace/delivery-report',
  (req, res) => {
    // Handle mSpace delivery reports
    console.log('mSpace delivery report received:', req.body);
    
    // Process the delivery report
    // This would typically update the SMS delivery status in the database
    
    res.json({
      statusCode: 'S1000',
      statusDetail: 'Success'
    });
  }
);

// 404 handler
router.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    message: 'Endpoint not found'
  });
});

module.exports = router; 