const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

// Test configuration
const TEST_PHONE = '771234567'; // Replace with a real test number
const TEST_OTP = '123456'; // Replace with actual OTP received

async function testOTPFlow() {
  console.log('🧪 Testing SafeStep OTP Backend\n');

  try {
    // Test 1: Health Check
    console.log('1️⃣ Testing health check...');
    const healthResponse = await axios.get(`${BASE_URL}/health`);
    console.log('✅ Health check passed:', healthResponse.data);
    console.log('');

    // Test 2: Request OTP
    console.log('2️⃣ Testing OTP request...');
    const requestResponse = await axios.post(`${BASE_URL}/api/otp/request`, {
      phoneNumber: TEST_PHONE,
      applicationMetaData: {
        client: 'TEST_CLIENT',
        device: 'Test Device',
        os: 'Test OS'
      }
    });
    console.log('✅ OTP request successful:', requestResponse.data);
    
    const reference = requestResponse.data.reference;
    console.log('📱 Reference:', reference);
    console.log('');

    // Test 3: Check OTP Status
    console.log('3️⃣ Testing OTP status check...');
    const statusResponse = await axios.get(`${BASE_URL}/api/otp/status/${reference}`);
    console.log('✅ Status check successful:', statusResponse.data);
    console.log('');

    // Test 4: Verify OTP (this will likely fail with test OTP)
    console.log('4️⃣ Testing OTP verification...');
    try {
      const verifyResponse = await axios.post(`${BASE_URL}/api/otp/verify`, {
        reference: reference,
        otp: TEST_OTP
      });
      console.log('✅ OTP verification successful:', verifyResponse.data);
    } catch (verifyError) {
      console.log('⚠️ OTP verification failed (expected with test OTP):', verifyError.response?.data);
    }
    console.log('');

    console.log('🎉 All tests completed!');
    console.log('');
    console.log('📝 Next steps:');
    console.log('1. Check your phone for the actual OTP');
    console.log('2. Use the reference:', reference);
    console.log('3. Verify with the real OTP code');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    if (error.response) {
      console.error('Response data:', error.response.data);
    }
  }
}

// Test error handling
async function testErrorHandling() {
  console.log('\n🔍 Testing error handling...\n');

  try {
    // Test invalid phone number
    console.log('Testing invalid phone number...');
    await axios.post(`${BASE_URL}/api/otp/request`, {
      phoneNumber: '123'
    });
  } catch (error) {
    console.log('✅ Invalid phone error handled:', error.response.data);
  }

  try {
    // Test missing phone number
    console.log('Testing missing phone number...');
    await axios.post(`${BASE_URL}/api/otp/request`, {});
  } catch (error) {
    console.log('✅ Missing phone error handled:', error.response.data);
  }

  try {
    // Test invalid reference
    console.log('Testing invalid reference...');
    await axios.post(`${BASE_URL}/api/otp/verify`, {
      reference: 'INVALID_REF',
      otp: '123456'
    });
  } catch (error) {
    console.log('✅ Invalid reference error handled:', error.response.data);
  }
}

// Run tests
async function runTests() {
  await testOTPFlow();
  await testErrorHandling();
}

// Check if server is running
async function checkServer() {
  try {
    await axios.get(`${BASE_URL}/health`);
    return true;
  } catch (error) {
    console.error('❌ Server is not running on', BASE_URL);
    console.error('Please start the server with: npm run dev');
    return false;
  }
}

// Main execution
async function main() {
  const serverRunning = await checkServer();
  if (serverRunning) {
    await runTests();
  }
}

main().catch(console.error);
