// นำเข้า Firebase SDK
importScripts('https://www.gstatic.com/firebasejs/8.2.3/firebase-app.js');
importScripts('https://www.gstatic.com/firebasejs/8.2.3/firebase-messaging.js');

// กำหนดค่าการเชื่อมต่อ Firebase
firebase.initializeApp({
  messagingSenderId: "669729897073"  // ใส่ค่าของ messagingSenderId ที่ได้จาก Firebase Console
});

// สร้างตัวแปรสำหรับจัดการการแจ้งเตือน
const messaging = firebase.messaging();

// ฟังก์ชันจัดการข้อความเมื่อแอปอยู่ใน background หรือไม่ได้เปิดหน้าเว็บ
messaging.setBackgroundMessageHandler(function(payload) {
  console.log('Handling background message', payload);

  const notificationTitle = 'Notification Title';  // ชื่อการแจ้งเตือน
  const notificationOptions = {
    body: payload.notification.body,  // ข้อความการแจ้งเตือน
    icon: '/firebase-logo.png'  // ไอคอนของการแจ้งเตือน
  };

  // แสดงการแจ้งเตือน
  return self.registration.showNotification(notificationTitle, notificationOptions);
});
