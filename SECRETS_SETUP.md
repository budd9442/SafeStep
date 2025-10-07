# Secrets Configuration Guide

This document explains how to set up the required API keys and credentials for SafeStep.

## ⚠️ IMPORTANT: Never Commit Secrets to Git

The following files contain sensitive information and are now gitignored:
- `backend/service.json`
- `android/app/google-services.json`
- `lib/firebase_options.dart`
- `.env`

## Required Secrets

### 1. Firebase Configuration

#### Backend Service Account (`backend/service.json`)
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings > Service Accounts
4. Click "Generate New Private Key"
5. Save the downloaded JSON file as `backend/service.json`
6. Use `backend/service.json.example` as a template reference

#### Android Google Services (`android/app/google-services.json`)
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings
4. Under "Your apps", select your Android app
5. Download `google-services.json`
6. Place it in `android/app/google-services.json`
7. Use `android/app/google-services.json.example` as a template reference

#### Flutter Firebase Options (`lib/firebase_options.dart`)
1. Install FlutterFire CLI: `dart pub global activate flutterfire_cli`
2. Run: `flutterfire configure`
3. Select your Firebase project
4. This will generate `lib/firebase_options.dart`
5. Use `lib/firebase_options.dart.example` as a template reference

### 2. Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Enable Maps SDK for Android
3. Create an API key
4. Add restrictions (Android apps with your package name)
5. Replace `YOUR_GOOGLE_MAPS_API_KEY_HERE` in:
   - `android/app/src/main/AndroidManifest.xml` (line 85)

### 3. Environment Variables

Create a `.env` file in the project root:

```env
# Gemini API Key for AI features
GEMINI_API_KEY=your_gemini_api_key_here
```

Create a `backend/.env` file:

```env
# Firebase Configuration
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=your-service-account@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY_HERE\n-----END PRIVATE KEY-----\n"

# MSpace Configuration (SMS service)
MSPACE_APPLICATION_ID=your_app_id
MSPACE_PASSWORD=your_password
MSPACE_API_KEY=your_api_key
MSPACE_SENDER_ID=your_sender_id

# Server Configuration
PORT=3000
NODE_ENV=development
```

Use `backend/.env.example` as a template.

## Verification Checklist

Before running the app, verify:

- [ ] `backend/service.json` exists and contains your Firebase service account key
- [ ] `android/app/google-services.json` exists
- [ ] `lib/firebase_options.dart` exists
- [ ] `.env` file exists in project root with `GEMINI_API_KEY`
- [ ] `backend/.env` file exists with all required variables
- [ ] Google Maps API key is set in `AndroidManifest.xml`
- [ ] All `.example` files have been copied and configured

## Security Best Practices

1. **Never commit** these files to version control
2. **Never share** these files publicly
3. **Rotate keys** regularly
4. **Use different keys** for development and production
5. **Set up API key restrictions** in Google Cloud Console
6. **Monitor usage** of your API keys

## Getting API Keys

- **Gemini API**: [Google AI Studio](https://makersuite.google.com/app/apikey)
- **Firebase**: [Firebase Console](https://console.firebase.google.com/)
- **Google Maps**: [Google Cloud Console](https://console.cloud.google.com/)

## Troubleshooting

If you encounter authentication errors:
1. Verify all files are in the correct locations
2. Check that API keys are not expired
3. Ensure Firebase project ID matches across all config files
4. Verify `.env` files are loaded correctly
5. Check that API services are enabled in Google Cloud Console
