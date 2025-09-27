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
  
  // Override res.json to log responses
  const originalJson = res.json;
  res.json = function(data) {
    console.log(`\n📤 [${new Date().toISOString()}] ${req.method} ${req.originalUrl} - Status: ${res.statusCode}`);
    console.log(`📋 Response:`, JSON.stringify(data, null, 2));
    return originalJson.call(this, data);
  };
  
  next();
});

// mspace API configuration
const MSPACE_CONFIG = {
  baseURL: process.env.MSPACE_BASE_URL || 'https://api.mspace.lk',
  applicationId: process.env.MSPACE_APPLICATION_ID,
  password: process.env.MSPACE_PASSWORD,
  applicationHash: process.env.MSPACE_APPLICATION_HASH
};

// Phone number mapping for mspace (same as OTP)
const PHONE_TO_CLIENT_ID_MAPPING = {
  'tel:94714555151': '94714555151',
  'tel:94712345678': '94712345678',
  'tel:94776543210': '94776543210',
  'tel:94701234567': '94701234567',
  'tel:94787654321': '94787654321',
  'tel:94723456789': '94723456789',
  'tel:94734567890': '94734567890',
  'tel:94745678901': '94745678901',
  'tel:94756789012': '94756789012',
  'tel:94767890123': '94767890123',
  'tel:94778901234': '94778901234',
  'tel:94789012345': '94789012345',
  'tel:94790123456': '94790123456',
  'tel:94702315301': '94702315301',
  'tel:94712345678': '94712345678',
  'tel:94723456789': '94723456789',
  'tel:94734567890': '94734567890',
  'tel:94745678901': '94745678901',
  'tel:94756789012': '94756789012',
  'tel:94767890123': '94767890123',
  'tel:94778901234': '94778901234',
  'tel:94789012345': '94789012345',
  'tel:94790123456': '94790123456',
  'tel:94701234567': '94701234567',
  'tel:94711111111': '94711111111',
  'tel:94722222222': '94722222222',
  'tel:94733333333': '94733333333',
  'tel:94744444444': '94744444444',
  'tel:94755555555': '94755555555',
  'tel:94766666666': '94766666666',
  'tel:94777777777': '94777777777',
  'tel:94788888888': '94788888888',
  'tel:94799999999': '94799999999',
  'tel:94700000000': '94700000000'
};

// POST /api/emergency/alert - Send emergency alert to close contacts
router.post('/alert', async (req, res) => {
  const endpoint = '/api/emergency/alert';
  
  try {
    console.log(`🚨 [EMERGENCY ALERT] Starting emergency alert process`);
    
    const { userId, userName, latitude, longitude, timestamp } = req.body;
    
    // Validate required fields
    if (!userId || !userName || !latitude || !longitude) {
      return res.status(400).json({
        error: 'Missing required fields',
        code: 'MISSING_FIELDS',
        message: 'userId, userName, latitude, and longitude are required'
      });
    }
    
    console.log(`🚨 [EMERGENCY ALERT] Alert for user: ${userName} (${userId})`);
    console.log(`📍 [EMERGENCY ALERT] Location: ${latitude}, ${longitude}`);
    
    // Get user's close contacts
    const db = getFirestore();
    const contactsSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('contacts')
      .get();
    
    if (contactsSnapshot.empty) {
      console.log(`⚠️ [EMERGENCY ALERT] No close contacts found for user ${userId}`);
      return res.status(404).json({
        error: 'No close contacts found',
        code: 'NO_CONTACTS',
        message: 'User has no close contacts to alert'
      });
    }
    
    const contacts = contactsSnapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    console.log(`📞 [EMERGENCY ALERT] Found ${contacts.length} close contacts`);
    
    // Get user's current location info for Google Maps link
    const currentTime = new Date().toLocaleString('en-US', {
      timeZone: 'Asia/Colombo',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
    
    // Create Google Maps link
    const googleMapsLink = `https://maps.google.com/maps?q=${latitude},${longitude}`;
    
    // Prepare emergency message
    const emergencyMessage = `🚨 EMERGENCY ALERT from SafeStep 🚨

${userName} needs immediate assistance!

📍 Location: ${latitude}, ${longitude}
🕐 Time: ${currentTime}
🗺️ View on Google Maps: ${googleMapsLink}

This is an automated emergency alert. Please check on ${userName} immediately.

Stay Safe with SafeStep`;

    console.log(`📱 [EMERGENCY ALERT] Prepared message for ${contacts.length} contacts`);
    
    // Send SMS to each contact
    const results = [];
    let successCount = 0;
    let failureCount = 0;
    
    for (const contact of contacts) {
      try {
        const contactPhone = contact.phone;
        console.log(`📤 [EMERGENCY ALERT] Sending to ${contact.name} (${contactPhone})`);
        
        // Format phone number
        let formattedPhone;
        if (contactPhone.startsWith('tel:')) {
          formattedPhone = contactPhone;
        } else if (contactPhone.startsWith('0')) {
          formattedPhone = `tel:94${contactPhone.substring(1)}`;
        } else if (contactPhone.startsWith('94')) {
          formattedPhone = `tel:${contactPhone}`;
        } else {
          formattedPhone = `tel:94${contactPhone}`;
        }
        
        // Get client ID for mspace
        const clientId = PHONE_TO_CLIENT_ID_MAPPING[formattedPhone];
        if (!clientId) {
          console.log(`⚠️ [EMERGENCY ALERT] No client ID mapping for ${formattedPhone}`);
          results.push({
            contact: contact.name,
            phone: contactPhone,
            status: 'failed',
            error: 'No client ID mapping'
          });
          failureCount++;
          continue;
        }
        
        // Prepare mspace SMS request
        const mspaceSMSRequest = {
          version: "1.0",
          applicationId: MSPACE_CONFIG.applicationId,
          password: MSPACE_CONFIG.password,
          message: emergencyMessage,
          destinationAddresses: [clientId],
          deliveryStatusRequest: "0",
          encoding: "0"
        };
        
        console.log(`📤 [EMERGENCY ALERT] Sending SMS via mspace to ${clientId}`);
        
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
        if (mspaceResponse.data && mspaceResponse.data.statusCode === 'S1000') {
          console.log(`✅ [EMERGENCY ALERT] SMS sent successfully to ${contact.name}`);
          results.push({
            contact: contact.name,
            phone: contactPhone,
            status: 'success',
            messageId: mspaceResponse.data.requestId
          });
          successCount++;
        } else {
          console.log(`❌ [EMERGENCY ALERT] SMS failed for ${contact.name}:`, mspaceResponse.data);
          results.push({
            contact: contact.name,
            phone: contactPhone,
            status: 'failed',
            error: mspaceResponse.data?.statusDescription || 'Unknown error'
          });
          failureCount++;
        }
        
      } catch (error) {
        console.error(`❌ [EMERGENCY ALERT] Error sending to ${contact.name}:`, error.message);
        results.push({
          contact: contact.name,
          phone: contact.phone,
          status: 'failed',
          error: error.message
        });
        failureCount++;
      }
    }
    
    // Log emergency alert to Firebase
    await db.collection('emergency_alerts').add({
      userId: userId,
      userName: userName,
      latitude: latitude,
      longitude: longitude,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      contactsAlerted: contacts.length,
      successCount: successCount,
      failureCount: failureCount,
      results: results,
      googleMapsLink: googleMapsLink
    });
    
    console.log(`📊 [EMERGENCY ALERT] Summary: ${successCount} success, ${failureCount} failed`);
    
    res.json({
      success: true,
      message: 'Emergency alert sent to close contacts',
      data: {
        totalContacts: contacts.length,
        successCount: successCount,
        failureCount: failureCount,
        results: results,
        googleMapsLink: googleMapsLink,
        timestamp: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error(`❌ [EMERGENCY ALERT] Global error:`, error);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: error.message
    });
  }
});

module.exports = router;
