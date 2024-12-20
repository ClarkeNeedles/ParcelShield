# ParcelShield

## Description:
 Anti-theft package storage system to combat against porch pirates

## Functionality
### Hardware:
 - Arduino as the brains of the device
 - 3D printed box to store the packages in
 - FSR to detect that a package is placed
 - Keypad that is used by the delivery driver in order to open the box
 - Key fob that is used by the admin to open the box a retrieve package
 - Buzzer that will sound if a package is stolen without authorization

### Software:
 - MQTT broker (HiveMQ) used as communication between Arduino and Flutter
 - Flutter Web App that generates OTPs
 - Enter the OTP into the delivery website so that the delivery driver can open the box and place the package
 - Web app was hosted using firebase
 - Still have to implement firestore for saving session data
 - Still have to implement firebase cloud messaging for push notifications
 - Notifying the user when a package is stolen or when a package has been delivered
