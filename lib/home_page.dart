import 'dart:async';
import 'dart:convert'; // Needed for json encoding
import 'package:http/http.dart' as http; // Import http package for Telegram API calls
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:testcode/main.dart'; // Assuming LoginPage exists
import 'package:testcode/user_info_page.dart'; // Assuming UserInfoPage exists
import 'package:testcode/map_page.dart'; // Assuming MapPage exists
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
// Import timezone package if you haven't already (for time zone names in logs)
// import 'package:timezone/timezone.dart' as tz;
// import 'package:timezone/data/latest.dart' as tz;


// AnimatedIconContainer (จำเป็นต้องมี)
class AnimatedIconContainer extends StatefulWidget {
  final Widget child;
  const AnimatedIconContainer({Key? key, required this.child}) : super(key: key);
  @override
  _AnimatedIconContainerState createState() => _AnimatedIconContainerState();
}
class _AnimatedIconContainerState extends State<AnimatedIconContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween(begin: 0.0, end: 10.0).animate(_controller);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -_animation.value),
          child: widget.child,
        );
      },
    );
  }
}
// -------------------------------------------------

// --- HomePage State ---
class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- State for Activities, User Info, Local Notifications ---
  List<Map<String, dynamic>> activities = [];
  List<Map<String, dynamic>> completedActivities = [];
  Stream<List<Map<String, dynamic>>>? _activitiesStream;
  Stream<List<Map<String, dynamic>>>? _completedActivitiesStream;
  final TextEditingController _activityController = TextEditingController();
  DateTime? _selectedDateTime;
  List<Map<String, dynamic>> notifications = [];

  // --- State for Map, Location, and Safe Zones ---
  LatLng? currentLocation;
  final MapController _mapController = MapController();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  // Use late final and initialize in initState or get dynamically
  late final String deviceID;
  StreamSubscription? _locationSubscription;
  StreamSubscription? _safeZoneSubscription;
  Map<String, Map<String, dynamic>> _safeZones = {};
  final Color _defaultZoneColor = Colors.blue;
  Set<String> _currentlyInsideZoneIds = {};
  String _safeZoneStatusMessage = "กำลังตรวจสอบ...";

  // --- Telegram Integration Variables ---
  final String telegramBotToken = '7411078912:AAF5ZfSBpCmQ2ojAmjWsIoz05Hzvx-iTAzo'; // Replace with your Bot Token
  final String telegramChatId = '7892088611'; // Replace with your Chat ID

  // *** NEW: Map for storing activity reminder timers ***
  Map<String, Timer> _activityTimers = {};

  // --- Helper Function to get IconData from String ID ---
  IconData _getIconFromString(String? iconId) {
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
    };
    return availableIcons[iconId?.toLowerCase() ?? 'default'] ?? Icons.location_pin;
  }

  @override
  void initState() {
    super.initState();
    print("--- HomePage initState ---");
    // Initialize deviceID based on logged-in user
    User? currentUser = FirebaseAuth.instance.currentUser; // ตรวจสอบผู้ใช้งานที่ล็อกอินอยู่
    deviceID = FirebaseAuth.instance.currentUser?.uid ?? "default_device_id";
    print("--- HomePage initState: deviceID = $deviceID ---");

    // Initialize timezone data (if using timezone package for logs)
    // tz.initializeTimeZones();

    // Start loading and listening only if deviceID is valid
    if (deviceID != "default_device_id") {
      _loadActivitiesAndCompleted(); // This will now also schedule existing reminders after loading
      _listenToRealtimeLocation();
      _listenToSafeZones();
    } else {
      print("--- HomePage initState: No user logged in, skipping data loading/listening ---");
      // Optionally update UI to show a login prompt or relevant message
      if (mounted) {
        setState(() {
          _safeZoneStatusMessage = "กรุณาเข้าสู่ระบบ";
        });
      }
    }
  }



  @override
  void dispose() {
    print("--- HomePage dispose ---");
    // *** Cancel all active activity timers ***
    _activityTimers.forEach((key, timer) => timer.cancel());
    _activityTimers.clear(); // Clear the map
    _locationSubscription?.cancel();
    _safeZoneSubscription?.cancel();
    _activityController.dispose();
    _mapController.dispose(); // Dispose map controller
    super.dispose();
  }

  // --- Telegram Function ---
  Future<void> _sendTelegramMessage(String message) async {
    if (telegramBotToken.isEmpty || telegramChatId.isEmpty) {
      print("HomePage: Error: Bot token or Chat ID is empty.");
      return;
    }
    final String url = 'https://api.telegram.org/bot$telegramBotToken/sendMessage';
    print("HomePage: Attempting to send Telegram message: '$message'");
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(<String, String>{ 'chat_id': telegramChatId, 'text': message }),
      ).timeout(const Duration(seconds: 10)); // Added timeout
      if (response.statusCode == 200) {
        print('HomePage: Telegram message sent successfully.');
      } else {
        print('HomePage: !!! Failed to send Telegram message. Status code: ${response.statusCode}, body: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('HomePage: !!! Error sending Telegram message: $e');
      print('HomePage: !!! StackTrace: $stackTrace');
    }
  }

  // --- Firebase Listeners ---
  void _listenToRealtimeLocation() {
    if (deviceID == "default_device_id") {
      print("HomePage: Cannot listen to location, deviceID is default.");
      if (mounted) {
        setState(() { currentLocation = null; _safeZoneStatusMessage = "ไม่พบ ID ผู้ใช้"; });
      }
      return; // Don't listen if ID is not set
    }
    _locationSubscription?.cancel();
    print("HomePage: Listening to Realtime Location: locations/$deviceID");
    _locationSubscription = _database.child('locations/$deviceID').onValue.listen((event) {
      if (!mounted) { _locationSubscription?.cancel(); return; }
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        if (data.containsKey('latitude') && data.containsKey('longitude')) {
          try {
            // Ensure data types are correct before conversion
            double latitude = (data['latitude'] as num).toDouble();
            double longitude = (data['longitude'] as num).toDouble();

            // Validate coordinates
            if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
              throw FormatException("Invalid Lat/Lon values received: $latitude, $longitude");
            }
            LatLng newPosition = LatLng(latitude, longitude);

            // Check if location actually changed to avoid unnecessary updates
            if (currentLocation == null || currentLocation!.latitude != newPosition.latitude || currentLocation!.longitude != newPosition.longitude) {
              print("HomePage: Location changed: $newPosition");
              if(mounted) { // Ensure mounted before setState
                setState(() { currentLocation = newPosition; });
              }

              // Move map after frame build
              if(mounted){
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && currentLocation != null) { // Check currentLocation again inside callback
                    try {
                      _mapController.move(currentLocation!, _mapController.zoom);
                      print("HomePage: Map moved to new location post frame.");
                    } catch (e) {
                      print("HomePage: !!! Map move error post frame: $e");
                    }
                  }
                });
              }
              _checkZoneStatusAndNotify(); // Check zone status with new location
            }
          } catch (e, stackTrace) {
            print("HomePage: !!! Error parsing location data or invalid values: $e \n $stackTrace \n Data: $data");
            // Optionally set location to null or show error state
            // if(mounted) { setState(() { currentLocation = null; _safeZoneStatusMessage = "ข้อผิดพลาดข้อมูลตำแหน่ง"; });}
          }
        } else {
          print("HomePage: Location data received is missing lat/lon keys. Data: $data");
        }
      } else {
        // Location data from Firebase is null or not a map
        if (currentLocation != null) {
          print("HomePage: Location data from Firebase became null.");
          if(mounted) { setState(() => currentLocation = null); }
          _checkZoneStatusAndNotify(); // Re-check status when location is lost
        }
        // else { print("HomePage: Location data from Firebase is null (and was already null)."); }
      }
    }, onError: (error) {
      print("HomePage: !!! Error listening to location stream: $error");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ข้อผิดพลาดในการรับตำแหน่ง: $error')));
        setState(() { currentLocation = null; _safeZoneStatusMessage = "ข้อผิดพลาดในการรับตำแหน่ง"; });
      }
    });
  }

  void _listenToSafeZones() {
    if (deviceID == "default_device_id") {
      print("HomePage: Cannot listen to safe zones, deviceID is default.");
      if (mounted) {
        setState(() { _safeZones = {}; _currentlyInsideZoneIds.clear(); _safeZoneStatusMessage = "ไม่พบ ID ผู้ใช้"; });
      }
      return;
    }
    _safeZoneSubscription?.cancel();
    print("HomePage: Listening to Safe Zones: safe_zones/$deviceID");
    _safeZoneSubscription = _database.child('safe_zones/$deviceID').onValue.listen((event) {
      if (!mounted) return;
      Map<String, Map<String, dynamic>> tempSafeZones = {};
      if (event.snapshot.exists) {
        final data = event.snapshot.value;
        if (data is Map) {
          data.forEach((key, value) {
            if (key is String && value is Map) {
              if (value.containsKey('latitude') && value.containsKey('longitude') && value.containsKey('radius')) {
                try {
                  double latitude = (value['latitude'] as num).toDouble();
                  double longitude = (value['longitude'] as num).toDouble();
                  double radius = (value['radius'] as num).toDouble();

                  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 || radius <= 0) {
                    throw FormatException("Invalid coordinate or radius values for key $key");
                  }
                  int? colorValue = value['color'] is int ? value['color'] as int : null;
                  String? iconId = value['iconId'] as String?;
                  String zoneName = value['name']?.toString() ?? key;

                  tempSafeZones[key] = {
                    'name': zoneName,
                    'latitude': latitude,
                    'longitude': longitude,
                    'radius': radius,
                    'colorValue': colorValue ?? _defaultZoneColor.value,
                    'iconId': iconId ?? 'default',
                    ...(value..removeWhere((k, v) => ['name', 'latitude', 'longitude', 'radius', 'colorValue', 'iconId'].contains(k)))
                  };

                } catch (e) {
                  print("HomePage: Error parsing safe zone data for key $key: $e \n Value: $value");
                }
              } else {
                print("HomePage: Skipping incomplete safe zone data for key $key: Missing lat/lon/radius. Value: $value");
              }
            } else {
              print("HomePage: Skipping invalid entry in safe zones: Key=$key, Value=$value");
            }
          });
        } else {
          print("HomePage: Safe zones data is not a Map. Data: $data");
        }
      } else {
        print("HomePage: No safe zones found for $deviceID");
      }

      if (mounted && _safeZones.toString() != tempSafeZones.toString()) {
        print("HomePage: Safe zones updated. Found ${tempSafeZones.length} zones.");
        setState(() {
          _safeZones = tempSafeZones;
          if (_safeZones.isEmpty) {
            _currentlyInsideZoneIds.clear();
            _safeZoneStatusMessage = "ยังไม่ได้กำหนดพื้นที่";
          }
          _currentlyInsideZoneIds.removeWhere((id) => !_safeZones.containsKey(id));
        });
        _checkZoneStatusAndNotify(); // Re-check status with updated zones
      }
    }, onError: (error) {
      print("HomePage: Error listening to safe zones stream: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ข้อผิดพลาดในการโหลดพื้นที่: $error')));
        setState(() {
          _safeZones = {};
          _currentlyInsideZoneIds.clear();
          _safeZoneStatusMessage = "ข้อผิดพลาดในการโหลดพื้นที่";
        });
      }
    });
  }

  // --- Automatic Zone Status Check & Notification ---
  void _checkZoneStatusAndNotify() {
    if (!mounted) return;
    final previousInsideZoneIds = Set<String>.from(_currentlyInsideZoneIds);
    final newInsideZoneIds = <String>{};
    String currentStatusMessage;

    if (currentLocation == null) {
      currentStatusMessage = "กำลังรอตำแหน่ง...";
    } else if (_safeZones.isEmpty) {
      currentStatusMessage = "ยังไม่ได้กำหนดพื้นที่";
    } else {
      bool isInsideAny = false;
      List<String> insideZoneNames = [];
      _safeZones.forEach((zoneId, zoneData) {
        double? latitude = zoneData['latitude'] as double?;
        double? longitude = zoneData['longitude'] as double?;
        double? radius = zoneData['radius'] as double?;
        String zoneName = zoneData['name'] ?? zoneId;

        if (latitude == null || longitude == null || radius == null || radius <= 0) {
          // print("HomePage: Skipping zone $zoneId during check due to invalid data..."); // Reduce log verbosity
          return;
        }
        try {
          double distance = Geolocator.distanceBetween(
              currentLocation!.latitude, currentLocation!.longitude,
              latitude, longitude
          );
          if (distance <= radius) {
            newInsideZoneIds.add(zoneId);
            insideZoneNames.add(zoneName);
            isInsideAny = true;
          }
        } catch (e) {
          print("HomePage: Error calculating distance or processing zone $zoneId during check: $e");
        }
      });

      if (isInsideAny) {
        currentStatusMessage = insideZoneNames.length == 1
            ? "อยู่ในพื้นที่ ${insideZoneNames.first} ✅"
            : "อยู่ในพื้นที่: ${insideZoneNames.join(', ')} ✅";
      } else {
        currentStatusMessage = "อยู่นอกพื้นที่ปลอดภัยทั้งหมด ❌";
      }
    }

    // --- Send Notifications for Status Changes ---
    final enteredZones = newInsideZoneIds.difference(previousInsideZoneIds);
    enteredZones.forEach((zoneId) {
      String zoneName = _safeZones[zoneId]?['name'] ?? zoneId;
      print("HomePage: Status change: Entered zone '$zoneName' ($zoneId). Sending notification.");
      _sendTelegramMessage("เข้าสู่พื้นที่ $zoneName ✅");
      _addNotification("เข้าสู่พื้นที่: $zoneName");
    });

    final exitedZones = previousInsideZoneIds.difference(newInsideZoneIds);
    exitedZones.forEach((zoneId) {
      String zoneName = _safeZones[zoneId]?['name'] ?? zoneId;
      print("HomePage: Status change: Exited zone '$zoneName' ($zoneId). Sending notification.");
      _sendTelegramMessage("ออกจากพื้นที่ $zoneName ❌");
      _addNotification("ออกจากพื้นที่: $zoneName");
    });

    // --- Update UI State if Changed ---
    if (_safeZoneStatusMessage != currentStatusMessage || _currentlyInsideZoneIds.toString() != newInsideZoneIds.toString()) {
      if(mounted) { // Check mounted before setState
        setState(() {
          _safeZoneStatusMessage = currentStatusMessage;
          _currentlyInsideZoneIds = Set<String>.from(newInsideZoneIds);
        });
      }
    }
  }



  // --- Local Notification List Management ---
  void _addNotification(String message) {
    if(!mounted) return;
    DateTime now = DateTime.now();
    // Ensure locale is set for DateFormat if needed, otherwise uses default
    String formattedTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    print("HomePage: Adding local notification: '$message'");
    setState(() {
      notifications.insert(0, {'message': message, 'time': formattedTime});
      if (notifications.length > 20) { // Limit list size
        notifications.removeLast();
      }
    });
  }

  // --- Data Loading for Activities/Completed (Firestore) ---
  Future<void> _loadActivitiesAndCompleted() async {
    // Use the initialized deviceID (user's UID)
    if (deviceID == "default_device_id") {
      print("User is not logged in (deviceID is default), cannot load activities.");
      if(mounted) { setState(() { activities = []; completedActivities = []; }); }
      return;
    }
    print("--- HomePage: Loading Activities/Completed for user: $deviceID ---");
    try {
      print("HomePage: Querying 'activities' collection group for uid: $deviceID...");
      var activitySnapshot = await FirebaseFirestore.instance
          .collectionGroup('activities')
          .where('uid', isEqualTo: deviceID)
          .orderBy('time') // Ensure index exists: activities(collection group) -> uid ASC, time ASC
          .get()
          .timeout(const Duration(seconds: 15));
      print("HomePage: Loaded ${activitySnapshot.docs.length} pending activities.");

      print("HomePage: Querying 'completed_activities' collection for uid: $deviceID...");
      var completedActivitySnapshot = await FirebaseFirestore.instance
          .collection('completed_activities')
          .where('uid', isEqualTo: deviceID)
          .orderBy('completionTime', descending: true)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 15));
      print("HomePage: Loaded ${completedActivitySnapshot.docs.length} completed activities.");

      List<Map<String, dynamic>> newActivities = activitySnapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      List<Map<String, dynamic>> newCompletedActivities = completedActivitySnapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        print("HomePage: Cancelling ${_activityTimers.length} existing timers before update.");
        _activityTimers.forEach((key, timer) => timer.cancel());
        _activityTimers.clear();

        setState(() {
          activities = newActivities;
          completedActivities = newCompletedActivities;
          print("HomePage: State updated with Activity/Completed data.");
        });
        // Schedule reminders AFTER state is updated
        _scheduleExistingActivityReminders();
      } else {
        print("HomePage: Widget not mounted after loading activities.");
      }
    } catch (e, stackTrace) {
      print("HomePage: !!! Error loading Activities/Completed data: $e");
      if (e is FirebaseException && e.code == 'failed-precondition') {
        print("HomePage: !!! Firestore Index Required !!!");
        print("    Collection Group: 'activities'");
        print("    Fields: uid (ASC), time (ASC)");
        print("    Please create this index in the Firebase Console (Firestore > Indexes).");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: Duration(seconds: 15), // Show longer
              content: Text('Firestore ต้องการ Index (Collection Group) สำหรับ activities: uid (ASC), time (ASC). โปรดสร้างใน Firebase Console.')));
        }
      } else {
        print("HomePage: !!! StackTrace: $stackTrace");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดร้ายแรงในการโหลดข้อมูลกิจกรรม: $e')));
        }
      }
      if (mounted) {
        setState(() { activities = []; completedActivities = []; }); // Reset lists on error
      }
    }
    print("--- HomePage: Finished loading Activities/Completed data ---");
  }

  // --- Logout ---
  void _logout() async {
    print("HomePage: Logging out...");
    try {
      await FirebaseAuth.instance.signOut();
      print("HomePage: Sign out successful.");
      if (mounted) {
        _activityTimers.forEach((key, timer) => timer.cancel());
        _activityTimers.clear();
        _locationSubscription?.cancel();
        _safeZoneSubscription?.cancel();
        setState(() {
          activities = [];
          completedActivities = [];
          notifications = [];
          currentLocation = null;
          _safeZones = {};
          _currentlyInsideZoneIds = {};
          _safeZoneStatusMessage = "กรุณาเข้าสู่ระบบ";
          // Reset deviceID? No, initState will handle it on next build if needed.
        });
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => LoginPage()),
                (Route<dynamic> route) => false
        );
      }
    } catch (e, stackTrace) {
      print("HomePage: !!! Error logging out: $e \n $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการออกจากระบบ: $e')));
      }
    }
  }

  // --- Activity Management Actions ---

  void _scheduleActivityReminder(String activityId, String activityName, DateTime activityTime) {
    _cancelActivityReminder(activityId); // Cancel existing timer first

    DateTime now = DateTime.now();
    DateTime localActivityTime = activityTime.toLocal();
    DateTime reminderTime = localActivityTime.subtract(Duration(minutes: 15));

    bool activityIsInFuture = localActivityTime.isAfter(now);
    bool reminderIsInFuture = reminderTime.isAfter(now);

    print("---------- Scheduling Check ----------");
    print("Activity: '$activityName' (ID: $activityId)");
    print("  Now           : $now (${now.timeZoneName})");
    print("  Activity Time : $localActivityTime (${localActivityTime.timeZoneName})");
    print("  Reminder Time : $reminderTime (${reminderTime.timeZoneName})");
    print("  Activity > Now? : $activityIsInFuture");
    print("  Reminder > Now? : $reminderIsInFuture");

    if (activityIsInFuture) {
      Duration durationUntilFire;
      String logMessage;

      if (reminderIsInFuture) {
        // Case 1: Reminder time is still in the future (more than 15 mins away)
        durationUntilFire = reminderTime.difference(now);
        logMessage = "  ✅ SCHEDULING reminder in ${durationUntilFire.inMinutes} min (${durationUntilFire.inSeconds} sec)";
      } else {
        // Case 2: Reminder time has passed, but activity is still in the future (less than 15 mins away)
        // In this case, we want to notify immediately or very soon (e.g., in 10 seconds)
        // Or, you could set the reminder for the activity time itself, or a minute before
        durationUntilFire = localActivityTime.difference(now);
        if (durationUntilFire.isNegative) { // Should not happen if activityIsInFuture is true, but as a safeguard
          print("  ❌ NOT SCHEDULING: Activity time ($localActivityTime) is actually in the past despite initial check.");
          return;
        }
        // Schedule to fire soon (e.g., 5 seconds from now), or at the actual activity time
        // I'd suggest firing immediately for activities within the 15-min window
        // For immediate notification, durationUntilFire should be very small, e.g., 0 seconds.
        durationUntilFire = Duration(seconds: 5); // Fire in 5 seconds to catch it
        logMessage = "  ✅ SCHEDULING IMMEDIATE/NEAR reminder for activity (less than 15 mins away). Fires in ${durationUntilFire.inSeconds} sec";
      }

      print(logMessage);

      _activityTimers[activityId] = Timer(durationUntilFire, () {
        print("  ⏰ TIMER FIRED for '$activityName' (ID: $activityId) at ${DateTime.now()}");
        if (!mounted) {
          print("    ❌ Timer Fired: Widget not mounted.");
          _activityTimers.remove(activityId);
          return;
        }
        bool activityExists = activities.any((act) => act['id'] == activityId);
        print("    Timer Fired: Activity exists in list? $activityExists");
        if (activityExists) {
          print("    ✅ Sending reminder Telegram message.");
          _sendTelegramMessage("⏰ ใกล้ถึงเวลากิจกรรม: $activityName (${DateFormat('HH:mm').format(localActivityTime)})");
          _addNotification("ใกล้ถึงเวลากิจกรรม: $activityName");
        } else {
          print("    ❌ Reminder not sent, activity no longer exists in the list.");
        }
        _activityTimers.remove(activityId);
      });
    } else {
      // Activity time itself is in the past
      print("  ❌ NOT SCHEDULING: Activity time ($localActivityTime) already passed.");
    }
    print("------------------------------------");
  }


  // *** NEW Function: Cancel reminder for a specific activity ***
  void _cancelActivityReminder(String? activityId) {
    if (activityId == null) {
      // print("HomePage: Attempted to cancel reminder with null activity ID."); // Reduce verbosity
      return;
    }
    if (_activityTimers.containsKey(activityId)) {
      print("HomePage: Cancelling reminder for activity ID: $activityId");
      _activityTimers[activityId]?.cancel();
      _activityTimers.remove(activityId);
    }
  }

  // *** NEW Function: Schedule reminders for existing activities on app start/reload ***
  void _scheduleExistingActivityReminders() {
    print("HomePage: Scheduling reminders for ${activities.length} existing activities...");
    int scheduledCount = 0;
    activities.forEach((activity) {
      // Safely parse time and get ID/Name
      DateTime? activityTime = DateTime.tryParse(activity['time'] ?? ''); // Parse ISO string
      String? activityId = activity['id'] as String?;
      String? activityName = activity['name'] as String?;

      if (activityTime != null && activityId != null && activityName != null) {
        // Let _scheduleActivityReminder handle the logic of whether to actually schedule
        _scheduleActivityReminder(activityId, activityName, activityTime);
        // Check if the timer was actually added (meaning conditions were met)
        if (_activityTimers.containsKey(activityId)) {
          scheduledCount++;
        }
      } else {
        print("HomePage: Skipping existing activity scheduling due to missing data: ID=$activityId, Name=$activityName, TimeStr=${activity['time']}");
      }
    });
    print("HomePage: Finished scheduling existing reminders. $scheduledCount active timers expected.");
  }


  Future<void> _addActivity() async {
    // Use the initialized deviceID (user's UID)
    if (deviceID == "default_device_id") {
      print("Add activity: User not logged in (deviceID default).");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนเพิ่มกิจกรรม')));
      return;
    }
    if (_activityController.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('กรุณาใส่ชื่อกิจกรรม')));
      return;
    }
    if (_selectedDateTime == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('กรุณาเลือกวันและเวลา')));
      return;
    }
    // Re-validate time just before adding
    if (_selectedDateTime!.isBefore(DateTime.now().subtract(Duration(seconds:10)))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ไม่สามารถเพิ่มกิจกรรมในอดีตได้')));
      setState(() { _selectedDateTime = null; }); // Clear invalid selection
      return;
    }

    String formattedDateTime = _selectedDateTime!.toIso8601String(); // Store as ISO 8601 string (includes offset or Z)
    final newActivityData = {
      'name': _activityController.text.trim(),
      'time': formattedDateTime,
      'uid': deviceID // Include user's UID
    };
    // Keep local copies for UI update and scheduling
    String tempActivityName = _activityController.text.trim();
    DateTime tempSelectedDT = _selectedDateTime!;

    // Optimistically clear input fields in UI
    if (mounted) {
      setState(() {
        _activityController.clear();
        _selectedDateTime = null;
      });
    }

    try {
      print("HomePage: Adding activity '$tempActivityName' at $tempSelectedDT (ISO: $formattedDateTime) to Firestore for user $deviceID...");
      // Add to Firestore: users/{uid}/activities/{docId}
      DocumentReference docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(deviceID)
          .collection('activities')
          .add(newActivityData)
          .timeout(const Duration(seconds: 10));
      print("HomePage: Activity added with Firestore ID: ${docRef.id}");

      if (mounted) {
        final newActivityEntry = { // Create map for local state
          'id': docRef.id, // Use the actual ID from Firestore
          'name': tempActivityName,
          'time': formattedDateTime, // Store the ISO string
          'uid': deviceID
        };
        setState(() {
          activities.add(newActivityEntry);
          activities.sort((a, b) { // Keep sorted
            DateTime? tA = DateTime.tryParse(a['time'] ?? '');
            DateTime? tB = DateTime.tryParse(b['time'] ?? '');
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1; if (tB == null) return -1;
            return tA.compareTo(tB);
          });
          print("HomePage: Activity added to local UI state.");
        });

        // Schedule reminder AFTER successful add and state update
        print("HomePage: Scheduling reminder for new activity...");
        _scheduleActivityReminder(docRef.id, tempActivityName, tempSelectedDT); // Use DateTime object for scheduling

      } else {
        print("HomePage: Widget not mounted after adding activity to Firestore.");
      }
    } catch (e, stackTrace) {
      print("HomePage: !!! Error adding activity: $e \n $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการเพิ่มกิจกรรม: $e')));
        // Consider restoring input fields if add failed
        // setState(() { _activityController.text = tempActivityName; _selectedDateTime = tempSelectedDT; });
      }
    }
  }

  Future<void> _completeActivity(int index) async {
    // Use the initialized deviceID (user's UID)
    if (!mounted || deviceID == "default_device_id" || index < 0 || index >= activities.length) {
      print("HomePage: Complete activity precondition failed: mounted=$mounted, deviceID=$deviceID, index=$index, listSize=${activities.length}");
      return;
    }

    var activity = Map<String, dynamic>.from(activities[index]); // Get copy
    String? activityId = activity['id'] as String?;
    String? activityName = activity['name'] as String?;
    String? originalTime = activity['time'] as String?; // ISO String

    if (activityId == null || activityName == null || originalTime == null) {
      print("HomePage: !!! Error: Attempting to complete activity with missing ID/Name/Time. Index: $index, Data: $activity");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ข้อผิดพลาด: ข้อมูลกิจกรรมไม่สมบูรณ์')));
      }
      return;
    }

    String completionTime = DateTime.now().toIso8601String(); // Record completion time as ISO string

    // Cancel any pending reminder FIRST
    _cancelActivityReminder(activityId);

    try {
      print("HomePage: Completing activity '$activityName' (ID: $activityId) for user $deviceID...");

      // 1. Add to 'completed_activities' top-level collection
      await FirebaseFirestore.instance
          .collection('completed_activities')
          .add({
        'name': activityName,
        'time': originalTime,       // Original scheduled time (ISO string)
        'completionTime': completionTime, // Actual completion time (ISO string)
        'uid': deviceID              // User who completed it
      }).timeout(const Duration(seconds: 10));
      print("HomePage: Added to completed_activities.");

      // 2. Delete from the user's 'activities' subcollection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(deviceID)
          .collection('activities')
          .doc(activityId)
          .delete()
          .timeout(const Duration(seconds: 10));
      print("HomePage: Deleted activity $activityId from users/$deviceID/activities.");

      // 3. Update UI State *AFTER* successful DB operations
      if (mounted) {
        setState(() {
          // Add to local completed list for UI
          completedActivities.insert(0, {
            'id': activityId, 'name': activityName,
            'time': originalTime, 'completionTime': completionTime
          });
          // Remove from local pending list
          activities.removeWhere((item) => item['id'] == activityId);
          print("HomePage: Activity completion updated in UI state.");
        });

        // Send Telegram notification AFTER UI update
        print("HomePage: Sending Telegram notification for completed activity...");
        await _sendTelegramMessage('✅ ทำกิจกรรมเสร็จสิ้น: $activityName');
      } else {
        print("HomePage: Widget not mounted after completing activity DB operations.");
      }

    } catch (e, stackTrace) {
      print("HomePage: !!! Error completing activity $activityId: $e \n $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('เกิดข้อผิดพลาดในการทำกิจกรรมให้เสร็จสิ้น: $e')));
      }
      // If completion failed, try to reschedule reminder if appropriate
      DateTime? originalActivityTime = DateTime.tryParse(originalTime); // Try parse ISO string
      if (originalActivityTime != null) {
        DateTime localOriginalTime = originalActivityTime.toLocal();
        if (localOriginalTime.isAfter(DateTime.now())) { // Check if time is still in future
          print("HomePage: Rescheduling reminder for $activityName (ID: $activityId) due to completion error.");
          _scheduleActivityReminder(activityId, activityName, localOriginalTime); // Use local DateTime
        } else {
          // print("HomePage: Not rescheduling reminder for $activityName after error, original time is past."); // Reduce verbosity
        }
      }
    }
  }


  // --- DateTime Picker ---
  void _selectDateTime(BuildContext context) async {
    print("Opening DateTime picker...");
    final DateTime now = DateTime.now();
    // Allow picking dates from today onwards
    final DateTime firstAllowedDate = DateTime(now.year, now.month, now.day);
    final DateTime initialPickerDate = _selectedDateTime ?? now;
    // Ensure initial date for DatePicker is not before the first allowed date
    final DateTime validInitialDate = initialPickerDate.isBefore(firstAllowedDate) ? firstAllowedDate : initialPickerDate;

    final DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: validInitialDate,
        firstDate: firstAllowedDate, // Start from today
        lastDate: DateTime(2101) // Far future date
    );
    print("Date picked: $pickedDate");

    if (pickedDate != null && mounted) { // Check mounted again after await
      // Determine initial time for TimePicker
      // Use current time if selected before or if it's for today and time is past
      TimeOfDay initialTime = TimeOfDay.fromDateTime(validInitialDate);
      bool isToday = pickedDate.year == now.year && pickedDate.month == now.month && pickedDate.day == now.day;

      if (isToday) {
        TimeOfDay nowTime = TimeOfDay.now();
        // If the initially suggested time is earlier than the current time
        if (initialTime.hour < nowTime.hour || (initialTime.hour == nowTime.hour && initialTime.minute < nowTime.minute)) {
          initialTime = nowTime; // Default to current time
          print("Adjusting initial time for today to current time: $initialTime");
        }
      }

      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: initialTime,
      );
      print("Time picked: $pickedTime");

      if (pickedTime != null && mounted) { // Check mounted again
        final selectedDT = DateTime(
            pickedDate.year, pickedDate.month, pickedDate.day,
            pickedTime.hour, pickedTime.minute
        );
        print("Selected DateTime: $selectedDT");

        // Validate: Must not be in the past (allow maybe 10 sec buffer)
        if (selectedDT.isBefore(DateTime.now().subtract(Duration(seconds: 10)))) {
          print("Selected DateTime is in the past.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ไม่สามารถเลือกเวลาในอดีตได้')));
          }
          return; // Don't update state
        }

        if (mounted) {
          setState(() {
            _selectedDateTime = selectedDT; // Update state with valid selection
          });
          print("DateTime state updated.");
        }
      }
    } else {
      print("Date picker cancelled or widget disposed.");
    }
  }

  // --- Build Method --- //
  @override
  Widget build(BuildContext context) {
    LatLng initialMapCenter = currentLocation ?? LatLng(13.7563, 100.5018); // Default Bangkok
    Color statusIndicatorColor;
    // Determine status color based on state
    if (deviceID == "default_device_id") { statusIndicatorColor = Colors.orange.shade700; } // Not logged in
    else if (currentLocation == null && _safeZoneStatusMessage.contains("ข้อผิดพลาด")) { statusIndicatorColor = Colors.orange.shade700;} // Location error
    else if (currentLocation == null) { statusIndicatorColor = Colors.blueGrey.shade700;} // Waiting for location
    else if (_safeZones.isEmpty && _safeZoneStatusMessage.contains("ข้อผิดพลาด")) { statusIndicatorColor = Colors.orange.shade700;} // Zone error
    else if (_safeZones.isEmpty) { statusIndicatorColor = Colors.grey.shade700;} // No zones defined
    else if (_currentlyInsideZoneIds.isNotEmpty) { statusIndicatorColor = Colors.green.shade700;} // Inside zone(s)
    else { statusIndicatorColor = Colors.red.shade700;} // Outside all zones

    return Scaffold(
      appBar: AppBar(
        title: Text('ระบบดูแลผู้ป่วยอัลไซเมอร์'),
        actions: [
          IconButton( tooltip: 'ออกจากระบบ', icon: Icon(Icons.exit_to_app), onPressed: _logout ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // --- Row 1: Activities and User Info ---
              Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Activities Card
                Expanded( flex: 2, child: Container(
                    margin: const EdgeInsets.only(right: 8.0, bottom: 16.0),
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration( color: Colors.deepOrange[400], borderRadius: BorderRadius.circular(12), boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: Offset(0, 2)) ]),
                    height: 300,
                    child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding( padding: const EdgeInsets.only(top: 8.0, bottom: 4.0), child: Text('กิจกรรมที่ต้องทำ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                      Divider(color: Colors.white54),
                      Expanded( child: activities.isEmpty
                          ? Center(child: Text("ไม่มีกิจกรรม", style: TextStyle(color: Colors.white70)))
                          : ListView.builder( itemCount: activities.length, itemBuilder: (context, index) {
                        final activityItem = activities[index];
                        DateTime? activityTime = DateTime.tryParse(activityItem['time'] ?? ''); // Parse ISO string
                        String timeString = 'Invalid Time';
                        if (activityTime != null) {
                          try { timeString = DateFormat('HH:mm dd/MM').format(activityTime.toLocal()); } // Display in local time
                          catch(e){ print("Error formatting list time: $e"); }
                        }
                        return ListTile( dense: true,
                            title: Text( '${activityItem['name'] ?? 'N/A'}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                            subtitle: Text( timeString, style: TextStyle(color: Colors.white70, fontSize: 12)),
                            trailing: IconButton( tooltip: 'ทำกิจกรรมนี้เสร็จสิ้น', icon: Icon(Icons.check_circle_outline, color: Colors.white), onPressed: () => _completeActivity(index), padding: EdgeInsets.zero, constraints: BoxConstraints())
                        );
                      }),
                      ),
                      Divider(color: Colors.white54),
                      Padding( padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), child: Row(children: [
                        Expanded(child: TextField( controller: _activityController, style: TextStyle(color: Colors.white), decoration: InputDecoration( hintText: 'เพิ่มกิจกรรม...', hintStyle: TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white.withOpacity(0.1), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true), onSubmitted: (_) => _addActivity())),
                        IconButton(tooltip: 'เลือกวันและเวลา', icon: Icon(Icons.calendar_today, color: Colors.white), onPressed: () => _selectDateTime(context)),
                        IconButton(tooltip: 'เพิ่มกิจกรรม', icon: Icon(Icons.add_circle, color: Colors.white, size: 28), onPressed: _addActivity),
                      ])),
                      if (_selectedDateTime != null) Padding( padding: const EdgeInsets.only(bottom: 4.0), child: Text( 'เวลาที่เลือก: ${DateFormat('HH:mm dd/MM/yyyy').format(_selectedDateTime!)}', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12))),
                    ]))
                ),
                // User Info Card
                Expanded( flex: 1, child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('user_info').doc(deviceID).snapshots(), // Use deviceID
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) { return Container(margin: const EdgeInsets.only(left: 8.0, bottom: 16.0), decoration: BoxDecoration(color: Colors.grey[350], borderRadius: BorderRadius.circular(12)), height: 300, child: Center(child: CircularProgressIndicator(color: Colors.white))); }
                      if (snapshot.hasError) { print("Error loading user info stream: ${snapshot.error}"); return Container(margin: const EdgeInsets.only(left: 8.0, bottom: 16.0), padding: const EdgeInsets.all(12.0), decoration: BoxDecoration(color: Colors.red.shade300, borderRadius: BorderRadius.circular(12)), height: 300, child: Center(child: Text('เกิดข้อผิดพลาด\nโหลดข้อมูลผู้ป่วย', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)))); }
                      Map<String, dynamic>? userData = snapshot.data?.data() as Map<String, dynamic>?;
                      bool hasData = userData != null && (userData['username'] as String? ?? '').isNotEmpty;
                      return _buildUserInfoContainer( context: context, hasData: hasData, userData: userData );
                    })
                ),
              ]),
              // --- Row 2: Map and Completed Activities ---
              Row( crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Map View
                Expanded( flex: 2, child: Container(
                    margin: const EdgeInsets.only(right: 8.0, bottom: 16.0), height: 300, decoration: BoxDecoration( borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueGrey.shade100), boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: Offset(0, 2)) ]),
                    child: ClipRRect( borderRadius: BorderRadius.circular(12.0), child: Stack( children: [
                      FlutterMap( mapController: _mapController, options: MapOptions( center: initialMapCenter, zoom: 15.0, maxZoom: 18.0, minZoom: 5.0, interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate, ), children: [
                        TileLayer( urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", subdomains: ['a', 'b', 'c'], userAgentPackageName: 'com.example.testcode',), // TODO: Change package name
                        // Safe Zone Circles
                        if (_safeZones.isNotEmpty) CircleLayer( circles: _safeZones.entries.map((entry) {
                          final data = entry.value; double? lat = data['latitude'] as double?; double? lon = data['longitude'] as double?; double? rad = data['radius'] as double?; if(lat==null||lon==null||rad==null||rad<=0) return null;
                          final inside = _currentlyInsideZoneIds.contains(entry.key); final color = Color(data['colorValue'] ?? _defaultZoneColor.value);
                          try { return CircleMarker( point: LatLng(lat, lon), radius: rad, useRadiusInMeter: true, color: color.withOpacity(inside ? 0.4 : 0.15), borderColor: color.withOpacity(inside ? 0.9 : 0.5), borderStrokeWidth: inside ? 2.5 : 1.0 ); } catch (e) { return null;}
                        }).whereType<CircleMarker>().toList(),
                        ),
                        // Safe Zone Markers
                        if (_safeZones.isNotEmpty) MarkerLayer( markers: _safeZones.entries.map((entry) {
                          final data = entry.value; double? lat = data['latitude'] as double?; double? lon = data['longitude'] as double?; if(lat == null || lon == null) return null;
                          final iconData = _getIconFromString(data['iconId'] as String?); final name = data['name'] as String? ?? entry.key;
                          try { return Marker( point: LatLng(lat, lon), width: 120, height: 55, anchorPos: AnchorPos.align(AnchorAlign.bottom), builder: (ctx) => Column( mainAxisSize: MainAxisSize.min, children: [ Container( padding: EdgeInsets.all(4), decoration: BoxDecoration( color: Colors.white.withOpacity(0.85), shape: BoxShape.circle, boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: Offset(0, 1), ) ] ), child: Icon(iconData, size: 22, color: Colors.blueGrey.shade800)), SizedBox(height: 2), Container( padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration( color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(3), ), child: Text( name, style: TextStyle( fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold,), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 1, )) ] ) ); } catch (e) { return null;}
                        }).whereType<Marker>().toList(),
                        ),
                        // Current Location Marker
                        if (currentLocation != null) MarkerLayer( markers: [ Marker( point: currentLocation!, width: 80, height: 80, builder: (context) => AnimatedIconContainer( child: Icon( Icons.location_pin, color: statusIndicatorColor, size: 40, shadows: [ Shadow(color: Colors.black54, blurRadius: 5.0, offset: Offset(0,2)), ],), ), anchorPos: AnchorPos.align(AnchorAlign.top), ), ], ),
                      ]),
                      // Status Indicator Overlay
                      Positioned( top: 10, left: 10, child: Container( padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration( color: statusIndicatorColor.withOpacity(0.85), borderRadius: BorderRadius.circular(10), boxShadow: [ BoxShadow(color: Colors.black38, blurRadius: 3) ] ), child: Text( _safeZoneStatusMessage, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13) ), ), ),
                      // Fullscreen Button Overlay
                      Positioned( bottom: 10, right: 10, child: FloatingActionButton.extended( heroTag: 'mapPageBtn_home', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => MapPage())), icon: Icon(Icons.open_in_full), label: Text('ดูเต็มจอ'), backgroundColor: Colors.blueAccent, elevation: 4 ), ),
                    ]))
                )),
                // Completed Activities Card
                Expanded( flex: 1, child: Container(
                  margin: const EdgeInsets.only(left: 8.0, bottom: 16.0), height: 300, padding: const EdgeInsets.all(8.0), decoration: BoxDecoration( color: Colors.green[400], borderRadius: BorderRadius.circular(12), boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: Offset(0, 2)) ]),
                  child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Text( 'ทำเสร็จแล้ว', textAlign: TextAlign.center, style: TextStyle( color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, ), ), ),
                    Divider(color: Colors.white54, height: 1),
                    Expanded( child: completedActivities.isEmpty
                        ? Center(child: Text("ยังไม่มี", style: TextStyle(color: Colors.white70)))
                        : ListView.builder( itemCount: completedActivities.length, itemBuilder: (context, index) {
                      final item = completedActivities[index]; DateTime? completionTime = DateTime.tryParse(item['completionTime'] ?? ''); String timeStr = ''; if(completionTime!=null){ try{ timeStr = DateFormat('HH:mm dd/MM').format(completionTime.toLocal()); } catch(e){} }
                      return ListTile( dense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8), title: Text('${item['name'] ?? 'N/A'}', style: TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis), subtitle: Text(timeStr, style: TextStyle(color: Colors.white70, fontSize: 11)), leading: Icon(Icons.check_circle, color: Colors.white, size: 18));
                    }),
                    ),
                  ]),
                )),
              ]),
              // Notifications Card
              Container( height: 160, margin: const EdgeInsets.only(bottom: 16.0), padding: const EdgeInsets.all(8.0), decoration: BoxDecoration( color: Colors.cyan[600], borderRadius: BorderRadius.circular(12), boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: Offset(0, 2)) ]),
                child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Text( 'การแจ้งเตือนล่าสุด', textAlign: TextAlign.center, style: TextStyle( color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, ), ), ),
                  Divider(color: Colors.white54, height: 1),
                  Expanded( child: notifications.isEmpty
                      ? Center(child: Text("ไม่มีการแจ้งเตือน", style: TextStyle(color: Colors.white70)))
                      : ListView.builder( itemCount: notifications.length, itemBuilder: (context, index) {
                    final item = notifications[index]; DateTime? notificationTime = DateTime.tryParse(item['time'] ?? ''); String timeStr = 'Invalid Time'; if(notificationTime!=null){ try{ timeStr = DateFormat('HH:mm:ss dd/MM').format(notificationTime.toLocal()); } catch(e){} }
                    return ListTile( dense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8), title: Text('${item['message'] ?? ''}', style: TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 2), subtitle: Text(timeStr, style: TextStyle(color: Colors.white70, fontSize: 11)), leading: Icon(Icons.notifications_active, color: Colors.white, size: 18));
                  }),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---
  Widget _buildUserInfoContainer({required BuildContext context, required bool hasData, Map<String, dynamic>? userData}) {
    String patientUsername = userData?['username'] as String? ?? 'N/A';
    String patientAgeStr = userData?['age']?.toString() ?? 'N/A';
    String patientAllergies = userData?['allergies'] as String? ?? 'N/A';
    String patientSeverity = userData?['severity'] as String? ?? 'N/A';
    String? profileImageUrl = userData?['profileImageUrl'] as String?;

    Widget avatarWidget;
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      avatarWidget = CircleAvatar( radius: 35, backgroundColor: Colors.white.withOpacity(0.3), backgroundImage: NetworkImage(profileImageUrl),
        onBackgroundImageError: (exception, stackTrace) { print("User info image Load Error: $exception"); },
      );
    } else {
      avatarWidget = Icon(Icons.account_circle, color: Colors.white, size: 70);
    }

    Gradient gradient = hasData
        ? LinearGradient(colors: [Colors.lightBlue.shade300, Colors.blueAccent.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight)
        : LinearGradient(colors: [Colors.redAccent.shade100, Colors.orangeAccent.shade100], begin: Alignment.topLeft, end: Alignment.bottomRight);

    return GestureDetector( onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => UserInfoPage())),
        child: Container( margin: const EdgeInsets.only(left: 8.0, bottom: 16.0), padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration( gradient: gradient, borderRadius: BorderRadius.circular(12), boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: Offset(0, 2)) ]),
          height: 300,
          child: Column( mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
            avatarWidget, SizedBox(height: 15),
            Text(hasData ? 'ข้อมูลผู้ป่วย' : 'เพิ่มข้อมูล', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center), SizedBox(height: 10),
            if (hasData) ...[
              _buildUserInfoRow('ชื่อ:', patientUsername), _buildUserInfoRow('อายุ:', patientAgeStr),
              _buildUserInfoRow('แพ้ยา:', patientAllergies), _buildUserInfoRow('ระดับ:', patientSeverity),
            ] else ...[
              SizedBox(height: 10), Icon(Icons.add_circle_outline, color: Colors.white, size: 30), SizedBox(height: 5),
              Text( 'แตะเพื่อเพิ่ม/แก้ไข', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14), textAlign: TextAlign.center ),
            ],
          ]),
        )
    );
  }

  Widget _buildUserInfoRow(String label, String value) {
    String displayValue = (value.isEmpty || value.toLowerCase() == 'n/a') ? 'N/A' : value;
    return Padding( padding: const EdgeInsets.symmetric(vertical: 3.0), child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [
      Flexible( child: Text( '$label $displayValue', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 1, ),),
    ],),);
  }
  // ... ภายใน StatefulWidget ของ HomePage ...



} // End of _HomePageState class