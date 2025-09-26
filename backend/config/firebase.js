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
        console.log('📋 Project ID:', serviceAccount.project_id);
        console.log('📧 Client Email:', serviceAccount.client_email);
      } catch (fileError) {
        // Fall back to environment variables
        console.log('⚠️ Service account file not found, using environment variables');
        console.log('🔍 Checking environment variables...');
        
        const projectId = process.env.FIREBASE_PROJECT_ID;
        const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
        const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
        
        console.log('📋 Project ID:', projectId ? 'Set' : 'Missing');
        console.log('🔑 Private Key:', privateKey ? 'Set' : 'Missing');
        console.log('📧 Client Email:', clientEmail ? 'Set' : 'Missing');
        
        if (!projectId || !privateKey || !clientEmail) {
          throw new Error('Missing required Firebase environment variables. Please check FIREBASE_PROJECT_ID, FIREBASE_PRIVATE_KEY, and FIREBASE_CLIENT_EMAIL');
        }
        
        const serviceAccount = {
          projectId: projectId,
          privateKey: privateKey,
          clientEmail: clientEmail,
        };
        credential = admin.credential.cert(serviceAccount);
      }

      const projectId = process.env.FIREBASE_PROJECT_ID || 'safestep-d8237';
      const databaseURL = `https://${projectId}-default-rtdb.firebaseio.com`;
      
      console.log('🔗 Database URL:', databaseURL);
      
      admin.initializeApp({
        credential: credential,
        databaseURL: databaseURL
      });
    }

    db = admin.firestore();
    console.log('✅ Firebase initialized successfully');
    console.log('🗄️ Firestore database connected');
  } catch (error) {
    console.error('❌ Firebase initialization failed:', error.message);
    console.error('📚 Error details:', error);
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
