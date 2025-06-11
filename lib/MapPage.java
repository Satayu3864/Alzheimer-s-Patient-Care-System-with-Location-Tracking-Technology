import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Ensure this import exists
import 'package:geolocator/geolocator.dart'; // Import Geolocator
import 'package:http/http.dart' as http; // Import HTTP
import 'package:testcode/safezone.dart'; // Assuming SafeZonePage is in this path

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  LatLng? _currentPosition;
  final String deviceID = "icE1FNvXIIOVSxwG9si03rYaXXE2"; // Your Device ID

  // --- State for Multiple Safe Zones ---
  Map<String, Map<String, dynamic>> _safeZones = {}; // Store multiple zones
  StreamSubscription? _locationSubscription; // Separate subscription for location
  StreamSubscription? _safeZoneSubscription;

  // --- State for Notifications ---
  bool _wasInsideAnySafeZone = false; // Track previous state for notifications
  final String botToken =
      "7873274853:AAH8fAGSWVGpySX2nBajyBLb5RuJ1ETtHrI"; // Your Bot Token
  final String chatId = "7848824397"; // Your Chat ID

  @override
  void initState() {
    super.initState();
    _listenToRealtimeLocation(); // Start listening to location
    _listenToSafeZones(); // Start listening to safe zones (plural)
    _checkAndRequestLocationPermission(); // Good practice to check permission
  }

  @override
  void dispose() {
    _locationSubscription?.cancel(); // Cancel location subscription
    _safeZoneSubscription?.cancel(); // Cancel safe zone subscription
    super.dispose();
  }

  // Check location permission (optional but recommended)
  Future<void> _checkAndRequestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Handle permissions denied
        print("Location permissions are denied.");
        // Optionally show a dialog to the user
      }
    }
  }


  // --- Fetch and Listen to Multiple Safe Zones ---
  void _listenToSafeZones() {
    _safeZoneSubscription =
        _database.child('safe_zones/$deviceID').onValue.listen((event) {
      Map<String, Map<String, dynamic>> tempSafeZones = {};
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map?;
        if (data != null) {
          data.forEach((key, value) {
            if (value is Map) {
              // Basic validation for required fields
              if (value.containsKey('latitude') && value.containsKey('longitude') && value.containsKey('radius')) {
                 try {
                   // Ensure values are numbers before converting
                   double lat = (value['latitude'] as num).toDouble();
                   double lon = (value['longitude'] as num).toDouble();
                   double rad = (value['radius'] as num).toDouble();
                   tempSafeZones[key] = Map<String, dynamic>.from(value); // Store if valid
                 } catch (e) {
                    print("Error parsing safe zone data for key $key: $e");
                 }
              } else {
                 print("Skipping incomplete safe zone data for key $key");
              }
            }
          });
        }
      }
      // Update state only if the data has changed
      if (mounted && _safeZones.toString() != tempSafeZones.toString()) {
        setState(() {
          _safeZones = tempSafeZones;
        });
         _checkIfInsideSafeZone(); // Re-check after zones update
      }
    }, onError: (error) {
        print("Error listening to safe zones: $error");
        if (mounted) {
          setState(() {
            _safeZones = {}; // Clear zones on error
          });
        }
    });
  }

  // --- Listen to Real-time Location ---
  void _listenToRealtimeLocation() {
    _locationSubscription =
        _database.child('locations/$deviceID').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        if (data.containsKey('latitude') && data.containsKey('longitude')) {
         try{
            double latitude = (data['latitude'] as num).toDouble();
            double longitude = (data['longitude'] as num).toDouble();
            LatLng newPosition = LatLng(latitude, longitude);

            if (_currentPosition == null || _currentPosition != newPosition) {
              if (mounted) { // Check if the widget is still mounted
                setState(() {
                  _currentPosition = newPosition;
                  // Optionally move map only if user isn't interacting?
                  // For now, always move:
                  _mapController.move(_currentPosition!, _mapController.zoom);
                });
                _checkIfInsideSafeZone(); // Check zone status on location update
              }
            }
          } catch (e) {
             print("Error parsing location data: $e");
          }
        }
      }
    }, onError: (error){
       print("Error listening to location: $error");
       // Handle location stream error if needed
    });
  }

  // --- Check if Inside Any Safe Zone and Notify ---
  void _checkIfInsideSafeZone() {
    if (_currentPosition == null || _safeZones.isEmpty) {
       // If we were inside, and now there are no zones or no location, we are outside
       if(_wasInsideAnySafeZone) {
          _sendTelegramMessage("ออกจากพื้นที่ปลอดภัยทั้งหมด ❌");
          if(mounted) {
             _wasInsideAnySafeZone = false; // Update state tracking
          }
       }
       return; // Cannot check without position or zones
    }


    bool isInsideAnyZone = false;
    String enteredZoneName = "ไม่ระบุชื่อ"; // Default name

    for (var entry in _safeZones.entries) {
      final zoneData = entry.value;
      // Data validation should happen in _listenToSafeZones, but double-check
      if (zoneData['latitude'] == null || zoneData['longitude'] == null || zoneData['radius'] == null) continue;

      try {
          LatLng safeZonePosition = LatLng(
            (zoneData['latitude'] as num).toDouble(),
            (zoneData['longitude'] as num).toDouble(),
          );
          double radius = (zoneData['radius'] as num).toDouble();

          double distance = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              safeZonePosition.latitude,
              safeZonePosition.longitude);

          if (distance <= radius) {
            isInsideAnyZone = true;
            enteredZoneName = zoneData['name'] ?? "ไม่ระบุชื่อ"; // Get the name
            break; // Found at least one zone the user is inside
          }
       } catch (e) {
          print("Error during distance calculation for zone ${entry.key}: $e");
          continue; // Skip this zone if data is bad
       }
    }

    // Check if state changed
    if (isInsideAnyZone && !_wasInsideAnySafeZone) {
      // Entered a safe zone
      _sendTelegramMessage("เข้าสู่พื้นที่ $enteredZoneName ✅");
      if (mounted) {
           _wasInsideAnySafeZone = true; // Update state tracking
      }
    } else if (!isInsideAnyZone && _wasInsideAnySafeZone) {
      // Exited all safe zones
      _sendTelegramMessage("ออกจากพื้นที่ปลอดภัยทั้งหมด ❌");
       if (mounted) {
           _wasInsideAnySafeZone = false; // Update state tracking
       }
    }
    // If state didn't change, do nothing
  }

  // --- Send Telegram Message Function ---
  Future<void> _sendTelegramMessage(String message) async {
    // Ensure token and chat ID are not empty
     if (botToken.isEmpty || chatId.isEmpty) {
       print("Error: Bot token or Chat ID is empty. Cannot send message.");
       return;
     }
    String url =
        "https://api.telegram.org/bot$botToken/sendMessage?chat_id=$chatId&text=${Uri.encodeComponent(message)}";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        print("Telegram message sent successfully: $message");
      } else {
        print(
            "Failed to send Telegram message. Status code: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      print("Error sending Telegram message: $e");
    }
  }

  // --- Navigation ---
  void _goToCurrentLocation() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _mapController.zoom);
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('ยังไม่มีข้อมูลตำแหน่งปัจจุบัน')),
       );
    }
  }

  void _goToSafeZonePage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SafeZonePage(
          // Use a valid default if currentPosition is null
          initialPosition: _currentPosition ??
              LatLng(16.4538, 103.5308), // Default near Kalasin
        ),
      ),
    ).then((_) {
      // Re-fetch safe zones when returning from SafeZonePage
      // Ensures map reflects any changes made there.
       print("Returned from SafeZonePage, re-listening to safe zones.");
      _listenToSafeZones();
    });
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('แผนที่'),
        actions: [
          IconButton(
            icon: Icon(Icons.security),
            onPressed: _goToSafeZonePage,
            tooltip: 'กำหนด/แก้ไขพื้นที่ปลอดภัย', // Updated tooltip
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _currentPosition ??
                  LatLng(16.4538, 103.5308), // Default near Kalasin
              minZoom: 5.0,
              maxZoom: 18.0,
              zoom: 15.0,
              // onTap: (tapPosition, latLng) { /* Add tap handler if needed */ },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
              ),

              // --- Draw Multiple Safe Zone Circles ---
              if (_safeZones.isNotEmpty)
                 ..._safeZones.entries.map((entry) {
                   final safeZoneData = entry.value;
                    // Validate data before trying to draw
                    if (safeZoneData['latitude'] == null || safeZoneData['longitude'] == null || safeZoneData['radius'] == null) {
                      return CircleLayer(circles: []); // Return empty layer for invalid data
                    }
                    try {
                       final safeZonePosition = LatLng(
                         (safeZoneData['latitude'] as num).toDouble(),
                         (safeZoneData['longitude'] as num).toDouble(),
                       );
                       final radius = (safeZoneData['radius'] as num).toDouble();

                       return CircleLayer(
                         circles: [
                           CircleMarker(
                             point: safeZonePosition,
                             color: Colors.blue.withOpacity(0.3),
                             borderColor: Colors.blue,
                             borderStrokeWidth: 2,
                             radius: radius,
                             useRadiusInMeter: true, // Use meters for radius
                           ),
                         ],
                       );
                    } catch (e) {
                       print("Error creating circle for zone ${entry.key}: $e");
                       return CircleLayer(circles: []); // Return empty layer on error
                    }
                 }).toList(), // End of map and convert to list

              // Current Location Marker Layer
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 50.0,
                      height: 50.0,
                      point: _currentPosition!,
                      builder: (ctx) => Tooltip( // Add tooltip to marker
                        message: 'ตำแหน่งปัจจุบัน',
                        child: Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40.0,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // Floating Action Button for centering on current location
          Positioned(
            bottom: 20.0,
            right: 20.0,
            child: FloatingActionButton(
              onPressed: _goToCurrentLocation,
              tooltip: 'ไปยังตำแหน่งปัจจุบัน', // Add tooltip
              child: Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}