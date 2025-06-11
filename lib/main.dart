import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart'; // ตรวจสอบให้แน่ใจว่ามีไฟล์นี้
import 'registration_page.dart'; // ตรวจสอบให้แน่ใจว่ามีไฟล์นี้
import 'firebase_notification_service.dart'; // ตรวจสอบให้แน่ใจว่ามีไฟล์นี้
import 'serial_communicationPage.dart'; // ตรวจสอบให้แน่ใจว่ามีไฟล์นี้
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart'; // เพิ่ม import สำหรับ SharedPreferences


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: "AIzaSyBinULhaoZsGBJ1BRyg3yxm0kUR9b5Y3wA",
      authDomain: "testcode-ec713.firebaseapp.com",
      databaseURL: "https://testcode-ec713-default-rtdb.firebaseio.com",
      projectId: "testcode-ec713",
      storageBucket: "testcode-ec713.firebasestorage.app",
      messagingSenderId: "669729897073",
      appId: "1:669729897073:web:7f09e6f88a86230db639d0",
      measurementId: "G-QT21GZXE11",
    ),
  );

  FirebaseNotificationService notificationService = FirebaseNotificationService();
  await notificationService.initialize();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // ปิด debug banner
      home: LoginPage(), // หน้าหลัก
    );
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // คีย์สำหรับเก็บอีเมลใน SharedPreferences
  static const String _rememberedEmailKey = 'remembered_email';

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail(); // โหลดอีเมลที่จำไว้เมื่อ initState
  }

  // ฟังก์ชันสำหรับโหลดอีเมลที่จำไว้
  Future<void> _loadRememberedEmail() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? rememberedEmail = prefs.getString(_rememberedEmailKey);
    if (rememberedEmail != null) {
      setState(() {
        _emailController.text = rememberedEmail;
      });
    }
  }

  // ฟังก์ชันสำหรับบันทึกอีเมล
  Future<void> _rememberEmail(String email) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedEmailKey, email);
  }

  Future<void> loginUser() async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // บันทึกอีเมลเมื่อเข้าสู่ระบบสำเร็จ
      _rememberEmail(_emailController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เข้าสู่ระบบสำเร็จ')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('เข้าสู่ระบบติดตามผู้ป่วยอัลไซเมอร์')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                labelText: 'อีเมล',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'รหัสผ่าน',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: loginUser,
              child: Text('เข้าสู่ระบบ'),
            ),
            SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RegisterPage()),
                );
              },
              child: Text(
                'ลงทะเบียน',
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}