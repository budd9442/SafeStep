const express = require('express');
const axios = require('axios');
const { getFirestore, admin } = require('../config/firebase');

const router = express.Router();

// Request logging middleware for all routes
router.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  const clientIP = req.ip || req.connection.remoteAddress || req.headers['x-forwarded-for'];
  const userAgent = req.headers['user-agent'] || 'Unknown';
  
  console.log(`\n📥 [${timestamp}] ${req.method} ${req.originalUrl}`);
  console.log(`🌐 Client IP: ${clientIP}`);
  console.log(`📱 User Agent: ${userAgent}`);
  console.log(`📋 Request Body:`, JSON.stringify(req.body, null, 2));
  console.log(`🔗 Query Params:`, JSON.stringify(req.query, null, 2));
  console.log(`📄 Headers:`, JSON.stringify(req.headers, null, 2));
  
  // Override res.json to log responses
  const originalJson = res.json;
  res.json = function(data) {
    console.log(`\n📤 [${new Date().toISOString()}] ${req.method} ${req.originalUrl} - Status: ${res.statusCode}`);
    console.log(`📋 Response:`, JSON.stringify(data, null, 2));
    return originalJson.call(this, data);
  };
  
  next();
});

// Global error handler middleware
router.use((error, req, res, next) => {
  const timestamp = new Date().toISOString();
  console.error(`\n❌ [${timestamp}] GLOBAL ERROR HANDLER`);
  console.error(`🚨 Error Message:`, error.message);
  console.error(`📊 Error Code:`, error.code || 'UNKNOWN');
  console.error(`📋 Request Body:`, JSON.stringify(req.body, null, 2));
  console.error(`📚 Stack Trace:`, error.stack);
  
  // Log axios errors with more detail
  if (error.response) {
    console.error(`🌐 HTTP Status:`, error.response.status);
    console.error(`📄 Response Data:`, JSON.stringify(error.response.data, null, 2));
    console.error(`📋 Response Headers:`, JSON.stringify(error.response.headers, null, 2));
  }
  
  if (error.request) {
    console.error(`📡 Request made but no response received:`, error.request);
  }
  
  // Send error response
  if (!res.headersSent) {
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
      timestamp: timestamp
    });
  }
});

// Logging utility functions
const logRequest = (req, endpoint) => {
  const timestamp = new Date().toISOString();
  const clientIP = req.ip || req.connection.remoteAddress || req.headers['x-forwarded-for'];
  const userAgent = req.headers['user-agent'] || 'Unknown';
  
  console.log(`\n📥 [${timestamp}] ${req.method} ${endpoint}`);
  console.log(`🌐 Client IP: ${clientIP}`);
  console.log(`📱 User Agent: ${userAgent}`);
  console.log(`📋 Request Body:`, JSON.stringify(req.body, null, 2));
  console.log(`🔗 Query Params:`, JSON.stringify(req.query, null, 2));
  console.log(`📄 Headers:`, JSON.stringify(req.headers, null, 2));
};

const logResponse = (req, endpoint, statusCode, responseData) => {
  const timestamp = new Date().toISOString();
  console.log(`\n📤 [${timestamp}] ${req.method} ${endpoint} - Status: ${statusCode}`);
  console.log(`📋 Response:`, JSON.stringify(responseData, null, 2));
};

const logError = (req, endpoint, error, additionalInfo = {}) => {
  const timestamp = new Date().toISOString();
  console.error(`\n❌ [${timestamp}] ERROR in ${req.method} ${endpoint}`);
  console.error(`🚨 Error Message:`, error.message);
  console.error(`📊 Error Code:`, error.code || 'UNKNOWN');
  console.error(`📋 Request Body:`, JSON.stringify(req.body, null, 2));
  console.error(`🔍 Additional Info:`, JSON.stringify(additionalInfo, null, 2));
  console.error(`📚 Stack Trace:`, error.stack);
  
  // Log axios errors with more detail
  if (error.response) {
    console.error(`🌐 HTTP Status:`, error.response.status);
    console.error(`📄 Response Data:`, JSON.stringify(error.response.data, null, 2));
    console.error(`📋 Response Headers:`, JSON.stringify(error.response.headers, null, 2));
  }
  
  if (error.request) {
    console.error(`📡 Request made but no response received:`, error.request);
  }
};

// mspace API configuration
const MSPACE_CONFIG = {
  baseURL: process.env.MSPACE_BASE_URL || 'https://api.mspace.lk',
  applicationId: process.env.MSPACE_APPLICATION_ID,
  password: process.env.MSPACE_PASSWORD,
  applicationHash: process.env.MSPACE_APPLICATION_HASH
};

// Validate phone number format
const validatePhoneNumber = (phoneNumber) => {
  // Remove all non-digit characters
  const digits = phoneNumber.replace(/\D/g, '');
  
  // Check if it's a valid Sri Lankan mobile number
  // Sri Lankan mobile numbers start with 7 and are 9 digits long
  if (digits.length === 9 && digits.startsWith('7')) {
    return `tel:94${digits}`;
  }
  
  // Check if it already has country code
  if (digits.length === 12 && digits.startsWith('947')) {
    return `tel:${digits}`;
  }
  
  return null;
};

// Generate OTP reference for internal tracking
const generateReference = () => {
  return `REF_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
};

// Generate random 6-digit OTP
const generateOTP = () => {
  return Math.floor(100000 + Math.random() * 900000).toString();
};

// POST /api/otp/request - Request OTP
router.post('/request', async (req, res) => {
  const endpoint = '/api/otp/request';
  
  try {
    // Log incoming request
    logRequest(req, endpoint);
    
    const { phoneNumber, applicationMetaData } = req.body;

    // Validate input
    if (!phoneNumber) {
      return res.status(400).json({
        error: 'Phone number is required',
        code: 'MISSING_PHONE_NUMBER'
      });
    }

    // Handle tel: format for phone number
    let formattedPhone;
    if (phoneNumber.startsWith('tel:')) {
      formattedPhone = phoneNumber; // Use as-is if already in tel: format
    } else {
      // Validate and format phone number if not in tel: format
      formattedPhone = validatePhoneNumber(phoneNumber);
      if (!formattedPhone) {
        return res.status(400).json({
          error: 'Invalid phone number format',
          code: 'INVALID_PHONE_NUMBER',
          message: 'Please provide a valid Sri Lankan mobile number or tel: format'
        });
      }
    }

    const db = getFirestore();
    
    // Check if client exists in client mappings
    const clientQuery = await db.collection('client_mappings')
      .where('phoneNumber', '==', formattedPhone)
      .where('isActive', '==', true)
      .limit(1)
      .get();

    if (clientQuery.empty) {
      return res.status(404).json({
        error: 'Client not registered',
        code: 'CLIENT_NOT_FOUND',
        message: 'Please register your client ID before requesting OTP'
      });
    }

    const clientData = clientQuery.docs[0].data();
    const clientId = clientData.clientId;

    console.log('✅ Client found in mappings:', formattedPhone, 'Client ID:', clientId);

    // Check if OTP was already requested recently (within 1 minute)
    const recentOtpQuery = await db.collection('otp_requests')
      .where('phoneNumber', '==', formattedPhone)
      .where('createdAt', '>', new Date(Date.now() - 60000)) // 1 minute ago
      .limit(1)
      .get();

    if (!recentOtpQuery.empty) {
      return res.status(429).json({
        error: 'OTP already requested recently',
        code: 'OTP_RATE_LIMITED',
        message: 'Please wait before requesting another OTP'
      });
    }

    // Generate random OTP
    const generatedOTP = generateOTP();
    const internalReference = generateReference();

    console.log('📱 Generating OTP for:', formattedPhone);
    console.log('🔢 Generated OTP:', generatedOTP);

    // Prepare SMS message
    const smsMessage = `Your SafeStep verification code is: ${generatedOTP}. This code expires in 5 minutes. Do not share this code with anyone.`;

    // Prepare mspace SMS API request using the correct format with client ID
    const mspaceSMSRequest = {
      version: "1.0",
      applicationId: MSPACE_CONFIG.applicationId,
      password: MSPACE_CONFIG.password,
      message: smsMessage,
      destinationAddresses: [clientId], // Use client ID from mapping instead of phone number
      deliveryStatusRequest: "0",
      encoding: "0"
    };

    console.log('📤 Sending SMS via mspace for:', formattedPhone);
    console.log('📋 SMS Request:', JSON.stringify(mspaceSMSRequest, null, 2));

    // Call mspace SMS API
    const mspaceResponse = await axios.post(
      `${MSPACE_CONFIG.baseURL}/sms/send`,
      mspaceSMSRequest,
      {
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        timeout: 10000 // 10 second timeout
      }
    );

    // Check mspace response
    if (mspaceResponse.data.statusCode !== 'S1000') {
      throw new Error(`mspace SMS API error: ${mspaceResponse.data.statusDetail}`);
    }

    const mspaceReference = mspaceResponse.data.referenceNo || internalReference;

    // Store OTP request in Firebase
    const otpData = {
      phoneNumber: formattedPhone,
      clientId: clientId, // Store the client ID used for SMS
      mspaceReference: mspaceReference,
      internalReference: internalReference,
      generatedOTP: generatedOTP, // Store the generated OTP
      status: 'pending',
      attempts: 0,
      maxAttempts: 3,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 5 * 60 * 1000), // 5 minutes from now
      smsMessage: smsMessage // Store the SMS message sent
    };

    await db.collection('otp_requests').doc(internalReference).set(otpData);

    // Update client's last seen timestamp
    await clientQuery.docs[0].ref.update({
      lastSeen: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log('✅ OTP requested successfully for:', formattedPhone);
    console.log('📱 Updated client last seen for:', formattedPhone);

    // Return success response
    const successResponse = {
      success: true,
      message: 'OTP sent successfully',
      reference: internalReference,
      expiresIn: 300, // 5 minutes in seconds
      phoneNumber: formattedPhone.replace('tel:', '') // Return clean phone number
    };
    
    logResponse(req, endpoint, 200, successResponse);
    res.json(successResponse);

  } catch (error) {
    // Log detailed error information
    logError(req, endpoint, error, {
      phoneNumber: req.body.phoneNumber,
      timestamp: new Date().toISOString()
    });

    if (error.response) {
      // mspace SMS API error
      const errorResponse = {
        error: 'Failed to send SMS',
        code: 'MSPACE_SMS_ERROR',
        message: error.response.data?.statusDetail || 'SMS service unavailable'
      };
      logResponse(req, endpoint, 400, errorResponse);
      return res.status(400).json(errorResponse);
    }

    if (error.code === 'ECONNABORTED') {
      const errorResponse = {
        error: 'Request timeout',
        code: 'TIMEOUT',
        message: 'SMS service is taking too long to respond'
      };
      logResponse(req, endpoint, 408, errorResponse);
      return res.status(408).json(errorResponse);
    }

    const errorResponse = {
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to process OTP request'
    };
    logResponse(req, endpoint, 500, errorResponse);
    res.status(500).json(errorResponse);
  }
});

// POST /api/otp/verify - Verify OTP
router.post('/verify', async (req, res) => {
  const endpoint = '/api/otp/verify';
  
  try {
    // Log incoming request
    logRequest(req, endpoint);
    
    const { reference, otp, phoneNumber } = req.body;

    // Validate input
    if (!reference || !otp) {
      return res.status(400).json({
        error: 'Reference and OTP are required',
        code: 'MISSING_PARAMETERS'
      });
    }

    if (otp.length !== 6 || !/^\d{6}$/.test(otp)) {
      return res.status(400).json({
        error: 'Invalid OTP format',
        code: 'INVALID_OTP_FORMAT',
        message: 'OTP must be a 6-digit number'
      });
    }

    // Get OTP request from Firebase
    const db = getFirestore();
    const otpDoc = await db.collection('otp_requests').doc(reference).get();

    if (!otpDoc.exists) {
      return res.status(404).json({
        error: 'OTP request not found',
        code: 'OTP_NOT_FOUND',
        message: 'Invalid reference number'
      });
    }

    const otpData = otpDoc.data();

    // Check if OTP has expired
    if (new Date() > otpData.expiresAt.toDate()) {
      return res.status(410).json({
        error: 'OTP has expired',
        code: 'OTP_EXPIRED',
        message: 'Please request a new OTP'
      });
    }

    // Check if max attempts exceeded
    if (otpData.attempts >= otpData.maxAttempts) {
      return res.status(429).json({
        error: 'Maximum verification attempts exceeded',
        code: 'MAX_ATTEMPTS_EXCEEDED',
        message: 'Please request a new OTP'
      });
    }

    // Check if already verified
    if (otpData.status === 'verified') {
      return res.status(409).json({
        error: 'OTP already verified',
        code: 'ALREADY_VERIFIED',
        message: 'This OTP has already been used'
      });
    }

    // Increment attempts
    await db.collection('otp_requests').doc(reference).update({
      attempts: admin.firestore.FieldValue.increment(1),
      lastAttemptAt: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log('🔍 Verifying OTP for:', otpData.phoneNumber);

    // Verify OTP against stored value
    if (otp !== otpData.generatedOTP) {
      // Update status to failed
      await db.collection('otp_requests').doc(reference).update({
        status: 'failed',
        verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        failureReason: 'Invalid OTP provided'
      });

      return res.status(400).json({
        error: 'Invalid OTP',
        code: 'INVALID_OTP',
        message: 'The OTP you entered is incorrect',
        attemptsRemaining: otpData.maxAttempts - (otpData.attempts + 1)
      });
    }

    // OTP verification successful
    await db.collection('otp_requests').doc(reference).update({
      status: 'verified',
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      verifiedOtp: otp
    });

    console.log('✅ OTP verified successfully for:', otpData.phoneNumber);

    // Return success response
    res.json({
      success: true,
      message: 'OTP verified successfully',
      phoneNumber: otpData.phoneNumber.replace('tel:', ''),
      verifiedAt: new Date().toISOString(),
      subscriptionStatus: 'VERIFIED'
    });

  } catch (error) {
    console.error('❌ OTP verification error:', error.message);

    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to verify OTP'
    });
  }
});

// GET /api/otp/status/:reference - Check OTP status
router.get('/status/:reference', async (req, res) => {
  try {
    const { reference } = req.params;

    const db = getFirestore();
    const otpDoc = await db.collection('otp_requests').doc(reference).get();

    if (!otpDoc.exists) {
      return res.status(404).json({
        error: 'OTP request not found',
        code: 'OTP_NOT_FOUND'
      });
    }

    const otpData = otpDoc.data();
    const isExpired = new Date() > otpData.expiresAt.toDate();

    res.json({
      reference: reference,
      status: isExpired ? 'expired' : otpData.status,
      phoneNumber: otpData.phoneNumber.replace('tel:', ''),
      attempts: otpData.attempts,
      maxAttempts: otpData.maxAttempts,
      createdAt: otpData.createdAt.toDate().toISOString(),
      expiresAt: otpData.expiresAt.toDate().toISOString(),
      isExpired: isExpired
    });

  } catch (error) {
    console.error('❌ Status check error:', error.message);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR'
    });
  }
});

// POST /api/otp/register-client - Register phone number with client ID
router.post('/register-client', async (req, res) => {
  const endpoint = '/api/otp/register-client';
  
  try {
    // Log incoming request
    logRequest(req, endpoint);
    
    const { phoneNumber, clientId, clientInfo } = req.body;

    // Validate input
    if (!phoneNumber || !clientId) {
      return res.status(400).json({
        error: 'Phone number and client ID are required',
        code: 'MISSING_PARAMETERS'
      });
    }

    // Handle tel: format for phone number
    let formattedPhone;
    if (phoneNumber.startsWith('tel:')) {
      formattedPhone = phoneNumber; // Use as-is if already in tel: format
    } else {
      // Validate and format phone number if not in tel: format
      formattedPhone = validatePhoneNumber(phoneNumber);
      if (!formattedPhone) {
        return res.status(400).json({
          error: 'Invalid phone number format',
          code: 'INVALID_PHONE_NUMBER',
          message: 'Please provide a valid Sri Lankan mobile number or tel: format'
        });
      }
    }

    // Handle tel: format for client ID
    let formattedClientId;
    if (clientId.startsWith('tel:')) {
      formattedClientId = clientId; // Use as-is if already in tel: format
    } else {
      formattedClientId = clientId; // Use as-is for regular client IDs
    }

    const db = getFirestore();
    
    // Check if phone number already exists
    const existingClientQuery = await db.collection('client_mappings')
      .where('phoneNumber', '==', formattedPhone)
      .limit(1)
      .get();

    if (!existingClientQuery.empty) {
      // Update existing client
      const existingDoc = existingClientQuery.docs[0];
      await existingDoc.ref.update({
        clientId: formattedClientId,
        clientInfo: clientInfo || {},
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSeen: admin.firestore.FieldValue.serverTimestamp()
      });

      console.log('✅ Client mapping updated for:', formattedPhone);
      
      return res.json({
        success: true,
        message: 'Client mapping updated successfully',
        phoneNumber: formattedPhone,
        clientId: formattedClientId,
        action: 'updated'
      });
    } else {
      // Create new client mapping
      const clientData = {
        phoneNumber: formattedPhone,
        clientId: formattedClientId,
        clientInfo: clientInfo || {},
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
        isActive: true
      };

      await db.collection('client_mappings').add(clientData);

      console.log('✅ New client mapping created for:', formattedPhone);
      
      return res.json({
        success: true,
        message: 'Client mapping created successfully',
        phoneNumber: formattedPhone,
        clientId: formattedClientId,
        action: 'created'
      });
    }

  } catch (error) {
    console.error('❌ Client registration error:', error.message);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to register client'
    });
  }
});

// GET /api/otp/client/:phoneNumber - Get client ID by phone number
router.get('/client/:phoneNumber', async (req, res) => {
  try {
    const { phoneNumber } = req.params;

    // Handle tel: format for phone number
    let formattedPhone;
    if (phoneNumber.startsWith('tel:')) {
      formattedPhone = phoneNumber; // Use as-is if already in tel: format
    } else {
      // Validate and format phone number if not in tel: format
      formattedPhone = validatePhoneNumber(phoneNumber);
      if (!formattedPhone) {
        return res.status(400).json({
          error: 'Invalid phone number format',
          code: 'INVALID_PHONE_NUMBER',
          message: 'Please provide a valid Sri Lankan mobile number or tel: format'
        });
      }
    }

    const db = getFirestore();
    const clientQuery = await db.collection('client_mappings')
      .where('phoneNumber', '==', formattedPhone)
      .where('isActive', '==', true)
      .limit(1)
      .get();

    if (clientQuery.empty) {
      return res.status(404).json({
        error: 'Client not found',
        code: 'CLIENT_NOT_FOUND',
        message: 'No client mapping found for this phone number'
      });
    }

    const clientData = clientQuery.docs[0].data();
    
    res.json({
      success: true,
      phoneNumber: formattedPhone,
      clientId: clientData.clientId,
      clientInfo: clientData.clientInfo,
      createdAt: clientData.createdAt.toDate().toISOString(),
      lastSeen: clientData.lastSeen.toDate().toISOString()
    });

  } catch (error) {
    console.error('❌ Client lookup error:', error.message);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to lookup client'
    });
  }
});

// GET /api/otp/clients - Get all client mappings (for admin purposes)
router.get('/clients', async (req, res) => {
  try {
    const { limit = 50, offset = 0 } = req.query;
    
    const db = getFirestore();
    const clientsQuery = await db.collection('client_mappings')
      .where('isActive', '==', true)
      .orderBy('lastSeen', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();

    const clients = [];
    clientsQuery.forEach(doc => {
      const data = doc.data();
      clients.push({
        id: doc.id,
        phoneNumber: data.phoneNumber,
        clientId: data.clientId,
        clientInfo: data.clientInfo,
        createdAt: data.createdAt.toDate().toISOString(),
        lastSeen: data.lastSeen.toDate().toISOString()
      });
    });

    res.json({
      success: true,
      clients: clients,
      total: clients.length,
      limit: parseInt(limit),
      offset: parseInt(offset)
    });

  } catch (error) {
    console.error('❌ Clients list error:', error.message);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to retrieve clients'
    });
  }
});

// DELETE /api/otp/client/:phoneNumber - Deactivate client mapping
router.delete('/client/:phoneNumber', async (req, res) => {
  try {
    const { phoneNumber } = req.params;

    // Handle tel: format for phone number
    let formattedPhone;
    if (phoneNumber.startsWith('tel:')) {
      formattedPhone = phoneNumber; // Use as-is if already in tel: format
    } else {
      // Validate and format phone number if not in tel: format
      formattedPhone = validatePhoneNumber(phoneNumber);
      if (!formattedPhone) {
        return res.status(400).json({
          error: 'Invalid phone number format',
          code: 'INVALID_PHONE_NUMBER',
          message: 'Please provide a valid Sri Lankan mobile number or tel: format'
        });
      }
    }

    const db = getFirestore();
    const clientQuery = await db.collection('client_mappings')
      .where('phoneNumber', '==', formattedPhone)
      .where('isActive', '==', true)
      .limit(1)
      .get();

    if (clientQuery.empty) {
      return res.status(404).json({
        error: 'Client not found',
        code: 'CLIENT_NOT_FOUND',
        message: 'No active client mapping found for this phone number'
      });
    }

    const clientDoc = clientQuery.docs[0];
    await clientDoc.ref.update({
      isActive: false,
      deactivatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log('✅ Client mapping deactivated for:', formattedPhone);

    res.json({
      success: true,
      message: 'Client mapping deactivated successfully',
      phoneNumber: formattedPhone
    });

  } catch (error) {
    console.error('❌ Client deactivation error:', error.message);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: 'Failed to deactivate client'
    });
  }
});

module.exports = router;
