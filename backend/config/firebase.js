const admin = require('firebase-admin');

let db;

const initializeFirebase = () => {
  try {
    // Check if Firebase is already initialized
    if (admin.apps.length === 0) {
      // Use service account file if available, otherwise fall back to environment variables
      let credential;
      
      try {
        // Try to load service account from file
        const serviceAccount = require('../service.json');
        credential = admin.credential.cert(serviceAccount);
        console.log('📁 Using Firebase service account file');
      } catch (fileError) {
        // Fall back to environment variables
        console.log('⚠️ Service account file not found, using environment variables');
        const serviceAccount = {
          projectId: process.env.FIREBASE_PROJECT_ID,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        };
        credential = admin.credential.cert(serviceAccount);
      }

      admin.initializeApp({
        credential: credential,
        databaseURL: `https://${process.env.FIREBASE_PROJECT_ID || 'safestep-d8237'}-default-rtdb.firebaseio.com`
      });
    }

    db = admin.firestore();
    console.log('✅ Firebase initialized successfully');
  } catch (error) {
    console.error('❌ Firebase initialization failed:', error.message);
    throw error;
  }
};

const getFirestore = () => {
  if (!db) {
    throw new Error('Firebase not initialized');
  }
  return db;
};

module.exports = {
  initializeFirebase,
  getFirestore,
  admin
};
