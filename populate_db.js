const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: `https://reelai-a3565-default-rtdb.firebaseio.com`
});

const db = admin.database();
const ref = db.ref('videos');

async function populateDB() {
  const videos = [
    "009885C1-20EA-4A40-8ADA-BCC89D12A791.mp4",
    "069558C8-90DB-4FC2-9502-EB8ABE1E62ED.mp4",
    "2312E9EC-BCBA-4407-8D2A-B18288B5722C.mp4",
    "26E6C92C-7491-4F83-BD47-FCCE49528143.mp4",
    "3A9486E7-64D1-422E-A60E-56B838A3A9FF.mp4",
    "3D8AE74A-3126-4E0B-85E0-718067838DFC.mp4",
    "42D5FC66-D7D2-4E6F-8A43-EBD08CAAFCA2.mp4",
    "4A7F7ED6-7342-42D8-BB9C-CA98BC50963B.mp4",
    "4AC15908-6D33-4E35-8F7B-5895BADA36C5.mp4",
    "4D3B86C9-FE10-412D-A079-C82CC1B521EC.mp4",
    "6A1FF63B-1C01-4BA2-A304-F47DD69A3491.mp4",
    "6B320102-9E2E-462F-81F3-569F6ABB883E.mp4",
    "77F65EFF-D832-4B8C-A819-5D7FF40E58EC.mp4",
    "796448E9-72F7-4F25-854F-AFBC7B134680.mp4",
    "7C4C95D3-5324-4BDA-BA7C-23F99A7669D2.mp4",
    "7FE4A82E-51B1-4286-B536-63879B76EF62.mp4",
    "853965E3-F9A9-4050-AD39-B3855000EAA0.mp4",
    "9ECCD974-968F-4E4E-B940-7431CA52FF0A.mp4",
    "A7F36218-8C6C-48F3-9ABD-AD138CBED842.mp4",
    "ABA43B3A-8B3D-4002-B6BF-D7C2A500CC17.mp4",
    "AC89159D-AEEA-4B08-A3D7-1528228ADE8F.mp4",
    "D0D971D9-B96A-4205-84A7-C7503B9076AD.mp4",
    "D3166EE3-1AE1-48DD-A4FA-0E21C9A111F2.mp4",
    "E9A3503C-A684-4D16-A8FC-A08E74E2104F.mp4",
    "FF2454BC-7AD8-4BB9-9874-A170089F97F7.mp4"
  ];

  const updates = {};
  videos.forEach((videoName, index) => {
    updates[`video${index + 1}`] = {
      videoName,
      timestamp: Date.now() - (index * 1000) // Stagger timestamps
    };
  });

  try {
    await ref.update(updates);
    console.log('Database populated successfully');
  } catch (error) {
    console.error('Error populating database:', error);
  }
  process.exit();
}

populateDB();
