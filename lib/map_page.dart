import 'dart:async';
import 'dart:convert'; // For JSON decoding
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart'; // ใช้สำหรับคำนวณระยะห่างและหาตำแหน่งปัจจุบันของเครื่อง
import 'package:http/http.dart' as http;
import 'package:testcode/safezone.dart'; // ตรวจสอบ path ให้ถูกต้อง: ควรแน่ใจว่าไฟล์ safezone.dart อยู่ในโฟลเดอร์เดียวกันหรือ path ถูกต้อง

// เพิ่ม Imports สำหรับ Firebase Auth และ Firestore
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  LatLng? _currentPatientPosition; // เปลี่ยนชื่อเป็น _currentPatientPosition เพื่อความชัดเจน
  LatLng? _currentUserLocation; // ตำแหน่งปัจจุบันของผู้ใช้ (คนดูแผนที่)

  // TODO: เปลี่ยน deviceID เป็น ID ที่ถูกต้องสำหรับอุปกรณ์ติดตามของคุณ
  final String deviceID = "icE1FNvXIIOVSxwG9si03rYaXXE2";

  Map<String, Map<String, dynamic>> _safeZones = {};
  StreamSubscription? _patientLocationSubscription; // เปลี่ยนชื่อเพื่อความชัดเจน
  StreamSubscription? _safeZoneSubscription;
  StreamSubscription? _userLocationStreamSubscription; // Subscription สำหรับตำแหน่งผู้ใช้

  Set<String> _currentlyInsideZoneIds = {};
  String _safeZoneStatusMessage = "กำลังตรวจสอบ...";

  // TODO: เปลี่ยน botToken และ chatId เป็นค่าที่ถูกต้องสำหรับ Telegram Bot ของคุณ
  final String botToken = "7411078912:AAF5ZfSBpCmQ2ojAmZswIoz05Hzvx-iTAzo";
  final String chatId = "7892088611";
  final Color _defaultZoneColor = Colors.blue;

  // --- Map icons ที่ให้เลือก (เหมือนใน SafeZonePage) ---
  final Map<String, IconData> availableIcons = {
    'default': Icons.location_pin,
    'home': Icons.home_filled,
    'school': Icons.school,
    'hospital': Icons.local_hospital,
    'work': Icons.work,
    'shop': Icons.shopping_cart,
    'restaurant': Icons.restaurant,
    'park': Icons.park,
    'train': Icons.train,
    'bus': Icons.directions_bus,
    'local_atm': Icons.local_atm,
    'local_police': Icons.local_police,
    'local_fire_department': Icons.local_fire_department,
    'fitness_center': Icons.fitness_center,
    // เพิ่มไอคอนอื่นๆ ที่นี่ตามต้องการ
  };

  // --- ตัวแปรสำหรับ URL รูปโปรไฟล์, ชื่อผู้ป่วย และสถานะการโหลด ---
  String? _userProfileImageUrl;
  String? _patientName;
  bool _isLoadingProfileImage = true;

  // --- สำหรับการนำทาง ---
  List<LatLng> _routePoints = []; // เก็บพิกัดเส้นทาง
  bool _isNavigating = false; // สถานะว่ากำลังนำทางอยู่หรือไม่

  @override
  void initState() {
    super.initState();
    print("--- MapPage initState ---");
    _fetchUserProfileData(); // ดึงข้อมูลรูปโปรไฟล์และชื่อผู้ป่วย
    _listenToRealtimePatientLocation(); // เริ่มฟังตำแหน่ง Realtime ของผู้ป่วย
    _listenToUserLocation(); // เริ่มฟังตำแหน่ง Realtime ของผู้ใช้ (เครื่องที่รันแอป)
    _listenToSafeZones(); // เริ่มฟังข้อมูล Safe Zones
  }

  @override
  void dispose() {
    print("--- MapPage dispose ---");
    _patientLocationSubscription?.cancel();
    _safeZoneSubscription?.cancel();
    _userLocationStreamSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // --- Helper Function เพื่อแปลง String ID เป็น IconData ---
  IconData _getIconFromString(String? iconId) {
    return availableIcons[iconId?.toLowerCase() ?? 'default'] ?? Icons.location_pin;
  }

  // --- ฟังก์ชันดึง URL รูปโปรไฟล์และชื่อผู้ป่วยจาก Firestore ---
  Future<void> _fetchUserProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() { _isLoadingProfileImage = false; });
      print("MapPage: No user logged in to fetch profile data.");
      return;
    }

    // สมมติว่าข้อมูลผู้ใช้ถูกเก็บไว้ใน collection 'user_info' และ doc id เป็น UID ของผู้ใช้
    final docRef = FirebaseFirestore.instance.collection('user_info').doc(user.uid);

    try {
      final docSnap = await docRef.get();
      if (!mounted) return;

      if (docSnap.exists) {
        final data = docSnap.data()!;
        if (mounted) {
          setState(() {
            _userProfileImageUrl = data['profileImageUrl'] as String?;
            _patientName = data['username'] as String?; // ดึงชื่อผู้ป่วยจาก Firestore
            _isLoadingProfileImage = false;
            print("MapPage: Fetched profile image URL: $_userProfileImageUrl, Name: $_patientName");
          });
        }
      } else {
        if (mounted) setState(() { _isLoadingProfileImage = false; });
        print("MapPage: User info document not found for UID: ${user.uid}. No profile image URL or name to display.");
      }
    } catch (e) {
      print("MapPage: Error fetching user profile image/name: $e");
      if (mounted) setState(() { _isLoadingProfileImage = false; });
    }
  }

  // --- ฟังการเปลี่ยนแปลงข้อมูล Safe Zones จาก Firebase Realtime Database ---
  void _listenToSafeZones() {
    _safeZoneSubscription?.cancel();
    print("MapPage: Listening to Safe Zones: safe_zones/$deviceID");
    _safeZoneSubscription =
        _database.child('safe_zones/$deviceID').onValue.listen((event) {
          if (!mounted) return;
          Map<String, Map<String, dynamic>> tempSafeZones = {};
          if (event.snapshot.exists) {
            final data = event.snapshot.value as Map?;
            if (data != null) {
              data.forEach((key, value) {
                if (value is Map) { // Check if 'value' is a Map before accessing keys
                  final latitudeValue = value['latitude'];
                  final longitudeValue = value['longitude'];
                  final radiusValue = value['radius'];

                  // Ensure all required fields exist and are of type num
                  if (latitudeValue is num && longitudeValue is num && radiusValue is num) {
                    try {
                      double latitude = latitudeValue.toDouble();
                      double longitude = longitudeValue.toDouble();
                      double radius = radiusValue.toDouble();

                      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 || radius <= 0) {
                        throw FormatException("Invalid coordinate or radius values for zone $key");
                      }

                      int? colorValue = value['color'] is int ? value['color'] : null;
                      String? iconId = value['iconId'] as String?;

                      Map<String, dynamic> zoneData = Map<String, dynamic>.from(value);
                      zoneData['name'] = value['name']?.toString() ?? key;
                      zoneData['colorValue'] = colorValue ?? _defaultZoneColor.value;
                      zoneData['latitude'] = latitude;
                      zoneData['longitude'] = longitude;
                      zoneData['radius'] = radius;
                      zoneData['iconId'] = iconId ?? 'default';

                      tempSafeZones[key] = zoneData;
                    } catch (e) {
                      print("MapPage: Error parsing safe zone data for key $key: $e");
                    }
                  } else {
                    print("MapPage: Skipping incomplete or invalid safe zone data (lat, lon, or radius not num) for key $key: $value");
                  }
                } else {
                  print("MapPage: Skipping non-map safe zone data for key $key");
                }
              });
            }
          }

          if (mounted) {
            if (_safeZones.toString() != tempSafeZones.toString()) {
              print("MapPage: Safe zones updated.");
              setState(() {
                _safeZones = tempSafeZones;
                if (_safeZones.isEmpty) { _currentlyInsideZoneIds.clear(); _safeZoneStatusMessage = "ยังไม่ได้กำหนดพื้นที่"; }
                _currentlyInsideZoneIds.removeWhere((id) => !_safeZones.containsKey(id));
              });
              _checkZoneStatusAndNotify(); // ตรวจสอบสถานะและแจ้งเตือนเมื่อ Safe Zones อัปเดต
            }
          }
        }, onError: (error) {
          print("MapPage: Error listening to safe zones: $error");
          if (mounted) { setState(() { _safeZones = {}; _currentlyInsideZoneIds.clear(); _safeZoneStatusMessage = "ข้อผิดพลาดในการโหลดพื้นที่"; }); }
        });
  }

  // --- ฟังการเปลี่ยนแปลงตำแหน่ง Real-time ของผู้ป่วยจาก Firebase Realtime Database ---
  void _listenToRealtimePatientLocation() {
    _patientLocationSubscription?.cancel();
    print("MapPage: Listening to Realtime Patient Location: locations/$deviceID");
    _patientLocationSubscription =
        _database.child('locations/$deviceID').onValue.listen((event) {
          if (!mounted) return;
          final data = event.snapshot.value;
          if (data != null && data is Map) {
            final latitudeValue = data['latitude'];
            final longitudeValue = data['longitude'];

            // Robust null and type checks before casting
            if (latitudeValue is num && longitudeValue is num) {
              try {
                double latitude = latitudeValue.toDouble();
                double longitude = longitudeValue.toDouble();
                if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) { throw FormatException("Invalid Lat/Lon values: $latitude, $longitude"); }
                LatLng newPosition = LatLng(latitude, longitude);
                if (_currentPatientPosition?.latitude != newPosition.latitude || _currentPatientPosition?.longitude != newPosition.longitude) {
                  print("MapPage: Patient Location changed: $newPosition");
                  LatLng? oldPosition = _currentPatientPosition;
                  setState(() { _currentPatientPosition = newPosition; });
                  if (oldPosition == null && _currentPatientPosition != null) {
                    // หากเป็นการรับตำแหน่งผู้ป่วยครั้งแรก ให้เลื่อนแผนที่ไปที่ตำแหน่งนั้น
                    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { try { _mapController.move(_currentPatientPosition!, 15.0); } catch (e) { print("MapPage: Error moving map on first patient location: $e"); } } });
                  }
                  _checkZoneStatusAndNotify(); // ตรวจสอบสถานะโซนและแจ้งเตือนทุกครั้งที่ตำแหน่งผู้ป่วยเปลี่ยน
                }
              } catch (e) { print("MapPage: Error parsing patient location data or invalid values: $e"); if (mounted) setState(() => _safeZoneStatusMessage = "ข้อผิดพลาดข้อมูลตำแหน่งผู้ป่วย"); }
            } else { // Handle cases where latitude or longitude are missing or not numbers
              if (mounted) setState(() => _safeZoneStatusMessage = "ข้อมูลตำแหน่งผู้ป่วยไม่สมบูรณ์ หรือไม่ถูกต้อง");
              print("MapPage: Patient Latitude or Longitude is not a number or is null in RealtimeDB for locations/$deviceID.");
            }
          } else { // Handle cases where data is null or not a Map
            if (mounted) setState(() => _safeZoneStatusMessage = "ไม่มีข้อมูลตำแหน่งผู้ป่วย");
            if (_currentPatientPosition != null) { setState(() => _currentPatientPosition = null); _checkZoneStatusAndNotify(); }
          }
        }, onError: (error) { print("MapPage: Error listening to patient location: $error"); if (mounted) setState(() => _safeZoneStatusMessage = "ข้อผิดพลาดในการรับตำแหน่งผู้ป่วย"); });
  }

  // --- ฟังการเปลี่ยนแปลงตำแหน่ง Real-time ของผู้ใช้ (เครื่องที่รันแอป) ---
  void _listenToUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled.');
      // Optionally show a message to the user or open settings
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('กรุณาเปิดบริการตำแหน่งเพื่อใช้งานฟังก์ชันนำทาง')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions are denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('คุณต้องอนุญาตเข้าถึงตำแหน่งเพื่อใช้งานฟังก์ชันนำทาง')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied, we cannot request permissions.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('คุณปฏิเสธการเข้าถึงตำแหน่งถาวร กรุณาไปตั้งค่าในระบบ')),
        );
      }
      return;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    _userLocationStreamSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentUserLocation = LatLng(position.latitude, position.longitude);
          print("MapPage: User Location updated: $_currentUserLocation");
          // ไม่จำเป็นต้องเลื่อนแผนที่ตามผู้ใช้ตลอดเวลา ถ้าผู้ใช้กำลังดูผู้ป่วยอยู่
        });
      }
    }, onError: (e) {
      print("MapPage: Error getting user location: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการรับตำแหน่งของคุณ')),
        );
      }
    });
  }


  // --- ตรวจสอบสถานะใน Safe Zone และส่ง Telegram เมื่อมีการเปลี่ยนแปลง (ปรับปรุงการแสดงระยะห่าง) ---
  void _checkZoneStatusAndNotify() {
    if (!mounted) return;
    final previousInsideZoneIds = Set<String>.from(_currentlyInsideZoneIds);
    final newInsideZoneIds = <String>{};
    String currentStatusMessage = "กำลังรอตำแหน่ง...";

    if (_currentPatientPosition == null) { // ตรวจสอบตำแหน่งผู้ป่วย
      currentStatusMessage = "กำลังรอตำแหน่ง...";
    } else if (_safeZones.isEmpty) {
      currentStatusMessage = "ยังไม่ได้กำหนดพื้นที่";
    } else {
      bool isInsideAny = false;
      List<String> insideZoneMessages = []; // เปลี่ยนเป็นเก็บข้อความพร้อมระยะห่าง
      String closestZoneName = "";
      double minDistanceOutside = double.infinity;

      _safeZones.forEach((zoneId, zoneData) {
        double? latitude = zoneData['latitude'] as double?;
        double? longitude = zoneData['longitude'] as double?;
        double? radius = (zoneData['radius'] as num).toDouble(); // Ensure radius is double
        String zoneName = zoneData['name'] ?? zoneId;

        // เพิ่มการตรวจสอบ null ที่นี่สำหรับ _currentPatientPosition ก่อนคำนวณ
        if (_currentPatientPosition != null && latitude != null && longitude != null && radius != null && radius > 0) {
          try {
            double distance = Geolocator.distanceBetween(
              _currentPatientPosition!.latitude, // ใช้ตำแหน่งผู้ป่วย
              _currentPatientPosition!.longitude, // ใช้ตำแหน่งผู้ป่วย
              latitude,
              longitude,
            );

            if (distance <= radius) {
              newInsideZoneIds.add(zoneId);
              insideZoneMessages.add("$zoneName (${distance.toInt()} ม. จากศูนย์กลาง)");
              isInsideAny = true;
            } else {
              // คำนวณระยะห่างถึงขอบเขตของโซนที่ใกล้ที่สุด หากอยู่นอกโซน
              double distanceToEdge = distance - radius;
              if (distanceToEdge < minDistanceOutside) {
                minDistanceOutside = distanceToEdge;
                closestZoneName = zoneName;
              }
            }
          } catch (e) {
            print("MapPage: Error processing zone $zoneId during check: $e");
          }
        } else {
          print("MapPage: Skipping check for incomplete/invalid zone data or null patient position for zone: $zoneId");
        }
      });

      if (isInsideAny) {
        currentStatusMessage = "อยู่ในพื้นที่: ${insideZoneMessages.join(', ')} ✅";
      } else {
        if (closestZoneName.isNotEmpty && minDistanceOutside != double.infinity) {
          currentStatusMessage = "อยู่นอกพื้นที่ปลอดภัย (${minDistanceOutside.toInt()} ม. ถึง $closestZoneName) ❌";
        } else {
          currentStatusMessage = "อยู่นอกพื้นที่ปลอดภัยทั้งหมด ❌";
        }
      }
    }

    // ตรวจจับการเข้าและออกจากโซนเพื่อส่ง Telegram
    final enteredZones = newInsideZoneIds.difference(previousInsideZoneIds);
    for (String zoneId in enteredZones) {
      String zoneName = _safeZones[zoneId]?['name'] ?? zoneId;
      print("MapPage: Status change: Entered zone '$zoneName' ($zoneId). Sending notification.");
      _sendTelegramMessage("เข้าสู่พื้นที่ $zoneName ✅");
    }
    final exitedZones = previousInsideZoneIds.difference(newInsideZoneIds);
    for (String zoneId in exitedZones) {
      String zoneName = _safeZones[zoneId]?['name'] ?? zoneId;
      print("MapPage: Status change: Exited zone '$zoneName' ($zoneId). Sending notification.");
      _sendTelegramMessage("ออกจากพื้นที่ $zoneName ❌");
    }

    // อัปเดต UI หากข้อความสถานะหรือรายการโซนที่อยู่ภายในมีการเปลี่ยนแปลง
    if (_safeZoneStatusMessage != currentStatusMessage || _currentlyInsideZoneIds.toString() != newInsideZoneIds.toString()) {
      setState(() {
        _safeZoneStatusMessage = currentStatusMessage;
        _currentlyInsideZoneIds = newInsideZoneIds;
      });
    }
  }

  // --- ฟังก์ชันสำหรับส่งข้อความไปยัง Telegram ---
  Future<void> _sendTelegramMessage(String message) async {
    if (botToken.isEmpty || chatId.isEmpty) {
      print("MapPage: Error: Bot token or Chat ID is empty.");
      return;
    }
    String url = "https://api.telegram.org/bot$botToken/sendMessage?chat_id=$chatId&text=${Uri.encodeComponent(message)}";
    print("MapPage: Sending Telegram: $message");
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        print("MapPage: Telegram sent successfully.");
      } else {
        print("MapPage: Failed Telegram send. Code: ${response.statusCode}, Body: ${response.body}");
      }
    } on TimeoutException catch (_) {
      print("MapPage: Error sending Telegram: Connection timed out.");
    } catch (e) {
      print("MapPage: Error sending Telegram: $e");
    }
  }

  // --- ฟังก์ชันสำหรับเลื่อนแผนที่ไปยังตำแหน่งปัจจุบันของผู้ป่วย ---
  void _goToPatientLocation() {
    if (!mounted) return;
    if (_currentPatientPosition != null) {
      try {
        _mapController.move(_currentPatientPosition!, 16.0); // ซูมที่ระดับ 16.0
        // เมื่อเลื่อนไปตำแหน่งผู้ป่วย ให้หยุดนำทาง
        if (_isNavigating) {
          setState(() {
            _isNavigating = false;
            _routePoints.clear();
          });
        }
      } catch(e) {
        print("MapPage: Error moving map to patient location: $e");
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ยังไม่มีข้อมูลตำแหน่งผู้ป่วยปัจจุบัน')),
      );
    }
  }

  // --- ฟังก์ชันสำหรับเริ่มต้น/หยุดการนำทางไปยังผู้ป่วย ---
  void _toggleNavigation() async {
    print("MapPage: _toggleNavigation called.");
    print("MapPage: _currentUserLocation: $_currentUserLocation");
    print("MapPage: _currentPatientPosition: $_currentPatientPosition");

    if (_isNavigating) {
      // If already navigating, stop navigation
      setState(() {
        _isNavigating = false;
        _routePoints.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('หยุดการนำทาง')),
      );
      return;
    }

    // Start navigation
    if (_currentUserLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถระบุตำแหน่งของคุณได้ กรุณาตรวจสอบการอนุญาตตำแหน่ง')),
      );
      print("MapPage: Cannot start navigation, user location is null.");
      return;
    }
    if (_currentPatientPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ยังไม่มีข้อมูลตำแหน่งผู้ป่วยที่จะนำทางไป')),
      );
      print("MapPage: Cannot start navigation, patient location is null.");
      return;
    }

    setState(() {
      _isNavigating = true;
      _routePoints.clear(); // Clear previous route
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('กำลังค้นหาเส้นทาง...')),
    );

    // OSRM Public Demo Server
    // Format: http://router.project-osrm.org/route/v1/driving/{lon1},{lat1};{lon2},{lat2}?overview=full&geometries=geojson

    // ใช้ ?. เพื่อป้องกัน NoSuchMethodError หากเป็น null
    final startLon = _currentUserLocation?.longitude;
    final startLat = _currentUserLocation?.latitude;
    final endLon = _currentPatientPosition?.longitude;
    final endLat = _currentPatientPosition?.latitude;

    // ตรวจสอบให้แน่ใจว่าค่าทั้งหมดไม่เป็น null ก่อนสร้าง URL
    if (startLon == null || startLat == null || endLon == null || endLat == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถเริ่มการนำทางได้: ตำแหน่งไม่สมบูรณ์')),
        );
        setState(() {
          _isNavigating = false;
          _routePoints.clear();
        });
      }
      print("MapPage: Navigation points are null after null-aware access. Exiting _toggleNavigation.");
      return;
    }

    final url = 'http://router.project-osrm.org/route/v1/driving/$startLon,$startLat;$endLon,$endLat?overview=full&geometries=geojson';

    print("MapPage: OSRM URL: $url");

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];

          if (geometry != null && geometry['coordinates'] != null) {
            List<dynamic> coordinates = geometry['coordinates'];
            List<LatLng> points = coordinates.map((coord) {
              return LatLng((coord[1] as num).toDouble(), (coord[0] as num).toDouble());
            }).toList();

            if (mounted) {
              setState(() {
                _routePoints = points;
                // Move map to show both user and patient, or the route
                if (points.isNotEmpty) {
                  // Calculate bounds including both start and end points
                  double minLat = [startLat, endLat].reduce((a, b) => a < b ? a : b);
                  double maxLat = [startLat, endLat].reduce((a, b) => a > b ? a : b);
                  double minLon = [startLon, endLon].reduce((a, b) => a < b ? a : b);
                  double maxLon = [startLon, endLon].reduce((a, b) => a > b ? a : b);

                  // Add some padding to the bounds
                  double latPadding = (maxLat - minLat) * 0.1; // 10% padding
                  double lonPadding = (maxLon - minLon) * 0.1;

                  _mapController.fitBounds(
                    LatLngBounds(
                      LatLng(minLat - latPadding, minLon - lonPadding),
                      LatLng(maxLat + latPadding, maxLon + lonPadding),
                    ),
                    options: FitBoundsOptions(padding: EdgeInsets.all(50.0)),
                  );
                } else {
                  _mapController.move(_currentUserLocation!, 15.0); // fallback if no route points
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('แสดงเส้นทางไปยังผู้ป่วยแล้ว')),
              );
              print("MapPage: Route found and displayed.");
            }
          } else {
            if (mounted) {
              setState(() { _isNavigating = false; _routePoints.clear(); });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('ไม่พบเส้นทางที่เหมาะสม')),
              );
            }
            print("MapPage: No geometry or coordinates in OSRM response.");
          }
        } else {
          if (mounted) {
            setState(() { _isNavigating = false; _routePoints.clear(); });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('ไม่พบเส้นทางที่เหมาะสม')),
            );
          }
          print("MapPage: No routes found in OSRM response.");
        }
      } else {
        if (mounted) {
          setState(() { _isNavigating = false; _routePoints.clear(); });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการค้นหาเส้นทาง: ${response.statusCode}')),
          );
        }
        print("MapPage: OSRM API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isNavigating = false; _routePoints.clear(); });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อเพื่อค้นหาเส้นทาง')),
        );
      }
      print("MapPage: Error fetching route from OSRM: $e");
    }
  }

  // --- ฟังก์ชันสำหรับไปยังหน้า Safe Zone Management ---
  void _goToSafeZonePage() {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SafeZonePage(
          // ส่งตำแหน่งปัจจุบันของผู้ป่วยเป็นค่าเริ่มต้นไปยังหน้า SafeZonePage
          initialPosition: _currentPatientPosition ?? LatLng(13.7563, 100.5018),
        ),
      ),
    ).then((_) {
      print("MapPage: Returned from SafeZonePage.");
      _checkZoneStatusAndNotify(); // ตรวจสอบสถานะอีกครั้งเมื่อกลับมาจากหน้า SafeZonePage
    });
  }


  // --- Build Method สำหรับสร้าง UI ของหน้า MapPage ---
  @override
  Widget build(BuildContext context) {
    // กำหนดจุดศูนย์กลางเริ่มต้นและระดับการซูม
    final LatLng initialCenter = _currentPatientPosition ?? LatLng(13.7563, 100.5018);
    final double initialZoom = _currentPatientPosition != null ? 15.0 : 10.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('แผนที่ติดตาม'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_input_component_outlined),
            onPressed: _goToSafeZonePage, // Correctly calling the method
            tooltip: 'จัดการพื้นที่ปลอดภัย',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: initialCenter,
              minZoom: 5.0,
              maxZoom: 18.0,
              zoom: initialZoom,
              interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate, // ไม่ให้หมุนแผนที่
            ),
            children: [
              // --- Layer สำหรับแผนที่พื้นฐาน (OpenStreetMap) ---
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.testcode', // ควรเปลี่ยนเป็นชื่อ package ของคุณ
              ),

              // --- Layer สำหรับวาดวงกลม Safe Zones ---
              if (_safeZones.isNotEmpty)
                CircleLayer(
                  circles: _safeZones.entries.map((entry) {
                    final id = entry.key;
                    final data = entry.value;
                    double? lat = data['latitude'] as double?;
                    double? lon = data['longitude'] as double?;
                    double? rad = (data['radius'] as num).toDouble();
                    if(lat==null||lon==null||rad==null||rad<=0) return null; // ตรวจสอบค่าที่ไม่ถูกต้อง

                    try {
                      final pos = LatLng(lat, lon);
                      final color = Color(data['colorValue'] ?? _defaultZoneColor.value);
                      final inside = _currentlyInsideZoneIds.contains(id); // ตรวจสอบว่าอยู่ในโซนนี้หรือไม่
                      return CircleMarker(
                        point: pos,
                        radius: rad,
                        useRadiusInMeter: true, // กำหนดรัศมีเป็นเมตร
                        color: color.withOpacity(inside ? 0.4 : 0.15), // สีวงกลมทึบกว่าเมื่ออยู่ข้างใน
                        borderColor: color.withOpacity(inside ? 0.9 : 0.5), // ขอบวงกลมชัดกว่าเมื่ออยู่ข้างใน
                        borderStrokeWidth: inside ? 2.5 : 1.0,
                      );
                    } catch (e){
                      print("MapPage: Error creating circle marker for zone $id: $e");
                      return null;
                    }
                  }).whereType<CircleMarker>().toList(), // กรองค่า null ออก
                ),

              // --- Layer สำหรับ Marker ของ Safe Zones (แสดงชื่อและไอคอน) ---
              if (_safeZones.isNotEmpty)
                MarkerLayer(
                  markers: _safeZones.entries.map((entry) {
                    final safeZoneId = entry.key;
                    final safeZoneData = entry.value;
                    double? latitude = safeZoneData['latitude'] as double?;
                    double? longitude = safeZoneData['longitude'] as double?;
                    String? name = safeZoneData['name'] as String?;
                    String? iconId = safeZoneData['iconId'] as String?;

                    if (latitude == null || longitude == null || name == null) return null;

                    try {
                      final position = LatLng(latitude, longitude);
                      final iconData = _getIconFromString(iconId); // แปลง ID ไอคอนเป็น IconData

                      return Marker(
                        point: position,
                        width: 120, // ความกว้างของ Marker
                        height: 55, // ความสูงของ Marker (ปรับให้พอดีกับไอคอนและชื่อ)
                        anchorPos: AnchorPos.align(AnchorAlign.bottom), // ตำแหน่งยึดของ Marker
                        builder: (ctx) => Column( // ใช้ Column เพื่อวางไอคอนและชื่อในแนวตั้ง
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // --- แสดงไอคอนของ Safe Zone ---
                            Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.85),
                                  shape: BoxShape.circle,
                                  boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: Offset(0, 1), ) ]
                              ),
                              child: Icon(
                                iconData,
                                size: 22,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                            SizedBox(height: 2),
                            // --- แสดงชื่อของ Safe Zone ---
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                name.isNotEmpty ? name : safeZoneId, // ใช้ชื่อที่กำหนด หรือ ID ถ้าไม่มีชื่อ
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis, // ตัดข้อความหากยาวเกิน
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      );
                    } catch (e) { print("MapPage: Error creating name/icon marker for zone $safeZoneId: $e"); return null; }
                  }).whereType<Marker>().toList(),
                ),

              // --- Marker สำหรับตำแหน่งปัจจุบันของผู้ป่วย (แสดงรูปโปรไฟล์และชื่อ) ---
              if (_currentPatientPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 120.0, // ความกว้างของ Marker เพื่อรองรับชื่อ
                      height: 60.0, // ความสูงของ Marker เพื่อรองรับชื่อ
                      point: _currentPatientPosition!,
                      anchorPos: AnchorPos.align(AnchorAlign.center), // ตำแหน่งยึดของ Marker
                      builder: (ctx) {
                        Widget markerContent;
                        // กำหนด Widget ที่จะแสดง (รูปโปรไฟล์/ไอคอน/Loading)
                        if (!_isLoadingProfileImage && _userProfileImageUrl != null && _userProfileImageUrl!.isNotEmpty) {
                          markerContent = Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.shade700.withOpacity(0.5), // เงารอบรูป
                                  blurRadius: 10.0,
                                  spreadRadius: 2.0,
                                  offset: Offset(0, 0),
                                ),
                              ],
                            ),
                            child: ClipOval( // ตัดรูปให้เป็นวงกลม
                              child: Image.network(
                                _userProfileImageUrl!,
                                width: 40.0,
                                height: 40.0,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  // หากโหลดรูปไม่ได้ ให้กลับไปแสดงไอคอนเริ่มต้น
                                  print("MapPage: Error loading profile image: $error");
                                  return Icon(
                                    Icons.location_history,
                                    color: Colors.red.shade700,
                                    size: 40.0,
                                    shadows: [ Shadow(blurRadius: 6.0, color: Colors.black.withOpacity(0.6), offset: Offset(2,2)) ],
                                  );
                                },
                              ),
                            ),
                          );
                        } else if (_isLoadingProfileImage) {
                          // แสดง CircularProgressIndicator ระหว่างโหลดรูปโปรไฟล์
                          markerContent = Center(
                            child: SizedBox(
                              width: 20.0,
                              height: 20.0,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red.shade700),
                            ),
                          );
                        } else {
                          // แสดงไอคอนเริ่มต้น หากไม่มีรูปโปรไฟล์หรือไม่สามารถโหลดได้
                          markerContent = Icon(
                            Icons.location_history,
                            color: Colors.red.shade700,
                            size: 40.0,
                            shadows: [ Shadow(blurRadius: 6.0, color: Colors.black.withOpacity(0.6), offset: Offset(2,2)) ],
                          );
                        }

                        // สร้าง Column เพื่อรวมรูปภาพ/ไอคอน และชื่อผู้ป่วย
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'ตำแหน่งผู้ป่วยปัจจุบัน', // Changed tooltip
                              child: markerContent, // ใช้ Widget ที่สร้างไว้ด้านบน
                            ),
                            if (_patientName != null && _patientName!.isNotEmpty) // แสดงชื่อผู้ป่วยถ้ามี
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _patientName!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),

              // --- Marker สำหรับตำแหน่งปัจจุบันของผู้ใช้ (เครื่องที่รันแอป) ---
              if (_currentUserLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 50.0,
                      height: 50.0,
                      point: _currentUserLocation!,
                      builder: (ctx) => Tooltip( // Added Tooltip for user location
                        message: 'ตำแหน่งของคนดูแล',
                        child: Icon(
                          Icons.person_pin_circle, // ไอคอนสำหรับตำแหน่งผู้ใช้
                          color: Colors.blue.shade700,
                          size: 40.0,
                          shadows: [ Shadow(blurRadius: 6.0, color: Colors.black.withOpacity(0.6), offset: Offset(2,2)) ],
                        ),
                      ),
                    ),
                  ],
                ),

              // --- Layer สำหรับวาดเส้นทาง (Polyline) ---
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.blue,
                      strokeWidth: 5.0,
                      isDotted: false, // สามารถตั้งเป็น true เพื่อให้เป็นเส้นประได้
                    ),
                  ],
                ),
            ],
          ),

          // --- แสดงสถานะ Safe Zone ปัจจุบัน (อยู่/นอกโซน, ระยะห่าง) ---
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: (_currentlyInsideZoneIds.isNotEmpty)
                        ? Colors.green.shade700 // สีเขียวเมื่ออยู่ในโซน
                        : (_safeZones.isEmpty || _currentPatientPosition == null) // ใช้ _currentPatientPosition
                        ? Colors.grey.shade700 // สีเทาเมื่อไม่มีข้อมูล/รอตำแหน่ง
                        : Colors.red.shade700, // สีแดงเมื่ออยู่นอกโซน
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: Offset(1,1))
                    ]
                ),
                child: Text(
                  _safeZoneStatusMessage,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

          // --- ปุ่มสำหรับนำแผนที่ไปยังตำแหน่งปัจจุบันของผู้ป่วย (เปลี่ยนไอคอน/tooltip) ---
          Positioned(
            bottom: 20.0,
            right: 15.0,
            child: FloatingActionButton(
              heroTag: "goToPatientLocationBtn",
              onPressed: _goToPatientLocation,
              tooltip: 'ไปยังตำแหน่งผู้ป่วย',
              child: Icon(Icons.location_on), // ไอคอนสำหรับผู้ป่วย
              mini: true,
              backgroundColor: Colors.white70,
              foregroundColor: Colors.redAccent,
            ),
          ),

          // --- ปุ่มสำหรับนำทางไปยังผู้ป่วย (เพิ่มใหม่) ---
          Positioned(
            bottom: 65.0, // ตำแหน่งสูงขึ้นจากปุ่มแรก
            right: 15.0,
            child: FloatingActionButton(
              heroTag: "toggleNavigationBtn",
              onPressed: _toggleNavigation,
              tooltip: _isNavigating ? 'หยุดการนำทาง' : 'นำทางไปยังผู้ป่วย',
              child: Icon(_isNavigating ? Icons.cancel : Icons.alt_route), // Changed icon for 'stop' state
              mini: true,
              backgroundColor: _isNavigating ? Colors.orangeAccent : Colors.lightGreen, // เปลี่ยนสีตามสถานะ
              foregroundColor: Colors.white,
            ),
          ),

          // --- ปุ่มสำหรับนำแผนที่ไปยังตำแหน่งปัจจุบันของผู้ใช้ (เพิ่มใหม่) ---
          Positioned(
            bottom: 110.0, // ตำแหน่งสูงขึ้นจากปุ่มที่สอง
            right: 15.0,
            child: FloatingActionButton(
              heroTag: "goToUserLocationBtn",
              onPressed: () {
                if (_currentUserLocation != null) {
                  _mapController.move(_currentUserLocation!, 16.0);
                  // เมื่อเลื่อนไปตำแหน่งผู้ใช้ ให้หยุดนำทาง
                  if (_isNavigating) {
                    setState(() {
                      _isNavigating = false;
                      _routePoints.clear();
                    });
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ไม่สามารถระบุตำแหน่งของคุณได้')),
                  );
                }
              },
              tooltip: 'ไปยังตำแหน่งของคุณ',
              child: Icon(Icons.my_location), // ไอคอนสำหรับตำแหน่งผู้ใช้
              mini: true,
              backgroundColor: Colors.white70,
              foregroundColor: Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }
}