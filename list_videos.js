const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'reelai-a3565.firebasestorage.app'  // Updated bucket name
});

const bucket = admin.storage().bucket();

async function listFiles() {
  try {
    console.log('Attempting to list files from bucket:', bucket.name);
    const [files] = await bucket.getFiles({ prefix: 'videos/' });
    console.log('Files found:', files.length);
    files.forEach(file => {
      console.log(file.name);
    });
  } catch (error) {
    console.error('Error details:', error);
    console.log('Project ID:', serviceAccount.project_id);
    console.log('Bucket name:', bucket.name);
  }
}

listFiles().catch(console.error);
