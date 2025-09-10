# SafeStep Flutter App Setup Guide

## Environment Configuration

The SafeStep app requires environment variables to function properly. Follow these steps to set up your environment:

### 1. Create Environment File

Create a `.env` file in the root directory of your project:

```bash
# Copy the example file
cp env.example .env
```

### 2. Configure Required Environment Variables

Edit the `.env` file and add your actual values:

```env
# Google Gemini AI API Key (REQUIRED)
# Get your API key from: https://makersuite.google.com/app/apikey
GEMINI_API_KEY=your_actual_gemini_api_key_here

# Optional: Add other environment variables as needed
# FIREBASE_PROJECT_ID=your_firebase_project_id
# FIREBASE_APP_ID=your_firebase_app_id
```

### 3. Get Your Gemini API Key

1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy the generated API key
5. Paste it in your `.env` file

### 4. Verify Configuration

After setting up your `.env` file:

1. Stop your Flutter app if it's running
2. Run `flutter clean` to clear build cache
3. Run `flutter pub get` to refresh dependencies
4. Restart your app

## Troubleshooting

### Common Error: "AI service is currently unavailable"

This error typically means:
- The `.env` file is missing
- The `GEMINI_API_KEY` is not set
- The API key is invalid or expired

### Debug Steps

1. **Check if `.env` file exists:**
   ```bash
   ls -la | grep .env
   ```

2. **Verify API key is loaded:**
   - Check the debug console for `[AI AGENT]` messages
   - Look for "GEMINI_API_KEY is missing or empty" errors

3. **Test API key manually:**
   ```bash
   curl "https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=YOUR_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"contents":[{"parts":[{"text":"Hello"}]}]}'
   ```

### Environment File Location

- **Development:** `.env` file in project root
- **Production:** Set environment variables in your deployment platform
- **Mobile builds:** The `.env` file is bundled with the app

### Security Notes

- **Never commit `.env` files** to version control
- The `.env` file is already in `.gitignore`
- Use different API keys for development and production
- Rotate API keys regularly

## API Usage Limits

- **Free tier:** 15 requests per minute
- **Paid tier:** Higher limits based on your plan
- **Rate limiting:** App will show appropriate error messages

## Support

If you continue to experience issues:

1. Check the debug console for detailed error messages
2. Verify your internet connection
3. Ensure your API key has the necessary permissions
4. Contact support with the error code and message

## Error Codes Reference

| Error Code | Description | Solution |
|------------|-------------|----------|
| `MISSING_API_KEY` | No API key configured | Create `.env` file with `GEMINI_API_KEY` |
| `INVALID_API_KEY` | API key format is invalid | Check API key length and format |
| `UNAUTHORIZED` | API key authentication failed | Verify API key is correct |
| `RATE_LIMITED` | Too many requests | Wait before sending another message |
| `SERVER_ERROR` | AI service is down | Try again later |
| `TIMEOUT` | Request took too long | Check internet connection |
| `NO_INTERNET` | No network connection | Check network settings |
