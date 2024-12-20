import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

List<Map<String, String>> otpRecords = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ParcelShieldApp());
}

String generateOtp() {
  Random random = Random();
  String otp = '';
  for (int i = 0; i < 8; i++) {
    otp += random.nextInt(10).toString(); // Generates a random digit (0-9)
  }
  return otp;
}

class ParcelShieldApp extends StatelessWidget {
  const ParcelShieldApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parcel Shield',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      ),
      home: const ParcelShieldHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ParcelShieldHomePage extends StatefulWidget {
  const ParcelShieldHomePage({Key? key}) : super(key: key);

  @override
  _ParcelShieldHomePageState createState() => _ParcelShieldHomePageState();
}

class _ParcelShieldHomePageState extends State<ParcelShieldHomePage> {
  late MqttBrowserClient client;
  String _otp = '';
  String _name = '';
  bool _isLoading = false;
  bool _hasPackage = false;
  String status = "Disconnected";

  @override
  void initState() {
    super.initState();
    setupMQTT();
    _loadOtpsFromFirestore();
  }

  void _loadOtpsFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance.collection('otps').get();
    setState(() {
    otpRecords = snapshot.docs.map((doc) {
      return {
        'name': doc['name'] as String,
        'otp': doc['otp'] as String,
        };
      }).toList();
    });

    print("Loaded OTPs: $otpRecords");
  }

  void setupMQTT() async {
    client = MqttBrowserClient('wss://broker.hivemq.com:8884/mqtt', 'flutter_client');
    client.port = 8884;
    client.logging(on: true);
    client.keepAlivePeriod = 20;

    // Set up connection message
    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean(); // Start with a clean session
        //.authenticateAs('broker', 'Password1'); // Use your HiveMQ Cloud credentials

    client.connectionMessage = connMessage;

    client.onConnected = () {
      print("Connected to the MQTT broker!");
      setState(() {
        status = "Connected";
      });
      subscribeToTopics();
    };

    client.onDisconnected = () {
      print("Disconnected from the MQTT broker.");
      setState(() {
        status = "Disconnected";
      });
      reconnect();
    };

    try {
      await client.connect();
    } catch (e) {
      print("Connection error: $e");
      setState(() {
        status = "Error: $e";
      });
    }
  }
  
  // Reconnect function
  void reconnect() async {
    // Ensure the client is not already connected
    if (client.connectionStatus!.state != MqttConnectionState.connected) {
      print("Attempting to reconnect...");
      try {
        await client.connect();
        print("Reconnected successfully!");
      } catch (e) {
        print("Reconnection failed: $e");
        // Optionally, retry after a short delay
        Future.delayed(const Duration(seconds: 5), reconnect);
      }
    }
  }

  void subscribeToTopics() {
    client.subscribe('alerts/fsr', MqttQos.atMostOnce);
    client.subscribe('alerts/alarm', MqttQos.atMostOnce);
    client.subscribe('otp/confirm', MqttQos.atMostOnce);

    client.updates!.listen((List<MqttReceivedMessage> messages) {
      final message = messages[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(message.payload.message);
      final topic = messages[0].topic;
      
      print("Message received on topic $topic: $payload");
      if (topic == 'alerts/fsr') {
        setState(() {
          _hasPackage = payload.toLowerCase() == 'present';
        });
      }
      else if (topic == 'alerts/alarm') {
        //send the user a push notification
      }
      else if (topic == 'otp/confirm') {
        bool otpVerify = otpRecords.any((record) => record['otp'] == _otp);
        publish(topic, otpVerify ? "yes" : "no");
      }
    });
  }

  void publish(String topic, String message) {
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
      print("message published to $topic: $message");
    } else {
      print("Client not connected, cannot send OTP.");
    }
  }

  void _requestOtp() {
    bool nameExists = otpRecords.any((record) => record['name'] == _name.toLowerCase());

    if (_name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a name before generating an OTP."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    else if (_name.length > 25 || _name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a name that is more than 3 and less than 25 characters."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    else if (nameExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a name that has not already been used."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    else if (otpRecords.length == 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Maximum of 5 OTPs at a time."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    else { // If the OTP name was valid, proceed
      setState(() {
        _isLoading = true;
      });

      Future.delayed(const Duration(seconds: 2), () async {
        setState(() {
          _otp = generateOtp();
          _isLoading = false;
        });

        // Add the OTP and name to the global map list
        Map<String, String> newRecord = {'name': _name.toLowerCase(), 'otp': _otp};
        otpRecords.add(newRecord);

        // Save to Firestore
        await FirebaseFirestore.instance.collection('otps').add(newRecord);

        print("OTP Records: $otpRecords");
      });
    }
  }

  void _deleteOtp(String name) async {
    setState(() {
      // Remove the OTP and name from the global map list
      otpRecords.removeWhere((record) => record['name'] == name);
    });
    
    final snapshot = await FirebaseFirestore.instance
      .collection('otps')
      .where('name', isEqualTo: name)
      .get();

    for (var doc in snapshot.docs) {
      await FirebaseFirestore.instance.collection('otps').doc(doc.id).delete();
    }

    print("OTP Records after delete: $otpRecords");
  }

  @override
  void dispose() {
    client.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parcel Shield'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 5,
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Welcome to Parcel Shield',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Secure your package with a One-Time Password (OTP).',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                // Input field for package name
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: TextField(
                        onChanged: (value) => setState(() => _name = value),
                        decoration: const InputDecoration(
                          labelText: "Package Name",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _requestOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 5,
                        shadowColor: Colors.blue.withOpacity(0.5),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            )
                          : const Text(
                              'Generate OTP',
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // Horizontal scrollable list for OTP names and OTPs
                if (otpRecords.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    // Take a maximum 5 entries
                    children: otpRecords.take(5).map((record) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Container(
                          // Fixed width so that 5 OTPs can fit on the page
                          width: 150,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                spreadRadius: 3,
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                record['name']!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                record['otp']!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              IconButton(
                                onPressed: () {
                                  _deleteOtp(record['name']!);
                                },
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 40),
                // Package status box
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: _hasPackage ? Colors.greenAccent.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _hasPackage ? Icons.check_circle : Icons.error,
                        color: _hasPackage ? Colors.green : Colors.red,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Text(
                       '${_hasPackage ? '' : 'No '}Package Present',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _hasPackage ? Colors.green : Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
