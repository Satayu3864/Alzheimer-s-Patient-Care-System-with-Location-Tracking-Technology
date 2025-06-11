import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';


class TrackPatientLocation extends StatefulWidget {
  @override
  _TrackPatientLocationState createState() => _TrackPatientLocationState();
}

class _TrackPatientLocationState extends State<TrackPatientLocation> {
  String _locationMessage = "กำลังค้นหาตำแหน่ง...";
  late Position _currentPosition;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    // ตรวจสอบสิทธิ์ในการเข้าถึงตำแหน่ง
    LocationPermission permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied) {
      setState(() {
        _locationMessage = "ไม่สามารถเข้าถึงตำแหน่งได้ กรุณาเปิดการใช้งาน GPS";
      });
      return;
    }

    // ดึงข้อมูลตำแหน่งปัจจุบัน
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = position;
      _locationMessage = "ตำแหน่งของผู้ป่วย: ${position.latitude}, ${position.longitude}";
    });

    // ส่งตำแหน่งไปยัง Firebase
    _sendLocationToFirebase(position.latitude, position.longitude);
  }

  Future<void> _sendLocationToFirebase(double latitude, double longitude) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // ส่งตำแหน่งของผู้ป่วยไปยัง Firebase Firestore
    try {
      await FirebaseFirestore.instance.collection('patient_locations').doc(user.uid).set({
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ส่งข้อมูลตำแหน่งผู้ป่วยไปยังระบบเรียบร้อย')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการส่งตำแหน่ง: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ติดตามตำแหน่งผู้ป่วย')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_locationMessage, style: TextStyle(fontSize: 16)),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _getCurrentLocation,
                child: Text('อัปเดตตำแหน่ง'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
