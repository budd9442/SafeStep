const axios = require('axios');

const BACKEND_URL = 'http://localhost:3000';
const TEST_CLIENT_URL = 'http://localhost:3001';

class LocationServiceTester {
  constructor() {
    this.sessionId = null;
  }

  async runTests() {
    console.log('🧪 Starting Location Service Tests\n');

    try {
      // Test 1: Health checks
      await this.testHealthChecks();
      
      // Test 2: Test client endpoint
      await this.testClientEndpoint();
      
      // Test 3: Start location sharing
      await this.startLocationSharing();
      
      // Test 4: Monitor session for 30 seconds
      await this.monitorSession();
      
      // Test 5: Get location history
      await this.getLocationHistory();
      
      // Test 6: Test offline fallback
      await this.testOfflineFallback();
      
      // Test 7: Stop location sharing
      await this.stopLocationSharing();
      
      console.log('\n✅ All tests completed successfully!');
      
    } catch (error) {
      console.error('\n❌ Test failed:', error.message);
    }
  }

  async testHealthChecks() {
    console.log('🔍 Test 1: Health Checks');
    
    try {
      // Backend health check
      const backendHealth = await axios.get(`${BACKEND_URL}/health`);
      console.log('✅ Backend health check passed:', backendHealth.data.status);
      
      // Location service health check
      const locationHealth = await axios.get(`${BACKEND_URL}/api/location/health`);
      console.log('✅ Location service health check passed:', locationHealth.data.service);
      
      // Test client health check
      const clientHealth = await axios.get(`${TEST_CLIENT_URL}/health`);
      console.log('✅ Test client health check passed:', clientHealth.data.status);
      
    } catch (error) {
      throw new Error(`Health check failed: ${error.message}`);
    }
    
    console.log('');
  }

  async testClientEndpoint() {
    console.log('🔍 Test 2: Client Endpoint Test');
    
    try {
      const response = await axios.post(`${BACKEND_URL}/api/location/test-client`, {
        clientEndpoint: `${TEST_CLIENT_URL}/api/location`
      });
      
      console.log('✅ Client endpoint test passed');
      console.log('📍 Test result:', response.data.data.testResult);
      
    } catch (error) {
      throw new Error(`Client endpoint test failed: ${error.message}`);
    }
    
    console.log('');
  }

  async startLocationSharing() {
    console.log('🔍 Test 3: Start Location Sharing');
    
    try {
      const response = await axios.post(`${BACKEND_URL}/api/location/start`, {
        clientId: 'test_client_001',
        clientEndpoint: `${TEST_CLIENT_URL}/api/location`,
        phoneNumber: 'tel:+94712345678',
        metadata: {
          startedBy: 'test_script',
          purpose: 'testing_location_service'
        }
      });
      
      this.sessionId = response.data.data.sessionId;
      console.log('✅ Location sharing started successfully');
      console.log('📋 Session ID:', this.sessionId);
      console.log('⏱️ Polling interval:', response.data.data.pollingInterval + 'ms');
      
    } catch (error) {
      throw new Error(`Start location sharing failed: ${error.message}`);
    }
    
    console.log('');
  }

  async monitorSession() {
    console.log('🔍 Test 4: Monitor Session (30 seconds)');
    
    const startTime = Date.now();
    const duration = 30000; // 30 seconds
    
    while (Date.now() - startTime < duration) {
      try {
        const response = await axios.get(`${BACKEND_URL}/api/location/session/${this.sessionId}`);
        const sessionData = response.data.data;
        
        console.log(`📊 Session Status: ${sessionData.status}`);
        console.log(`📍 Total Updates: ${sessionData.totalLocationUpdates}`);
        console.log(`❌ Failed Attempts: ${sessionData.failedAttempts}`);
        
        if (sessionData.lastLocationData) {
          console.log(`🌍 Last Location: ${sessionData.lastLocationData.latitude}, ${sessionData.lastLocationData.longitude}`);
          console.log(`📡 Source: ${sessionData.lastLocationData.source}`);
        }
        
        console.log('---');
        
        // Wait 5 seconds before next check
        await this.sleep(5000);
        
      } catch (error) {
        console.error('❌ Error monitoring session:', error.message);
      }
    }
    
    console.log('');
  }

  async getLocationHistory() {
    console.log('🔍 Test 5: Get Location History');
    
    try {
      const response = await axios.get(`${BACKEND_URL}/api/location/history/${this.sessionId}?limit=10`);
      const history = response.data.data.history;
      
      console.log('✅ Location history retrieved');
      console.log(`📈 Total records: ${history.length}`);
      
      if (history.length > 0) {
        console.log('📍 Recent locations:');
        history.slice(0, 3).forEach((location, index) => {
          console.log(`  ${index + 1}. ${location.latitude}, ${location.longitude} (${location.source}) - ${location.receivedAt}`);
        });
      }
      
    } catch (error) {
      throw new Error(`Get location history failed: ${error.message}`);
    }
    
    console.log('');
  }

  async testOfflineFallback() {
    console.log('🔍 Test 6: Test Offline Fallback');
    
    try {
      // Simulate client going offline
      console.log('🔌 Simulating client offline...');
      await axios.post(`${TEST_CLIENT_URL}/api/simulate-offline`);
      
      // Wait a bit for the service to detect the offline state
      await this.sleep(10000);
      
      // Check session status
      const response = await axios.get(`${BACKEND_URL}/api/location/session/${this.sessionId}`);
      const sessionData = response.data.data;
      
      console.log(`📊 Failed attempts after offline: ${sessionData.failedAttempts}`);
      
      // Simulate client coming back online
      console.log('🔌 Simulating client online...');
      await axios.post(`${TEST_CLIENT_URL}/api/simulate-online`);
      
      // Wait for recovery
      await this.sleep(10000);
      
      const recoveryResponse = await axios.get(`${BACKEND_URL}/api/location/session/${this.sessionId}`);
      const recoveryData = recoveryResponse.data.data;
      
      console.log(`📊 Failed attempts after recovery: ${recoveryData.failedAttempts}`);
      console.log('✅ Offline fallback test completed');
      
    } catch (error) {
      console.warn('⚠️ Offline fallback test had issues:', error.message);
    }
    
    console.log('');
  }

  async stopLocationSharing() {
    console.log('🔍 Test 7: Stop Location Sharing');
    
    try {
      const response = await axios.post(`${BACKEND_URL}/api/location/stop`, {
        sessionId: this.sessionId
      });
      
      console.log('✅ Location sharing stopped successfully');
      console.log('📋 Session status:', response.data.data.status);
      
    } catch (error) {
      throw new Error(`Stop location sharing failed: ${error.message}`);
    }
    
    console.log('');
  }

  async sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Run tests if this file is executed directly
if (require.main === module) {
  const tester = new LocationServiceTester();
  tester.runTests().catch(console.error);
}

module.exports = LocationServiceTester;
