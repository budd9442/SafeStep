-- SafeStep Database Schema

-- Users table with phone-based authentication
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number VARCHAR(20) UNIQUE NOT NULL,
  name VARCHAR(100),
  email VARCHAR(255),
  date_of_birth DATE,
  profile_picture_url TEXT,
  subscription_status VARCHAR(20) DEFAULT 'UNREGISTERED',
  is_online BOOLEAN DEFAULT FALSE,
  last_seen TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE
);

-- OTP Sessions (for local OTP verification)
CREATE TABLE mspace_otp_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number VARCHAR(20) UNIQUE NOT NULL,
  reference_no VARCHAR(6) NOT NULL, -- 6-digit OTP
  status VARCHAR(20) DEFAULT 'PENDING',
  attempts INTEGER DEFAULT 0,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Emergency Contacts
CREATE TABLE emergency_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  phone_number VARCHAR(20) NOT NULL,
  relationship VARCHAR(50),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Emergency Alerts
CREATE TABLE emergency_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  alert_type VARCHAR(20) NOT NULL,
  location_lat DECIMAL(10,8),
  location_lng DECIMAL(11,8),
  message TEXT,
  mspace_message_id VARCHAR(50),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  ended_at TIMESTAMP
);

-- Location Sharing Sessions
CREATE TABLE location_sharing_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  contact_ids UUID[] NOT NULL,
  duration VARCHAR(20), -- '1h', '8h', 'always'
  is_active BOOLEAN DEFAULT TRUE,
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- User Locations (real-time from app)
CREATE TABLE user_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  latitude DECIMAL(10,8) NOT NULL,
  longitude DECIMAL(11,8) NOT NULL,
  accuracy DECIMAL(5,2),
  timestamp TIMESTAMP DEFAULT NOW(),
  source VARCHAR(20) DEFAULT 'app' -- 'app' or 'mspace'
);

-- mSpace Location Requests
CREATE TABLE mspace_location_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID REFERENCES users(id),
  subscriber_id UUID REFERENCES users(id),
  mspace_message_id VARCHAR(50),
  status VARCHAR(20) DEFAULT 'PENDING',
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  timestamp TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- SMS Delivery Reports
CREATE TABLE sms_delivery_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mspace_message_id VARCHAR(50),
  destination_address VARCHAR(20),
  delivery_status VARCHAR(20),
  timestamp VARCHAR(20),
  created_at TIMESTAMP DEFAULT NOW()
);

-- Danger Zones
CREATE TABLE danger_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_lat DECIMAL(10,8) NOT NULL,
  location_lng DECIMAL(11,8) NOT NULL,
  radius_meters INTEGER NOT NULL,
  description TEXT,
  reported_by UUID REFERENCES users(id),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Reports
CREATE TABLE reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(50) NOT NULL,
  location_lat DECIMAL(10,8),
  location_lng DECIMAL(11,8),
  description TEXT,
  severity VARCHAR(20),
  status VARCHAR(20) DEFAULT 'PENDING',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- User Sessions (for online status tracking)
CREATE TABLE user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  session_token VARCHAR(255) UNIQUE NOT NULL,
  device_id VARCHAR(255),
  fcm_token VARCHAR(500),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Chat Conversations (for AI chat history)
CREATE TABLE chat_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  mode VARCHAR(20) DEFAULT 'safe',
  language VARCHAR(20) DEFAULT 'auto',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Chat Messages
CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES chat_conversations(id) ON DELETE CASCADE,
  role VARCHAR(10) NOT NULL, -- 'user' or 'ai'
  content TEXT NOT NULL,
  risk_analysis TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for better performance
CREATE INDEX idx_users_phone_number ON users(phone_number);
CREATE INDEX idx_users_online ON users(is_online);
CREATE INDEX idx_user_locations_user_id ON user_locations(user_id);
CREATE INDEX idx_user_locations_timestamp ON user_locations(timestamp);
CREATE INDEX idx_location_sharing_user_id ON location_sharing_sessions(user_id);
CREATE INDEX idx_location_sharing_active ON location_sharing_sessions(is_active);
CREATE INDEX idx_emergency_alerts_user_id ON emergency_alerts(user_id);
CREATE INDEX idx_emergency_alerts_active ON emergency_alerts(is_active);
CREATE INDEX idx_danger_zones_location ON danger_zones(location_lat, location_lng);
CREATE INDEX idx_user_locations_location ON user_locations(latitude, longitude);
CREATE INDEX idx_otp_sessions_phone_number ON mspace_otp_sessions(phone_number);
CREATE INDEX idx_otp_sessions_status ON mspace_otp_sessions(status); 