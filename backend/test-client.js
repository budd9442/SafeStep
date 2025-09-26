const express = require('express');
const app = express();
const PORT = 3001;

// Mock location data
let currentLocation = {
  latitude: 6.9271, // Colombo, Sri Lanka
  longitude: 79.8612,
  accuracy: 10.5,
  timestamp: new Date().toISOString(),
  altitude: 15.2,
  speed: 0.0,
  heading: 180.0
};

// Simulate location changes
setInterval(() => {
  // Add small random variations to simulate movement
  currentLocation.latitude += (Math.random() - 0.5) * 0.0001;
  currentLocation.longitude += (Math.random() - 0.5) * 0.0001;
  currentLocation.accuracy = 5 + Math.random() * 10;
  currentLocation.timestamp = new Date().toISOString();
  currentLocation.speed = Math.random() * 5; // Random speed 0-5 m/s
  currentLocation.heading = Math.random() * 360;
}, 5000); // Update every 5 seconds

// Middleware
app.use(express.json());

// Location endpoint that the backend will poll
app.get('/api/location', (req, res) => {
  console.log(`📍 [TEST CLIENT] Location requested at ${new Date().toISOString()}`);
  
  res.json({
    success: true,
    ...currentLocation
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'OK',
    service: 'Test Location Client',
    timestamp: new Date().toISOString(),
    currentLocation: currentLocation
  });
});

// Simulate client going offline (for testing fallback)
let isOnline = true;
app.post('/api/simulate-offline', (req, res) => {
  isOnline = false;
  console.log('🔌 [TEST CLIENT] Simulating offline state');
  res.json({ message: 'Client is now offline' });
});

app.post('/api/simulate-online', (req, res) => {
  isOnline = true;
  console.log('🔌 [TEST CLIENT] Simulating online state');
  res.json({ message: 'Client is now online' });
});

// Modify location endpoint to simulate offline
app.get('/api/location', (req, res) => {
  if (!isOnline) {
    console.log('❌ [TEST CLIENT] Client is offline, returning error');
    return res.status(503).json({
      error: 'Service Unavailable',
      message: 'Client is offline'
    });
  }
  
  console.log(`📍 [TEST CLIENT] Location requested at ${new Date().toISOString()}`);
  
  res.json({
    success: true,
    ...currentLocation
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Test Location Client running on port ${PORT}`);
  console.log(`📍 Location endpoint: http://localhost:${PORT}/api/location`);
  console.log(`🔗 Health check: http://localhost:${PORT}/health`);
  console.log(`🔌 Simulate offline: POST http://localhost:${PORT}/api/simulate-offline`);
  console.log(`🔌 Simulate online: POST http://localhost:${PORT}/api/simulate-online`);
});

module.exports = app;
