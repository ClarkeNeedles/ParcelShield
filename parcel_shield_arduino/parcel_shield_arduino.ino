#include <WiFi.h>
#include <PubSubClient.h>

// Wifi details
const char* ssid = "Cracker boiz";
const char* password = "Xaviers3rdNut";

// HiveMQ Cloud details
const char* mqttServer = "broker.hivemq.com";
const int mqttPort = 1883;

// WiFiClientSecure to support TLS/SSL
WiFiClient wifiClient;
PubSubClient client(wifiClient);

const int fsrPin = A0; // FSR sensor connected to analog pin A0
int threshold = 900;// Int array to store the threshold values

void setup() {
  Serial.begin(9600);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.println("Connecting to WiFi...");
  } 
  Serial.println("Connected to WiFi");

  client.setServer(mqttServer, mqttPort);
  reconnect();
}

void loop() {
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  int fsrValue = analogRead(fsrPin);
  Serial.print("FSR Value: ");
  Serial.println(fsrValue);

  if (fsrValue > threshold) {
    client.publish("alerts/fsr", "present"); // Publish to the "alerts/fsr" topic
    delay(5000); // Don't overflood the broker
  }
  else {
    client.publish("alerts/fsr", "not present");
    delay(5000); // Don't overflood the broker
  }
}

void reconnect() {
  while (!client.connected()) {
    if (client.connect("arduino_client")) {
      Serial.println("Connected to MQTT broker");
    } else {
      Serial.print("Failed with state ");
      Serial.println(client.state());
      delay(2000);
    }
  }
}