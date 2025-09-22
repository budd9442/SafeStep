# SafeStep OTP Backend

A custom Node.js backend for OTP verification using mspace API and Firebase integration.

## Features

- 📱 **SMS OTP via mspace API** - Send and verify OTP using Sri Lankan SMS service
- 🔥 **Firebase Integration** - Store OTP requests and track verification status
- 🛡️ **Rate Limiting** - Prevent spam and abuse
- 🔒 **Security** - Helmet, CORS, input validation
- 📊 **Status Tracking** - Monitor OTP requests and verification attempts
- ⏰ **Expiration Handling** - Automatic OTP expiration after 5 minutes

## API Endpoints

### POST `/api/otp/request`
Request an OTP to be sent to a phone number.

**Request Body:**
```json
{
  "phoneNumber": "771234567",
  "applicationMetaData": {
    "client": "MOBILEAPP",
    "device": "Samsung S10",
    "os": "Android 12"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "OTP sent successfully",
  "reference": "REF_1234567890_abc123def",
  "expiresIn": 300,
  "phoneNumber": "771234567"
}
```

### POST `/api/otp/verify`
Verify an OTP code.

**Request Body:**
```json
{
  "reference": "REF_1234567890_abc123def",
  "otp": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "message": "OTP verified successfully",
  "phoneNumber": "771234567",
  "verifiedAt": "2024-01-15T10:30:00.000Z",
  "subscriptionStatus": "VERIFIED"
}
```

### GET `/api/otp/status/:reference`
Check the status of an OTP request.

**Response:**
```json
{
  "reference": "REF_1234567890_abc123def",
  "status": "pending",
  "phoneNumber": "771234567",
  "attempts": 1,
  "maxAttempts": 3,
  "createdAt": "2024-01-15T10:25:00.000Z",
  "expiresAt": "2024-01-15T10:30:00.000Z",
  "isExpired": false
}
```

## Setup Instructions

### 1. Install Dependencies
```bash
cd backend
npm install
```

### 2. Environment Configuration
Copy the example environment file and configure it:
```bash
cp .env.example .env
```

Edit `.env` with your actual values:
```env
# mspace API Configuration
MSPACE_BASE_URL=https://api.mspace.lk
MSPACE_APPLICATION_ID=APP_000375
MSPACE_PASSWORD=your_mspace_password
MSPACE_APPLICATION_HASH=your_application_hash

# Firebase Configuration
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY_HERE\n-----END PRIVATE KEY-----\n"
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com

# Server Configuration
PORT=3000
NODE_ENV=development
```

### 3. Firebase Setup
1. Go to Firebase Console → Project Settings → Service Accounts
2. Generate a new private key
3. Download the JSON file
4. Copy the values to your `.env` file

### 4. mspace API Setup
1. Contact mspace to get your application credentials
2. Update the `MSPACE_APPLICATION_ID` and `MSPACE_PASSWORD` in `.env`
3. Set your `MSPACE_APPLICATION_HASH` if required

### 5. Run the Server
```bash
# Development mode with auto-restart
npm run dev

# Production mode
npm start
```

## Phone Number Format

The backend accepts Sri Lankan mobile numbers in these formats:
- `771234567` (9 digits starting with 7)
- `94771234567` (12 digits with country code)
- `+94771234567` (with + prefix)

All numbers are automatically formatted to `tel:94771234567` for mspace API.

## Rate Limiting

- **5 requests per 15 minutes** per IP address
- **1 OTP request per minute** per phone number
- **3 verification attempts** per OTP

## Error Codes

| Code | Description |
|------|-------------|
| `MISSING_PHONE_NUMBER` | Phone number not provided |
| `INVALID_PHONE_NUMBER` | Invalid phone number format |
| `OTP_RATE_LIMITED` | Too many OTP requests |
| `MSPACE_API_ERROR` | mspace API error |
| `TIMEOUT` | Request timeout |
| `OTP_NOT_FOUND` | Invalid reference number |
| `OTP_EXPIRED` | OTP has expired |
| `MAX_ATTEMPTS_EXCEEDED` | Too many verification attempts |
| `INVALID_OTP` | Incorrect OTP code |
| `ALREADY_VERIFIED` | OTP already used |

## Health Check

Check if the server is running:
```bash
curl http://localhost:3000/health
```

## Development

The backend includes:
- **Express.js** for HTTP server
- **Axios** for mspace API calls
- **Firebase Admin SDK** for database operations
- **Helmet** for security headers
- **CORS** for cross-origin requests
- **Rate limiting** for abuse prevention

## Production Deployment

For production deployment:
1. Set `NODE_ENV=production`
2. Configure proper CORS origins
3. Use environment variables for all secrets
4. Set up proper logging and monitoring
5. Configure reverse proxy (nginx)
6. Use PM2 for process management

## Testing

Test the API endpoints using curl or Postman:

```bash
# Request OTP
curl -X POST http://localhost:3000/api/otp/request \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "771234567"}'

# Verify OTP
curl -X POST http://localhost:3000/api/otp/verify \
  -H "Content-Type: application/json" \
  -d '{"reference": "REF_1234567890_abc123def", "otp": "123456"}'
```
