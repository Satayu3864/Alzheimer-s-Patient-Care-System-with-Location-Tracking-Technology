import 'package:flutter/material.dart';
import 'serial_communication_page.dart';  // นำเข้าหน้าใหม่ที่คุณสร้างขึ้น

void main() {
  runApp(MyApp());
}

class SerialCommunicationPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Serial Communication')),
      body: Center(child: Text('This is the Serial Communication Page')),
    );
  }
}
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Serial Communication',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MainPage(),
    );
  }
}

class MainPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Main Page'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // เมื่อกดปุ่มนี้จะเปิดหน้าจอการเชื่อมต่อกับ ESP32
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SerialCommunicationPage()),
            );
          },
          child: Text('Go to Serial Communication Page'),
        ),
      ),
    );
  }
}
