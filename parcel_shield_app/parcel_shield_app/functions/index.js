const mqtt = require('mqtt');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

const messaging = admin.messaging();

// MQTT Broker Connection
const mqttHost = 'mqtt://broker.hivemq.com'; // Replace with your broker address
const mqttTopic = 'alerts/fsr'; // Replace with your topic

const mqttClient = mqtt.connect(mqttHost);

mqttClient.on('connect', () => {
  console.log('Connected to MQTT broker');
  mqttClient.subscribe(mqttTopic, (err) => {
    if (!err) {
      console.log(`Subscribed to topic: ${mqttTopic}`);
    } else {
      console.error(`Failed to subscribe to topic: ${mqttTopic}`);
    }
  });
});

mqttClient.on('message', async (topic, message) => {
  console.log(`Message received on topic ${topic}: ${message.toString()}`);

  if (message.toString() === 'FSR threshold reached') {
    try {
      await messaging.send({
        notification: {
          title: 'Parcel Shield Alert',
          body: 'The FSR threshold has been reached. Check your package status!',
        },
        webpush: {
          fcmOptions: {
            link: 'https://flutter-web-46762.web.app/', // Replace with your hosted Flutter web app URL
          },
        },
        topic: 'alerts/fsr', // Use a topic or target specific device tokens
      });
      console.log('Notification sent successfully.');
    } catch (error) {
      console.error('Error sending notification:', error);
    }
  }
});
