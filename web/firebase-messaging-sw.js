importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDgj3kVzyQCfK-mtxgfVpgukKp9T3R_oTw',
  appId: '1:691116402438:web:ddfcc2bdc6b48ac1b02087',
  messagingSenderId: '691116402438',
  projectId: 'smart-cat-feeder-18b9e',
  authDomain: 'smart-cat-feeder-18b9e.firebaseapp.com',
  storageBucket: 'smart-cat-feeder-18b9e.firebasestorage.app',
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message:', payload);
  
  const notificationTitle = payload.notification?.title || 'Smart Cat Feeder';
  const notificationOptions = {
    body: payload.notification?.body || 'You have a new notification',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

