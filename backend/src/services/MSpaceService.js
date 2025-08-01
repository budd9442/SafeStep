const axios = require('axios');

class MSpaceService {
  constructor() {
    this.baseURL = process.env.MSPACE_BASE_URL || 'https://api.mspace.lk';
    this.applicationId = process.env.MSPACE_APPLICATION_ID || 'APP_008956';
    this.password = process.env.MSPACE_PASSWORD || 'bab3f431230a12998b0b72296642a5f6';
    this.version = process.env.MSPACE_VERSION || '2.0';
  }

  // Generate random OTP
  generateOTP() {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  // Send OTP via SMS
  async sendOTPSMS(phoneNumber, otp) {
    try {
      const message = `Your SafeStep verification code is: ${otp}. Valid for 5 minutes.`;
      
      const payload = {
        version: this.version,
        applicationId: this.applicationId,
        password: this.password,
        message,
        destinationAddresses: [`tel:${phoneNumber}`],
        sourceAddress: "SAFESTEP",
        deliveryStatusRequest: "1"
      };

      console.log('mSpace SMS Payload:', payload);

      const response = await axios.post(`${this.baseURL}/sms/send`, payload, {
        headers: { 
          'Content-Type': 'application/json;charset=utf-8',
          'Accept': 'application/json'
        }
      });

      const data = response.data;
      console.log('mSpace SMS Response:', data);
      
      if (data.statusCode === 'S1000') {
        return {
          success: true,
          messageIds: data.destinationResponses.map(resp => resp.messageId),
          statusDetail: data.statusDetail
        };
      } else {
        throw new Error(`mSpace Error: ${data.statusDetail} (${data.statusCode})`);
      }
    } catch (error) {
      console.error('mSpace SMS Error:', error.response?.data || error.message);
      throw new Error(`Failed to send SMS: ${error.response?.data?.statusDetail || error.message}`);
    }
  }

  // Send SMS for emergency alerts
  async sendSMS(destinationAddresses, message) {
    try {
      const payload = {
        version: this.version,
        applicationId: this.applicationId,
        password: this.password,
        message,
        destinationAddresses: destinationAddresses.map(addr => `tel:${addr}`),
        sourceAddress: "SAFESTEP",
        deliveryStatusRequest: "1"
      };

      console.log('mSpace SMS Payload:', payload);

      const response = await axios.post(`${this.baseURL}/sms/send`, payload, {
        headers: { 
          'Content-Type': 'application/json;charset=utf-8',
          'Accept': 'application/json'
        }
      });

      const data = response.data;
      console.log('mSpace SMS Response:', data);
      
      if (data.statusCode === 'S1000') {
        return {
          success: true,
          messageIds: data.destinationResponses.map(resp => resp.messageId),
          statusDetail: data.statusDetail
        };
      } else {
        throw new Error(`mSpace Error: ${data.statusDetail} (${data.statusCode})`);
      }
    } catch (error) {
      console.error('mSpace SMS Error:', error.response?.data || error.message);
      throw new Error(`Failed to send SMS: ${error.response?.data?.statusDetail || error.message}`);
    }
  }

  // Request location via mSpace
  async requestLocation(requesterId, subscriberId) {
    try {
      const payload = {
        applicationId: this.applicationId,
        password: this.password,
        version: this.version,
        requesterId: `tel:${requesterId}`,
        subscriberId: `tel:${subscriberId}`,
        serviceType: "IMMEDIATE"
      };

      console.log('mSpace Location Request Payload:', payload);

      const response = await axios.post(`${this.baseURL}/lbs/request`, payload, {
        headers: { 
          'Content-Type': 'application/json;charset=utf-8',
          'Accept': 'application/json'
        }
      });

      const data = response.data;
      console.log('mSpace Location Response:', data);
      
      if (data.statusCode === 'S1000') {
        return {
          success: true,
          latitude: data.latitude,
          longitude: data.longitude,
          timestamp: data.timestamp,
          subscriberState: data.subscriberState,
          messageID: data.messageID
        };
      } else {
        throw new Error(`mSpace Error: ${data.statusDetail} (${data.statusCode})`);
      }
    } catch (error) {
      console.error('mSpace Location Request Error:', error.response?.data || error.message);
      throw new Error(`Failed to request location: ${error.response?.data?.statusDetail || error.message}`);
    }
  }

  // Handle delivery report
  async handleDeliveryReport(reportData) {
    try {
      console.log('mSpace Delivery Report:', reportData);
      
      // Store delivery report in database
      await this.storeDeliveryReport(reportData);
      
      return {
        success: true,
        message: 'Delivery report processed'
      };
    } catch (error) {
      console.error('mSpace Delivery Report Error:', error);
      throw new Error(`Failed to process delivery report: ${error.message}`);
    }
  }

  // Store delivery report
  async storeDeliveryReport(reportData) {
    // This would be implemented with your database connection
    const { destinationAddress, timeStamp, requestId, deliveryStatus } = reportData;
    
    // Example implementation - replace with your actual database logic
    console.log('Storing delivery report:', {
      mspace_message_id: requestId,
      destination_address: destinationAddress,
      delivery_status: deliveryStatus,
      timestamp: timeStamp
    });
  }
}

module.exports = MSpaceService; 