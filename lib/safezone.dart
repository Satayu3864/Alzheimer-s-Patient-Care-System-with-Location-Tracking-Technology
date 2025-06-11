import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
// *** เพิ่ม Import สำหรับ Color Picker ***
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class SafeZonePage extends StatefulWidget {
  final LatLng initialPosition;

  SafeZonePage({required this.initialPosition});

  @override
  _SafeZonePageState createState() => _SafeZonePageState();
}

class _SafeZonePageState extends State<SafeZonePage> {
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  // ควรใช้ User ID จาก FirebaseAuth ถ้าเป็นไปได้ แต่ใช้ค่าเดิมไปก่อน
  final String deviceID = "icE1FNvXIIOVSxwG9si03rYaXXE2";

  StreamSubscription? _locationSubscription;
  StreamSubscription? _safeZoneSubscription;

  bool _isAddingNewSafeZone = false;
  Map<String, Map<String, dynamic>> _safeZones = {};
  String? _selectedSafeZoneId;
  final TextEditingController _safeZoneNameController = TextEditingController();

  final Color _defaultZoneColor = Colors.blue;

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

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentPosition != null) {
        try { _mapController.move(_currentPosition!, 15.0); }
        catch (e) { print("Error initial map move: $e"); }
      } else if (mounted) {
        try { _mapController.move(LatLng(13.7563, 100.5018), 6.0); } catch (e) {}
      }
    });
    _listenToRealtimeLocation();
    _listenToSafeZones();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _safeZoneSubscription?.cancel();
    _safeZoneNameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  IconData _getIconFromString(String? iconId) {
    return availableIcons[iconId?.toLowerCase() ?? 'default'] ?? Icons.location_pin;
  }

  void _listenToSafeZones() {
    _safeZoneSubscription?.cancel();
    print("SafeZonePage: Listening to safe_zones/$deviceID");
    _safeZoneSubscription = _database.child('safe_zones/$deviceID').onValue.listen((event) {
      if (!mounted) return;
      Map<String, Map<String, dynamic>> tempSafeZones = {};
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map?;
        if (data != null) {
          data.forEach((key, value) {
            if (value is Map && key is String) { // Ensure key is String
              if (value.containsKey('latitude') && value.containsKey('longitude') && value.containsKey('radius')) {
                try {
                  double latitude = (value['latitude'] as num).toDouble();
                  double longitude = (value['longitude'] as num).toDouble();
                  double radius = (value['radius'] as num).toDouble();
                  String name = value['name']?.toString() ?? key;

                  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 || radius <= 0 || name.trim().isEmpty) {
                    throw FormatException("Invalid data values for key $key");
                  }
                  int? colorValue = value['color'] is int ? value['color'] : null;
                  String? iconId = value['iconId'] as String?;

                  Map<String, dynamic> zoneData = Map<String, dynamic>.from(value);
                  zoneData['latitude'] = latitude;
                  zoneData['longitude'] = longitude;
                  zoneData['radius'] = radius;
                  zoneData['name'] = name.trim();
                  zoneData['colorValue'] = colorValue ?? _defaultZoneColor.value;
                  zoneData['iconId'] = iconId ?? 'default';
                  tempSafeZones[key] = zoneData;

                } catch (e) { print("SafeZonePage: Error parsing safe zone data for key $key: $e"); }
              } else { print("SafeZonePage: Skipping incomplete safe zone data for key $key"); }
            } else { print("SafeZonePage: Skipping invalid entry type (key: $key, value: $value)"); }
          });
        }
      } else { print("SafeZonePage: No safe zones found for $deviceID"); }

      if (mounted) {
        // Check if maps are actually different before updating state
        if (_safeZones.toString() != tempSafeZones.toString()) {
          print("SafeZonePage: Safe zones updated.");
          setState(() {
            _safeZones = tempSafeZones;
            // Ensure selected ID is still valid
            if (_selectedSafeZoneId != null && !_safeZones.containsKey(_selectedSafeZoneId)) {
              _selectedSafeZoneId = _safeZones.isNotEmpty ? _safeZones.keys.first : null;
              print("SafeZonePage: Selected zone removed, resetting selection.");
            } else if (_safeZones.isEmpty) {
              _selectedSafeZoneId = null;
            }
          });
        }
      }
    }, onError: (error) {
      print("SafeZonePage: Error listening to safe zones: $error");
      if (mounted) { setState(() { _safeZones = {}; _selectedSafeZoneId = null; }); }
    });
  }


  void _listenToRealtimeLocation() {
    _locationSubscription?.cancel();
    print("SafeZonePage: Listening to locations/$deviceID");
    _locationSubscription = _database.child('locations/$deviceID').onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        if (data.containsKey('latitude') && data.containsKey('longitude')) {
          try {
            double latitude = (data['latitude'] as num).toDouble();
            double longitude = (data['longitude'] as num).toDouble();
            if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) { throw FormatException("Invalid Lat/Lon values: $latitude, $longitude"); }
            LatLng newPosition = LatLng(latitude, longitude);
            if (mounted && (_currentPosition?.latitude != newPosition.latitude || _currentPosition?.longitude != newPosition.longitude)) {
              print("SafeZonePage: Location updated: $newPosition");
              setState(() { _currentPosition = newPosition; });
            }
          } catch (e) { print("SafeZonePage: Error parsing location data or invalid values: $e"); }
        }
      } else {
        if (mounted && _currentPosition != null) {
          print("SafeZonePage: Location data became null.");
          setState(() => _currentPosition = null);
        }
      }
    }, onError: (error) { print("SafeZonePage: Error listening to location: $error"); });
  }

  Future<void> _saveSafeZone(LatLng latLng, double radius, Color selectedColor, String selectedIconId) async {
    if (!mounted) return;
    if (_safeZoneNameController.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("กรุณาตั้งชื่อพื้นที่ปลอดภัย")), );
      return;
    }

    DateTime now = DateTime.now();
    String formattedTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    String? safeZoneId = _database.child('safe_zones/$deviceID').push().key; // Get key first

    if (safeZoneId == null) {
      print("!!! SafeZonePage: Error getting push key for new safe zone");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้าง ID')), );
      return;
    }

    try {
      print("Saving new safe zone: ID=$safeZoneId, Name=${_safeZoneNameController.text.trim()}, Icon=$selectedIconId, Color=${selectedColor.value}");
      await _database.child('safe_zones/$deviceID/$safeZoneId').set({
        'name': _safeZoneNameController.text.trim(),
        'latitude': latLng.latitude,
        'longitude': latLng.longitude,
        'radius': radius,
        'color': selectedColor.value, // Store color as integer
        'iconId': selectedIconId,
        'timestamp': formattedTime, // Optional: add timestamp
      });
      print("Save successful.");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('บันทึก "${_safeZoneNameController.text.trim()}" เรียบร้อยแล้ว!')), );
        setState(() {
          _isAddingNewSafeZone = false;
          _selectedSafeZoneId = safeZoneId; // Auto-select the new zone
          _safeZoneNameController.clear();
        });
        try { _mapController.move(latLng, 16.0); } // Move map to new zone
        catch(e) {print("Error moving map after save: $e");}
      }
    } catch (e) {
      print("!!! SafeZonePage: Error saving safe zone: $e");
      if(mounted){ ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e')), ); }
    }
  }

  // --- Function to show Color Picker Dialog ---
  Future<Color?> _showColorPickerDialog(BuildContext context, Color initialColor) async {
    Color? pickedColor = initialColor; // Start with the initial color
    return showDialog<Color>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('เลือกสี'),
          content: SingleChildScrollView(
            // *** Use ColorPicker from the package ***
            child: ColorPicker(
              pickerColor: pickedColor ?? _defaultZoneColor, // Current color
              onColorChanged: (Color color) {
                // Update the temporary color when changed
                pickedColor = color;
              },
              // Optional customizations:
              // colorPickerWidth: 300.0,
              // pickerAreaHeightPercent: 0.7,
              // enableAlpha: false, // Disable alpha slider if not needed
              // displayThumbColor: true,
              // paletteType: PaletteType.hsv,
              // pickerAreaBorderRadius: const BorderRadius.only(
              //   topLeft: Radius.circular(2.0),
              //   topRight: Radius.circular(2.0),
              // ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('ตกลง'),
              onPressed: () {
                // Return the finally selected color
                Navigator.of(context).pop(pickedColor);
              },
            ),
          ],
        );
      },
    );
  }


  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    if (!mounted) return;
    if (_isAddingNewSafeZone) {
      _safeZoneNameController.clear();
      Color selectedColor = _defaultZoneColor;
      double radius = 15.0;
      String selectedIconId = 'default';

      print("Map tapped in Add Mode at $latLng. Showing Add Dialog.");

      showDialog(
        context: context,
        builder: (context) {
          // Use StatefulBuilder to manage dialog's internal state (color, radius, icon)
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return AlertDialog(
                title: Text('กำหนดพื้นที่ปลอดภัยใหม่'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField( controller: _safeZoneNameController, decoration: InputDecoration(labelText: "ชื่อพื้นที่"), autofocus: true, ),
                      SizedBox(height: 16),
                      Text("ระยะ: ${radius.toStringAsFixed(0)} เมตร"),
                      Slider( min: 6, max: 50, // Adjusted range slightly
                        divisions: 44, value: radius, label: "${radius.toStringAsFixed(0)} ม.",
                        onChanged: (value) { setDialogState(() { radius = value; }); },
                      ),
                      SizedBox(height: 16),

                      // --- Modified Color Selection ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("เลือกสี:"),
                          GestureDetector(
                            onTap: () async {
                              // Show the color picker dialog
                              final Color? picked = await _showColorPickerDialog(context, selectedColor);
                              if (picked != null && picked != selectedColor) {
                                setDialogState(() {
                                  selectedColor = picked; // Update dialog state with picked color
                                });
                              }
                            },
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                  color: selectedColor, // Show currently selected color
                                  shape: BoxShape.circle,
                                  border: Border.all( color: Colors.grey.shade400, width: 1),
                                  boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 3)]
                              ),
                            ),
                          ),
                        ],
                      ),
                      // SizedBox(height: 12), // Remove the color bar preview if desired
                      // Container( decoration: BoxDecoration(color: selectedColor, borderRadius: BorderRadius.circular(4)), width: double.infinity, height: 20),
                      SizedBox(height: 20), // Add space before icon selection

                      // --- Icon Selection UI (Unchanged) ---
                      Text("เลือกไอคอน:"), SizedBox(height: 8),
                      Wrap( spacing: 12.0, runSpacing: 8.0, children: availableIcons.entries.map((entry) {
                        final iconId = entry.key; final iconData = entry.value;
                        final bool isIconSelected = selectedIconId == iconId;
                        return GestureDetector(
                          onTap: () { setDialogState(() { selectedIconId = iconId; }); },
                          child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: isIconSelected ? Theme.of(context).primaryColorLight.withOpacity(0.5) : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all( color: isIconSelected ? Theme.of(context).primaryColor : Colors.grey.shade300, width: isIconSelected ? 2 : 1 )
                              ),
                              child: Tooltip( message: iconId, child: Icon( iconData, size: 30, color: isIconSelected ? Theme.of(context).primaryColorDark : Colors.grey.shade700, ))
                          ),
                        );
                      }).toList(),
                      ),
                      // --- End Icon Selection UI ---
                    ],
                  ),
                ),
                actions: [
                  TextButton( onPressed: () { Navigator.of(context).pop(); _cancelAddingNewSafeZone(); }, child: Text('ยกเลิก'), ),
                  // Pass the final selected state to save function
                  TextButton( onPressed: () {
                    _saveSafeZone(latLng, radius, selectedColor, selectedIconId);
                    Navigator.of(context).pop();
                  },
                    child: Text('บันทึก'),
                  ),
                ],
              );
            },
          );
        },
      );
    } else {
      _checkTapOnExistingZones(latLng);
    }
  }


  void _checkTapOnExistingZones(LatLng tapLatLng) {
    String? tappedZoneId;
    double minDistance = 50.0; // Sensitivity for tapping near center

    _safeZones.forEach((key, zoneData) {
      double? latitude = zoneData['latitude'] as double?;
      double? longitude = zoneData['longitude'] as double?;
      if (latitude != null && longitude != null) {
        try {
          LatLng zoneCenter = LatLng(latitude, longitude);
          double distance = Geolocator.distanceBetween( tapLatLng.latitude, tapLatLng.longitude, zoneCenter.latitude, zoneCenter.longitude );
          // Prioritize selecting if tap is very close to center, regardless of current selection
          if (distance < minDistance) {
            minDistance = distance;
            tappedZoneId = key;
          }
        } catch(e) { print("SafeZonePage: Error checking tap distance: $e"); }
      }
    });

    // If a zone center was tapped and it's different from current selection
    if (tappedZoneId != null && tappedZoneId != _selectedSafeZoneId) {
      print("SafeZonePage: Tapped near zone: $tappedZoneId");
      if (mounted) {
        setState(() { _selectedSafeZoneId = tappedZoneId; _isAddingNewSafeZone = false; });
        // Move map to the tapped zone's center
        if (_safeZones.containsKey(tappedZoneId)){
          final zoneData = _safeZones[tappedZoneId]!;
          double? latitude = zoneData['latitude'] as double?;
          double? longitude = zoneData['longitude'] as double?;
          if(latitude != null && longitude != null){
            try { _mapController.move(LatLng(latitude, longitude), 16.0); }
            catch (e) { print("SafeZonePage: Error moving map on tap selection: $e"); }
          }
        }
      }
    }
    // Optional: Deselect if tapping far from any zone center
    // else if (tappedZoneId == null && _selectedSafeZoneId != null && !_isAddingNewSafeZone) {
    //    print("SafeZonePage: Tapped empty space, deselecting zone.");
    //    if (mounted) { setState(() { _selectedSafeZoneId = null; }); }
    // }
  }

  void _startAddingNewSafeZone() {
    if (!mounted) return;
    print("SafeZonePage: Starting Add New Zone mode.");
    setState(() { _isAddingNewSafeZone = true; _selectedSafeZoneId = null; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("แตะบนแผนที่เพื่อเลือกจุดศูนย์กลาง"), duration: Duration(seconds: 2)), );
    }
  }

  void _cancelAddingNewSafeZone() {
    if (!mounted) return;
    print("SafeZonePage: Cancelling Add New Zone mode.");
    setState(() { _isAddingNewSafeZone = false; _safeZoneNameController.clear(); });
  }

  Future<void> _editSelectedSafeZone() async {
    if (!mounted || _selectedSafeZoneId == null || !_safeZones.containsKey(_selectedSafeZoneId)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("กรุณาเลือกพื้นที่ปลอดภัยที่จะแก้ไข")), );
      return;
    }

    final safeZoneData = _safeZones[_selectedSafeZoneId]!;
    _safeZoneNameController.text = safeZoneData['name'] ?? '';
    // Initialize with current values
    Color currentColor = Color(safeZoneData['colorValue'] ?? _defaultZoneColor.value);
    double currentRadius = safeZoneData['radius'] as double? ?? 15.0;
    String currentIconId = safeZoneData['iconId'] ?? 'default';

    print("SafeZonePage: Editing zone '$_selectedSafeZoneId'. Initial: Radius=$currentRadius, Icon=$currentIconId, Color=${currentColor.value}");

    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) {
        // State variables for the dialog
        String selectedIconId = currentIconId; Color selectedColor = currentColor; double radius = currentRadius;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text('แก้ไขพื้นที่ปลอดภัย'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField( controller: _safeZoneNameController, decoration: InputDecoration(labelText: "ชื่อพื้นที่"), ), SizedBox(height: 16),
                    Text("ระยะ: ${radius.toStringAsFixed(0)} เมตร"),
                    Slider( min: 6, max: 50, divisions: 44, value: radius, label: "${radius.toStringAsFixed(0)} ม.",
                      onChanged: (value) { setDialogState(() { radius = value; }); },
                    ), SizedBox(height: 16),

                    // --- Modified Color Selection ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("เลือกสี:"),
                        GestureDetector(
                          onTap: () async {
                            final Color? picked = await _showColorPickerDialog(context, selectedColor);
                            if (picked != null && picked != selectedColor) {
                              setDialogState(() { selectedColor = picked; });
                            }
                          },
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                                color: selectedColor, shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade400, width: 1),
                                boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 3)]
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20), // Add space

                    // --- Icon Selection UI (Unchanged) ---
                    Text("เลือกไอคอน:"), SizedBox(height: 8),
                    Wrap( spacing: 12.0, runSpacing: 8.0, children: availableIcons.entries.map((entry) {
                      final iconId = entry.key; final iconData = entry.value;
                      final bool isIconSelected = selectedIconId == iconId;
                      return GestureDetector(
                        onTap: () { setDialogState(() { selectedIconId = iconId; }); },
                        child: Container(
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: isIconSelected ? Theme.of(context).primaryColorLight.withOpacity(0.5) : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all( color: isIconSelected ? Theme.of(context).primaryColor : Colors.grey.shade300, width: isIconSelected ? 2 : 1 )
                            ),
                            child: Tooltip( message: iconId, child: Icon( iconData, size: 30, color: isIconSelected ? Theme.of(context).primaryColorDark : Colors.grey.shade700, ))
                        ),
                      );
                    }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton( onPressed: () => Navigator.of(context).pop(false), child: Text('ยกเลิก'), ),
                TextButton(
                  onPressed: () async {
                    if (!mounted) return;
                    if (_safeZoneNameController.text.trim().isEmpty) {
                      if(mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("กรุณาตั้งชื่อพื้นที่ปลอดภัย")), );
                      return; // Don't close dialog if name is empty
                    }
                    try {
                      print("Updating zone '$_selectedSafeZoneId'. New values: Radius=$radius, Icon=$selectedIconId, Color=${selectedColor.value}");
                      await _database.child('safe_zones/$deviceID/$_selectedSafeZoneId').update({
                        'name': _safeZoneNameController.text.trim(),
                        'radius': radius, // Use radius from dialog state
                        'color': selectedColor.value, // Use selectedColor from dialog state
                        'iconId': selectedIconId, // Use selectedIconId from dialog state
                      });
                      print("Update successful.");
                      Navigator.of(context).pop(true); // Indicate save occurred
                    } catch (e) {
                      print("!!! SafeZonePage: Error updating safe zone: $e");
                      if(mounted){ ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('เกิดข้อผิดพลาดในการแก้ไข: $e')), ); }
                      Navigator.of(context).pop(false); // Indicate save failed
                    }
                  },
                  child: Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );

    // Show confirmation message outside dialog if save was successful
    if (mounted && result == true) {
      ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('แก้ไข "${_safeZoneNameController.text.trim()}" เรียบร้อยแล้ว!')), );
      _safeZoneNameController.clear(); // Clear controller after successful edit
    } else if (mounted && result == false){
      _safeZoneNameController.clear(); // Clear controller even if cancelled
    }
  }


  Future<void> _deleteSelectedSafeZone() async {
    if (!mounted || _selectedSafeZoneId == null || !_safeZones.containsKey(_selectedSafeZoneId)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text("กรุณาเลือกพื้นที่ปลอดภัยที่จะลบ")), );
      return;
    }

    String zoneNameToDelete = _safeZones[_selectedSafeZoneId]!['name'] ?? "พื้นที่ไม่มีชื่อ";

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: Text('คุณแน่ใจหรือไม่ว่าต้องการลบ "$zoneNameToDelete"?'),
          actions: <Widget>[
            TextButton( onPressed: () => Navigator.of(context).pop(false), child: const Text('ยกเลิก'), ),
            TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true), // Confirm deletion
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (mounted && confirmed == true) {
      try {
        String zoneIdToDelete = _selectedSafeZoneId!; // Keep ID before state changes
        print("SafeZonePage: Deleting zone '$zoneNameToDelete' (ID: $zoneIdToDelete)");
        await _database.child('safe_zones/$deviceID/$zoneIdToDelete').remove();
        print("Deletion successful from Firebase.");

        // Show confirmation message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('ลบ "$zoneNameToDelete" เรียบร้อยแล้ว!')), );
          // State update (clearing _selectedSafeZoneId or shifting it)
          // will be handled by the _listenToSafeZones listener automatically.
        }

      } catch (e) {
        print("!!! SafeZonePage: Error deleting safe zone: $e");
        if(mounted){ ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('เกิดข้อผิดพลาดในการลบ: $e')), ); }
      }
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    final LatLng centerPosition = _currentPosition ?? widget.initialPosition ?? LatLng(13.7563, 100.5018); // Add default fallback
    final double initialZoom = _currentPosition != null ? 15.0 : 13.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('กำหนดพื้นที่ปลอดภัย'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // --- Map View ---
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: centerPosition, minZoom: 5.0, maxZoom: 18.0, zoom: initialZoom,
              onTap: _onMapTap, // Handle map taps
              interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate, // Disable rotation
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.testcode', // TODO: Change package name
              ),
              // Draw Circles (Highlight selected)
              if (_safeZones.isNotEmpty) CircleLayer(
                circles: _safeZones.entries.map((entry) {
                  final id = entry.key; final data = entry.value;
                  double? lat = data['latitude'] as double?; double? lon = data['longitude'] as double?; double? rad = data['radius'] as double?;
                  if(lat==null||lon==null||rad==null||rad<=0) return null;
                  try {
                    final pos = LatLng(lat, lon);
                    final color = Color(data['colorValue'] ?? _defaultZoneColor.value);
                    final selected = id == _selectedSafeZoneId;
                    return CircleMarker(
                        point: pos, radius: rad, useRadiusInMeter: true,
                        color: color.withOpacity(selected ? 0.45 : 0.20), // More opaque if selected
                        borderColor: color.withOpacity(selected ? 0.9 : 0.6),
                        borderStrokeWidth: selected ? 2.5 : 1.5 // Thicker border if selected
                    );
                  } catch (e){ return null; }
                }).whereType<CircleMarker>().toList(),
              ),
              // Draw Name/Icon Markers
              if (_safeZones.isNotEmpty) MarkerLayer(
                markers: _safeZones.entries.map((entry) {
                  final id = entry.key; final data = entry.value;
                  double? lat = data['latitude'] as double?; double? lon = data['longitude'] as double?;
                  if(lat==null||lon==null) return null;
                  String name = data['name'] ?? id; // Use ID if name missing
                  String? iconId = data['iconId'] as String?;
                  try {
                    final pos = LatLng(lat, lon);
                    final icon = _getIconFromString(iconId);
                    // Optional: Highlight marker if selected? (Could add border/background)
                    // final bool isSelected = id == _selectedSafeZoneId;
                    return Marker(
                        point: pos, width: 120, height: 55,
                        anchorPos: AnchorPos.align(AnchorAlign.bottom),
                        builder: (ctx) => Column( mainAxisSize: MainAxisSize.min, children: [
                          Container( padding: EdgeInsets.all(4), decoration: BoxDecoration( color: Colors.white.withOpacity(0.85), shape: BoxShape.circle, boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: Offset(0, 1), ) ] ), child: Icon(icon, size: 22, color: Colors.blueGrey.shade800)),
                          SizedBox(height: 2),
                          Container( padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration( color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(3), ), child: Text( name, style: TextStyle( fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold,), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 1, ))
                        ] )
                    );
                  } catch (e){ return null; }
                }).whereType<Marker>().toList(),
              ),
              // Current Device Position Marker
              if (_currentPosition != null) MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition!, width: 40, height: 40,
                    builder: (ctx) => Tooltip( message: 'ตำแหน่งอุปกรณ์', child: Icon( Icons.location_history, color: Colors.red.shade800, size: 40.0, shadows: [ Shadow(blurRadius: 8.0, color: Colors.black.withOpacity(0.7), offset: Offset(2,2)) ], )),
                    anchorPos: AnchorPos.align(AnchorAlign.center), // Center anchor for this icon
                  ),
                ],
              ),
            ],
          ),

          // --- Top UI (Dropdown Menu for selecting zone) ---
          Positioned( top: 10, left: 10, right: 10, child: Card( // Use Card for better elevation/visual separation
            elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration( color: Colors.white, borderRadius: BorderRadius.circular(8), ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSafeZoneId, // Current selection
                  isExpanded: true, // Make dropdown take full width
                  hint: Text("เลือกพื้นที่", style: TextStyle(color: Colors.black54)), // Hint text
                  // Build dropdown items
                  items: (_safeZones.isEmpty)
                  // Show disabled item if no zones exist
                      ? [DropdownMenuItem(child: Text("ไม่มีพื้นที่กำหนด", style: TextStyle(color: Colors.grey)), value: null, enabled: false,)]
                  // Map existing zones to dropdown items
                      : _safeZones.entries.map((entry) {
                    String name = entry.value['name']?.toString() ?? "พื้นที่ไม่มีชื่อ";
                    Color color = Color(entry.value['colorValue'] ?? _defaultZoneColor.value);
                    return DropdownMenuItem(
                        value: entry.key, // Use zone ID as value
                        child: Row(children: [
                          // Show color indicator
                          Container(width: 14, height: 14, decoration: BoxDecoration( color: color, border: Border.all(color: Colors.grey.shade500, width: 0.5), shape: BoxShape.circle ), margin: EdgeInsets.only(right: 10)),
                          // Show zone name
                          Expanded(child: Text( name, style: TextStyle(color: Colors.black87, fontSize: 15), overflow: TextOverflow.ellipsis)),
                        ])
                    );
                  }).toList(),
                  // Handle dropdown selection change
                  onChanged: (String? newValue) {
                    if (!mounted || newValue == null || newValue == _selectedSafeZoneId) return;
                    setState(() {
                      _selectedSafeZoneId = newValue;
                      _isAddingNewSafeZone = false; // Exit add mode if selecting from dropdown
                      // Move map to selected zone
                      if (_safeZones.containsKey(_selectedSafeZoneId)) {
                        final zone = _safeZones[_selectedSafeZoneId]!;
                        double? lat = zone['latitude'] as double?;
                        double? lon = zone['longitude'] as double?;
                        if(lat!=null && lon!=null) {
                          try{ _mapController.move(LatLng(lat, lon), 16.0); } catch(e){}
                        }
                      }
                    });
                  },
                  icon: Icon(Icons.arrow_drop_down, color: Colors.blueGrey), // Dropdown icon
                ),
              ),
            ),
          ),),

          // --- Bottom UI (Action Buttons) ---
          Positioned( bottom: 20, left: 15, right: 15, child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space out buttons
            children: [
              // Add/Cancel Button (Flexible for smaller screens)
              Flexible( flex: 2, // Give slightly more space
                child: ElevatedButton.icon(
                  icon: Icon(_isAddingNewSafeZone ? Icons.cancel : Icons.add_location_alt_outlined),
                  onPressed: _isAddingNewSafeZone ? _cancelAddingNewSafeZone : _startAddingNewSafeZone,
                  label: Text(_isAddingNewSafeZone ? 'ยกเลิก' : 'เพิ่มพื้นที่'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _isAddingNewSafeZone ? Colors.grey.shade600 : Theme.of(context).colorScheme.primary, // Dynamic color
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)
                  ),
                ),
              ),
              // Edit/Delete Buttons (Show only if a zone is selected and not in add mode)
              if (_selectedSafeZoneId != null && !_isAddingNewSafeZone)
                Flexible( flex: 3, // Allow more space for two buttons
                  child: Row( mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                    // Edit Button
                    ElevatedButton.icon(
                      icon: Icon(Icons.edit_outlined, size: 18),
                      onPressed: _editSelectedSafeZone,
                      label: Text('แก้ไข'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          textStyle: TextStyle(fontSize: 14)
                      ),
                    ),
                    SizedBox(width: 8), // Space between buttons
                    // Delete Button
                    ElevatedButton.icon(
                      icon: Icon(Icons.delete_forever_outlined, size: 18),
                      onPressed: _deleteSelectedSafeZone,
                      label: Text('ลบ'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700, foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          textStyle: TextStyle(fontSize: 14)
                      ),
                    ),
                  ],
                  ),
                )
            ],
          ) ),

          // --- Add Mode Banner (Overlay) ---
          if (_isAddingNewSafeZone)
            Positioned(
              top: 75, // Adjust position below dropdown card
              left: 0, right: 0,
              child: IgnorePointer( // Banner doesn't block map interaction
                child: Container(
                  color: Colors.black.withOpacity(0.7), // Semi-transparent background
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text( "แตะบนแผนที่เพื่อกำหนดจุดศูนย์กลาง",
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
} // End of _SafeZonePageState