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

// Note: Client ID mappings are now stored in Firebase 'client_mappings' collection
// This provides better flexibility and allows dynamic registration of new phone numbers

// Function to get readable address from coordinates using reverse geocoding
async function getAddressFromCoordinates(latitude, longitude) {
  try {
    // Using OpenStreetMap Nominatim service (free, no API key required)
    const response = await axios.get(
      `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1`,
      {
        headers: {
          'User-Agent': 'SafeStep-Emergency-Alert/1.0'
        },
        timeout: 5000
      }
    );
    
    if (response.data && response.data.display_name) {
      // Extract the most relevant parts of the address
      const address = response.data.display_name;
      const addressParts = address.split(', ');
      
      // Take first 3-4 parts for a concise address
      const shortAddress = addressParts.slice(0, 4).join(', ');
      
      console.log(`[EMERGENCY ALERT] Reverse geocoded address: ${shortAddress}`);
      return shortAddress;
    }
    
    return null;
  } catch (error) {
    console.error(`[EMERGENCY ALERT] Reverse geocoding failed:`, error.message);
    return null;
  }
}

// POST /api/emergency/alert - Send emergency alert to close contacts
router.post('/alert', async (req, res) => {
  const endpoint = '/api/emergency/alert';
  
  try {
    console.log(`[EMERGENCY ALERT] Starting emergency alert process`);
    
    const { userId, userName, latitude, longitude, timestamp } = req.body;
    
    // Validate required fields
    if (!userId || !userName || !latitude || !longitude) {
      return res.status(400).json({
        error: 'Missing required fields',
        code: 'MISSING_FIELDS',
        message: 'userId, userName, latitude, and longitude are required'
      });
    }
    
    console.log(`[EMERGENCY ALERT] Alert for user: ${userName} (${userId})`);
    console.log(`[EMERGENCY ALERT] Location: ${latitude}, ${longitude}`);
    
    // Get user's actual name from Firebase
    const db = getFirestore();
    const userDoc = await db.collection('users').doc(userId).get();
    
    let actualUserName = userName; // Use provided name as fallback
    if (userDoc.exists) {
      const userData = userDoc.data();
      actualUserName = userData.name || userData.userName || userData.displayName || userName;
      console.log(`[EMERGENCY ALERT] Fetched user name from Firebase: ${actualUserName}`);
    } else {
      console.log(`[EMERGENCY ALERT] User document not found, using provided name: ${userName}`);
    }
    
    // Get user's close contacts
    const contactsSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('contacts')
      .get();
    
    if (contactsSnapshot.empty) {
      console.log(`[EMERGENCY ALERT] No close contacts found for user ${userId}`);
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
    
    console.log(`[EMERGENCY ALERT] Found ${contacts.length} close contacts`);
    
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
    
    // Get readable address from coordinates
    console.log(`[EMERGENCY ALERT] Getting address for coordinates: ${latitude}, ${longitude}`);
    const readableAddress = await getAddressFromCoordinates(latitude, longitude);
    
    // Create Google Maps link
    const googleMapsLink = `https://maps.google.com/maps?q=${latitude},${longitude}`;
    
    // Prepare location text (use address if available, fallback to coordinates)
    const locationText = readableAddress || `${latitude}, ${longitude}`;
    
    // Prepare emergency message
    const emergencyMessage = `EMERGENCY : ${actualUserName} needs immediate help

User: ${actualUserName}
Location: ${locationText}
Time: ${currentTime}
View on Google Maps: ${googleMapsLink}

This is an automated emergency alert. Please check on ${actualUserName} immediately.

Stay Safe with SafeStep`;

    console.log(`[EMERGENCY ALERT] Prepared message for ${contacts.length} contacts`);
    
    // Send SMS to each contact
    const results = [];
    let successCount = 0;
    let failureCount = 0;
    
    for (const contact of contacts) {
      try {
        const contactPhone = contact.phone;
        console.log(`[EMERGENCY ALERT] Sending to ${contact.name} (${contactPhone})`);
        
        // Format phone number with improved validation
        let formattedPhone;
        if (contactPhone.startsWith('tel:')) {
          formattedPhone = contactPhone;
        } else if (contactPhone.startsWith('0')) {
          // Sri Lankan format: 0714555151 -> tel:94714555151
          formattedPhone = `tel:94${contactPhone.substring(1)}`;
        } else if (contactPhone.startsWith('94')) {
          // Already has country code: 94714555151 -> tel:94714555151
          formattedPhone = `tel:${contactPhone}`;
        } else {
          // Assume local number: 714555151 -> tel:94714555151
          formattedPhone = `tel:94${contactPhone}`;
        }
        
        console.log(`[EMERGENCY ALERT] Formatted phone: ${contactPhone} -> ${formattedPhone}`);
        
        // Get client ID from Firebase client mappings (same as OTP service)
        const db = getFirestore();
        const clientQuery = await db.collection('client_mappings')
          .where('phoneNumber', '==', formattedPhone)
          .where('isActive', '==', true)
          .limit(1)
          .get();
        
        if (clientQuery.empty) {
          console.log(`[EMERGENCY ALERT] No client mapping found for ${formattedPhone}`);
          console.log(`[EMERGENCY ALERT] Please register this phone number using /api/otp/register-client`);
          results.push({
            contact: contact.name,
            phone: contactPhone,
            formattedPhone: formattedPhone,
            status: 'failed',
            error: `No client mapping found for ${formattedPhone}. Please register this phone number first.`
          });
          failureCount++;
          continue;
        }
        
        const clientData = clientQuery.docs[0].data();
        const clientId = clientData.clientId;
        
        console.log(`[EMERGENCY ALERT] Found client ID for ${formattedPhone}: ${clientId}`);
        
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
        
        console.log(`[EMERGENCY ALERT] Sending SMS via mspace to ${clientId}`);
        console.log(`[EMERGENCY ALERT] SMS Request:`, JSON.stringify(mspaceSMSRequest, null, 2));
        
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
          console.log(`[EMERGENCY ALERT] SMS sent successfully to ${contact.name}`);
          results.push({
            contact: contact.name,
            phone: contactPhone,
            status: 'success',
            messageId: mspaceResponse.data.requestId
          });
          successCount++;
        } else {
          console.log(`[EMERGENCY ALERT] SMS failed for ${contact.name}:`, mspaceResponse.data);
          results.push({
            contact: contact.name,
            phone: contactPhone,
            status: 'failed',
            error: mspaceResponse.data?.statusDescription || 'Unknown error'
          });
          failureCount++;
        }
        
      } catch (error) {
        console.error(`[EMERGENCY ALERT] Error sending to ${contact.name}:`, error.message);
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
      userName: actualUserName,
      originalUserName: userName, // Keep original for reference
      latitude: latitude,
      longitude: longitude,
      readableAddress: readableAddress,
      locationText: locationText,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      contactsAlerted: contacts.length,
      successCount: successCount,
      failureCount: failureCount,
      results: results,
      googleMapsLink: googleMapsLink
    });
    
    console.log(`[EMERGENCY ALERT] Summary: ${successCount} success, ${failureCount} failed`);
    
    res.json({
      success: true,
      message: 'Emergency alert sent to close contacts',
      data: {
        userId: userId,
        userName: actualUserName,
        originalUserName: userName,
        totalContacts: contacts.length,
        successCount: successCount,
        failureCount: failureCount,
        results: results,
        locationText: locationText,
        readableAddress: readableAddress,
        googleMapsLink: googleMapsLink,
        timestamp: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error(`[EMERGENCY ALERT] Global error:`, error);
    res.status(500).json({
      error: 'Internal server error',
      code: 'INTERNAL_ERROR',
      message: error.message
    });
  }
});

module.exports = router;
