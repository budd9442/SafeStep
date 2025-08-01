# SafeStep Backend API

A comprehensive backend API for the SafeStep safety application with mSpace SMS integration for OTP verification and emergency notifications.

## Features

- **Phone-based Authentication**: Local OTP generation with mSpace SMS delivery
- **Emergency System**: Panic alerts with SMS notifications
- **Location Sharing**: Real-time location tracking with mSpace fallback
- **Danger Zones**: Community-reported unsafe areas
- **Emergency Contacts**: Contact management
- **Reports**: Incident reporting system
- **Chat History**: AI chat conversation storage
- **Real-time Updates**: WebSocket support for live features

## Technology Stack

- **Runtime**: Node.js
- **Framework**: Express.js
- **Database**: PostgreSQL
- **Authentication**: JWT
- **SMS Service**: mSpace API
- **Security**: Helmet, CORS, Rate Limiting
- **Scheduling**: node-cron

## Prerequisites

- Node.js 16+ 
- PostgreSQL 12+
- Redis (optional, for caching)

## Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd backend
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp env.example .env
   ```
   
   Edit `.env` with your configuration:
   ```env
   # Server Configuration
   PORT=3000
   NODE_ENV=development
   
   # Database Configuration
   DATABASE_URL=postgresql://username:password@localhost:5432/safestep_db
   
   # JWT Configuration
   JWT_SECRET=your_super_secret_jwt_key_here
   JWT_EXPIRES_IN=7d
   
   # mSpace Configuration
   MSPACE_BASE_URL=https://api.mspace.lk
   MSPACE_APPLICATION_ID=APP_008956
   MSPACE_PASSWORD=bab3f431230a12998b0b72296642a5f6
   MSPACE_VERSION=2.0
   MSPACE_APPLICATION_HASH=safestep_hash
   ```

4. **Set up database**
   ```bash
   # Create database
   createdb safestep_db
   
   # Run schema
   psql -d safestep_db -f src/database/schema.sql
   ```

5. **Start the server**
   ```bash
   # Development
   npm run dev
   
   # Production
   npm start
   ```

## API Endpoints

### Authentication

#### Request OTP
```http
POST /api/auth/request-otp
Content-Type: application/json

{
  "phoneNumber": "+94716177301"
}
```

**Response:**
```json
{
  "success": true,
  "message": "OTP sent successfully to your mobile number",
  "messageIds": ["msg_123456"]
}
```

#### Verify OTP
```http
POST /api/auth/verify-otp
Content-Type: application/json

{
  "phoneNumber": "+94716177301",
  "otp": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "user-uuid",
    "phoneNumber": "+94716177301",
    "name": "John Doe"
  },
  "message": "OTP verified successfully"
}
```

#### Refresh Token
```http
POST /api/auth/refresh-token
Content-Type: application/json

{
  "refreshToken": "your_refresh_token"
}
```

### Emergency System

#### Create Panic Alert
```http
POST /api/emergency/panic-alert
Authorization: Bearer <token>
Content-Type: application/json

{
  "location": {
    "latitude": 6.9271,
    "longitude": 79.8612
  },
  "message": "Emergency situation",
  "alertType": "panic"
}
```

#### Send Emergency SMS
```http
POST /api/emergency/send-sms
Authorization: Bearer <token>
Content-Type: application/json

{
  "destinationAddresses": ["+94716177302"],
  "message": "EMERGENCY: Your contact needs help!"
}
```

#### Request Location via mSpace
```http
POST /api/emergency/request-location
Authorization: Bearer <token>
Content-Type: application/json

{
  "requesterId": "user-uuid",
  "subscriberId": "target-user-uuid"
}
```

### Location Services

#### Update Location
```http
POST /api/location/update
Authorization: Bearer <token>
Content-Type: application/json

{
  "latitude": 6.9271,
  "longitude": 79.8612,
  "accuracy": 10.5
}
```

#### Start Location Sharing
```http
POST /api/location/start-sharing
Authorization: Bearer <token>
Content-Type: application/json

{
  "contactIds": ["contact-uuid-1", "contact-uuid-2"],
  "duration": "1h"
}
```

#### Get Shared Locations
```http
GET /api/location/shared
Authorization: Bearer <token>
```

### User Management

#### Get Profile
```http
GET /api/users/profile
Authorization: Bearer <token>
```

#### Update Profile
```http
POST /api/users/profile
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com",
  "dateOfBirth": "1990-01-01"
}
```

### Emergency Contacts

#### Get Emergency Contacts
```http
GET /api/users/emergency-contacts
Authorization: Bearer <token>
```

#### Add Emergency Contact
```http
POST /api/users/emergency-contacts
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "Emergency Contact",
  "phoneNumber": "+94716177302",
  "relationship": "spouse"
}
```

### Danger Zones

#### Get Nearby Danger Zones
```http
GET /api/emergency/danger-zones?latitude=6.9271&longitude=79.8612&radius=5
```

#### Report Danger Zone
```http
POST /api/emergency/danger-zones
Authorization: Bearer <token>
Content-Type: application/json

{
  "location": {
    "latitude": 6.9271,
    "longitude": 79.8612
  },
  "radius": 100,
  "description": "Unsafe area"
}
```

### Reports

#### Create Report
```http
POST /api/reports
Authorization: Bearer <token>
Content-Type: application/json

{
  "type": "harassment",
  "location": {
    "latitude": 6.9271,
    "longitude": 79.8612
  },
  "description": "Incident description",
  "severity": "high"
}
```

## OTP System

The backend uses a local OTP generation system with mSpace SMS delivery:

1. **Generate OTP**: Backend generates a random 6-digit OTP
2. **Send SMS**: OTP is sent via mSpace SMS API
3. **Store Session**: OTP is stored in database with 5-minute expiration
4. **Verify OTP**: User enters OTP, backend verifies against database
5. **Rate Limiting**: Maximum 3 attempts per OTP session

### OTP Security Features:
- 6-digit numeric OTP
- 5-minute expiration
- Maximum 3 verification attempts
- Rate limiting on OTP requests
- One-time use (OTP becomes invalid after successful verification)

## Location Sharing Logic

The backend implements intelligent location sharing:

1. **Online Users**: Get location directly from app
2. **Offline Users**: Request location via mSpace API
3. **Fallback**: Store mSpace location for offline access

### Location Priority:
1. Recent app location (< 5 minutes)
2. mSpace location request
3. Stored location data

## Security Features

- **Rate Limiting**: Prevents API abuse
- **Input Validation**: All inputs validated
- **JWT Authentication**: Secure token-based auth
- **CORS Protection**: Cross-origin request control
- **Helmet Security**: HTTP headers protection
- **OTP Security**: Time-limited, attempt-limited verification

## Scheduled Tasks

- **Location Sharing Cleanup**: Every hour
- **User Online Status**: Every 5 minutes
- **OTP Cleanup**: Every 10 minutes (clean expired OTPs)

## Error Handling

All endpoints return consistent error responses:

```json
{
  "success": false,
  "message": "Error description"
}
```

## Development

### Running Tests
```bash
npm test
```

### Database Migrations
```bash
npm run migrate
```

### Environment Variables

See `env.example` for all required environment variables.

## Production Deployment

1. Set `NODE_ENV=production`
2. Configure production database
3. Set secure JWT secret
4. Configure mSpace credentials
5. Set up reverse proxy (nginx)
6. Use PM2 for process management

## mSpace Integration

The backend uses mSpace for SMS functionality:

- **SMS Sending**: OTP delivery and emergency notifications
- **Location Requests**: For offline users
- **Delivery Reports**: SMS status tracking

## Support

For issues and questions, please contact the development team. 