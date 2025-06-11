import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:io'; // ยังคงต้องใช้สำหรับ Mobile
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart'; // <-- ไม่ใช้แล้ว หรือคอมเมนต์ออก
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart'; // <-- CLOUDINARY: Import เพิ่ม

class UserInfoPage extends StatefulWidget {
  @override
  _UserInfoPageState createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {

  // --- CLOUDINARY: ใส่ข้อมูล Cloudinary ของคุณตรงนี้ ---
  // !!! สำคัญมาก: แทนที่ด้วย Cloud Name และ Unsigned Upload Preset จริงๆ ของคุณ !!!
  final String _cloudinaryCloudName = 'dujpogr95';
  final String _cloudinaryUploadPreset = 'flutter_unsigned';
  // ----------------------------------------------------

  // --- Controllers ---
  final TextEditingController _userIDController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _severityController = TextEditingController();
  final TextEditingController _caretakerNameController = TextEditingController();
  final TextEditingController _caretakerAgeController = TextEditingController();
  final TextEditingController _caretakerGenderController = TextEditingController();
  final TextEditingController _caretakerRelationController = TextEditingController();
  final TextEditingController _caretakerPhoneController = TextEditingController();
  final TextEditingController _caretakerAddressController = TextEditingController();
  final TextEditingController _emergencyPhoneController = TextEditingController();
  final TextEditingController _doctorNameController = TextEditingController();
  final TextEditingController _doctorPhoneController = TextEditingController();


  // --- State Variables ---
  String? documentId; // เก็บ UID ของ User ที่ login อยู่
  File? _pickedImage; // สำหรับ Mobile preview
  Uint8List? _pickedImageBytes; // สำหรับ Web preview
  String? _imageUrl; // URL รูปภาพจาก Cloudinary (หรือ Firestore ตอน fetch)
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo(); // โหลดข้อมูลเมื่อหน้าถูกสร้าง
  }

  @override
  void dispose() {
    // Dispose controllers ทั้งหมดเพื่อคืน memory
    _userIDController.dispose();
    _usernameController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _allergiesController.dispose();
    _severityController.dispose();
    _caretakerNameController.dispose();
    _caretakerAgeController.dispose();
    _caretakerGenderController.dispose();
    _caretakerRelationController.dispose();
    _caretakerPhoneController.dispose();
    _caretakerAddressController.dispose();
    _emergencyPhoneController.dispose();
    _doctorNameController.dispose();
    _doctorPhoneController.dispose();
    super.dispose();
  }

  // --- เลือกและอัปโหลดรูปภาพไปยัง Cloudinary ---
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('เลือกแหล่งที่มาของรูปภาพ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: Icon(Icons.photo_library), title: Text('เลือกรูปภาพ'), onTap: () => Navigator.of(context).pop(ImageSource.gallery)),
            ListTile(leading: Icon(Icons.camera_alt), title: Text('ถ่ายภาพ'), onTap: () => Navigator.of(context).pop(ImageSource.camera)),
          ],
        ),
      ),
    );
    if (source == null) return;

    final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    final cloudinary = CloudinaryPublic(_cloudinaryCloudName, _cloudinaryUploadPreset, cache: false);
    String? downloadUrl;
    String? cloudinaryPublicId;

    try {
      CloudinaryResponse response;
      String tempFileNameForBytes = 'upload_${DateTime.now().millisecondsSinceEpoch}';

      if (kIsWeb) {
        print("Platform is Web. Uploading to Cloudinary using bytes...");
        Uint8List bytes = await pickedFile.readAsBytes();
        if (mounted) setState(() { _pickedImageBytes = bytes; _pickedImage = null; });

        response = await cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(bytes, identifier: tempFileNameForBytes),
        );
      } else {
        print("Platform is Mobile. Uploading to Cloudinary using file path...");
        File imageFile = File(pickedFile.path);
        if (mounted) setState(() { _pickedImage = imageFile; _pickedImageBytes = null; });

        response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(pickedFile.path),
        );
      }

      // --- ตรวจสอบผลลัพธ์การอัปโหลด ---
      if (response.secureUrl.isNotEmpty) {
        downloadUrl = response.secureUrl;
        cloudinaryPublicId = response.publicId;
        print("Cloudinary Upload successful. URL: $downloadUrl, Public ID: $cloudinaryPublicId");

        if (mounted) {
          setState(() {
            _imageUrl = downloadUrl;
            _pickedImage = null;
            _pickedImageBytes = null;
          });
        }
      } else {
        print("Cloudinary Upload possibly failed: Secure URL is empty.");
        throw Exception('Cloudinary upload returned empty URL');
      }
      // --- จบการตรวจสอบผลลัพธ์ ---

    } catch (e) {
      print("Error during Cloudinary image upload: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดรูปภาพล้มเหลว: ${e.toString()}')));
        setState(() {
          _pickedImage = null;
          _pickedImageBytes = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- โหลดข้อมูลผู้ใช้จาก Firestore ---
  Future<void> _fetchUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!mounted) return;
    setState(() => _isLoading = true);
    final docRef = FirebaseFirestore.instance.collection('user_info').doc(user.uid);

    try {
      final docSnap = await docRef.get();
      if (!mounted) return;

      if (docSnap.exists) {
        final data = docSnap.data()!;
        setState(() {
          documentId = user.uid;
          _userIDController.text = data['userID'] ?? '';
          _usernameController.text = data['username'] ?? '';
          _ageController.text = data['age'] ?? '';
          _genderController.text = data['gender'] ?? '';
          _allergiesController.text = data['allergies'] ?? '';
          _severityController.text = data['severity'] ?? '';
          _imageUrl = data['profileImageUrl']; // โหลด Cloudinary URL
          _caretakerNameController.text = data['caretakerName'] ?? '';
          _caretakerAgeController.text = data['caretakerAge'] ?? '';
          _caretakerGenderController.text = data['caretakerGender'] ?? '';
          _caretakerRelationController.text = data['caretakerRelation'] ?? '';
          _caretakerPhoneController.text = data['caretakerPhone'] ?? '';
          _caretakerAddressController.text = data['caretakerAddress'] ?? '';
          _emergencyPhoneController.text = data['emergencyPhone'] ?? '';
          _doctorNameController.text = data['doctorName'] ?? '';
          _doctorPhoneController.text = data['doctorPhone'] ?? '';
          _pickedImage = null;
          _pickedImageBytes = null;
          print('Fetched Image URL from Firestore: $_imageUrl');
        });
      } else {
        print("User info document does not exist for UID: ${user.uid}. Generating new User ID.");
        int newUserId = await _generateUserId();
        if (mounted) {
          setState(() {
            documentId = user.uid;
            _userIDController.text = newUserId.toString();
            _usernameController.clear(); _ageController.clear(); _genderController.clear();
            _allergiesController.clear(); _severityController.clear();
            _imageUrl = null;
            _caretakerNameController.clear(); _caretakerAgeController.clear(); _caretakerGenderController.clear();
            _caretakerRelationController.clear(); _caretakerPhoneController.clear(); _caretakerAddressController.clear();
            _emergencyPhoneController.clear(); _doctorNameController.clear(); _doctorPhoneController.clear();
            _pickedImage = null; _pickedImageBytes = null;
          });
        }
      }
    } catch (e) {
      print("Error fetching user info: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- สร้าง User ID ใหม่ ---
  Future<int> _generateUserId() async {
    final collectionRef = FirebaseFirestore.instance.collection('user_info');
    final querySnapshot = await collectionRef.orderBy('userID', descending: true).limit(1).get();
    if (querySnapshot.docs.isNotEmpty) {
      final lastId = int.tryParse(querySnapshot.docs.first.data()['userID'] ?? '0') ?? 0;
      return lastId + 1;
    }
    return 1;
  }

  // --- บันทึกข้อมูลผู้ใช้ลง Firestore ---
  Future<void> _saveUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_userIDController.text.isEmpty) {
      int newUserId = await _generateUserId();
      if(!mounted) return;
      _userIDController.text = newUserId.toString();
    }

    final data = {
      'userID': _userIDController.text.trim(),
      'username': _usernameController.text.trim(),
      'age': _ageController.text.trim(),
      'gender': _genderController.text.trim(),
      'allergies': _allergiesController.text.trim(),
      'severity': _severityController.text.trim(),
      if (_imageUrl != null) 'profileImageUrl': _imageUrl, // บันทึก Cloudinary URL
      'caretakerName': _caretakerNameController.text.trim(),
      'caretakerAge': _caretakerAgeController.text.trim(),
      'caretakerGender': _caretakerGenderController.text.trim(),
      'caretakerRelation': _caretakerRelationController.text.trim(),
      'caretakerPhone': _caretakerPhoneController.text.trim(),
      'caretakerAddress': _caretakerAddressController.text.trim(),
      'emergencyPhone': _emergencyPhoneController.text.trim(),
      'doctorName': _doctorNameController.text.trim(),
      'doctorPhone': _doctorPhoneController.text.trim(),
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      print("Saving user info to Firestore with data: $data");
      await FirebaseFirestore.instance.collection('user_info')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      print("User info saved successfully.");
      if (mounted) {
        setState(() {
          _pickedImage = null;
          _pickedImageBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกข้อมูลสำเร็จ')));
      }

    } catch (e) {
      print("Error saving user info: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึกข้อมูล: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- แสดง Dialog แก้ไขข้อมูล ---
  void _showEditDialog() {
    String? currentDialogGender = _genderController.text.isNotEmpty && ['ชาย', 'หญิง', 'อื่นๆ'].contains(_genderController.text)
        ? _genderController.text : null;
    TextEditingController currentDialogOtherGenderController = TextEditingController(
        text: (_genderController.text.isNotEmpty && !['ชาย', 'หญิง'].contains(_genderController.text))
            ? _genderController.text : ''
    );
    String? currentDialogSeverity = ['ระยะแรก', 'ระยะสอง', 'ระยะสาม'].contains(_severityController.text)
        ? _severityController.text : null;

    final tempUsernameController = TextEditingController(text: _usernameController.text);
    final tempAgeController = TextEditingController(text: _ageController.text);
    final tempAllergiesController = TextEditingController(text: _allergiesController.text);
    final tempCaretakerNameController = TextEditingController(text: _caretakerNameController.text);
    final tempCaretakerAgeController = TextEditingController(text: _caretakerAgeController.text);
    final tempCaretakerGenderController = TextEditingController(text: _caretakerGenderController.text);
    final tempCaretakerRelationController = TextEditingController(text: _caretakerRelationController.text);
    final tempCaretakerPhoneController = TextEditingController(text: _caretakerPhoneController.text);
    final tempCaretakerAddressController = TextEditingController(text: _caretakerAddressController.text);
    final tempEmergencyPhoneController = TextEditingController(text: _emergencyPhoneController.text);
    final tempDoctorNameController = TextEditingController(text: _doctorNameController.text);
    final tempDoctorPhoneController = TextEditingController(text: _doctorPhoneController.text);

    File? tempPickedImageDialog = _pickedImage;
    Uint8List? tempPickedImageBytesDialog = _pickedImageBytes;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {

            void updateDialogImagePreview() {
              setDialogState(() {
                tempPickedImageDialog = _pickedImage;
                tempPickedImageBytesDialog = _pickedImageBytes;
              });
            }

            ImageProvider? buildDialogBackgroundImage() {
              if (tempPickedImageDialog != null) {
                return FileImage(tempPickedImageDialog!);
              } else if (tempPickedImageBytesDialog != null) {
                return MemoryImage(tempPickedImageBytesDialog!);
              } else if (_imageUrl != null) {
                return NetworkImage(_imageUrl!);
              } else {
                return null;
              }
            }

            Widget? buildDialogAvatarChild() {
              if (tempPickedImageDialog == null && tempPickedImageBytesDialog == null && _imageUrl == null) {
                return Icon(Icons.camera_alt, size: 50, color: Colors.grey[600]);
              } else {
                return null;
              }
            }

            final ImageProvider? dialogBackgroundImage = buildDialogBackgroundImage();

            return AlertDialog(
              title: Text('แก้ไขข้อมูลผู้ใช้'),
              content: SingleChildScrollView(
                child: AbsorbPointer(
                  absorbing: _isLoading,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading) Center(child: Padding( padding: const EdgeInsets.all(8.0), child: CircularProgressIndicator(),)),
                      GestureDetector(
                        onTap: _isLoading ? null : () async {
                          await _pickAndUploadImage();
                          if (mounted) updateDialogImagePreview();
                        },
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: dialogBackgroundImage,
                          // --- แก้ไข Assertion Error ---
                          // กำหนด onBackgroundImageError เฉพาะเมื่อ dialogBackgroundImage ไม่ใช่ null
                          onBackgroundImageError: dialogBackgroundImage != null
                              ? (exception, stackTrace) {
                            print("Error loading image in dialog: $exception");
                            if (mounted && _imageUrl != null) {
                              // อาจจะลองเคลียร์ imageUrl ใน state หลัก ถ้า NetworkImage โหลดไม่ได้
                              setState(() => _imageUrl = null);
                              setDialogState((){}); // อัปเดต UI Dialog
                            }
                          }
                              : null, // ถ้า dialogBackgroundImage เป็น null ให้ onBackgroundImageError เป็น null
                          // --- จบการแก้ไข ---
                          child: buildDialogAvatarChild(),
                        ),
                      ),
                      SizedBox(height: 20),
                      _buildDialogTextField(tempUsernameController, 'ชื่อผู้ป่วย'),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempAgeController, 'อายุ', inputType: TextInputType.number),
                      SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: currentDialogGender,
                        onChanged: (value) => setDialogState(() => currentDialogGender = value),
                        items: ['ชาย', 'หญิง', 'อื่นๆ'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                        decoration: _inputDecoration('เพศ'),
                        hint: Text('เลือกเพศ'),
                      ),
                      if (currentDialogGender == 'อื่นๆ') ...[
                        SizedBox(height: 10),
                        _buildDialogTextField(currentDialogOtherGenderController, 'ระบุเพศ', isOptional: true),
                      ],
                      SizedBox(height: 10),
                      _buildDialogTextField(tempAllergiesController, 'ยาที่แพ้', isOptional: true),
                      SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: currentDialogSeverity,
                        hint: Text('เลือกระดับความรุนแรง'),
                        onChanged: (value) => setDialogState(() => currentDialogSeverity = value),
                        items: ['ระยะแรก', 'ระยะสอง', 'ระยะสาม'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        decoration: _inputDecoration('ระดับความรุนแรง'),
                      ),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempCaretakerNameController, 'ชื่อผู้ดูแล', isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempCaretakerAgeController, 'อายุผู้ดูแล', inputType: TextInputType.number, isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempCaretakerRelationController, 'ความสัมพันธ์', isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempCaretakerPhoneController, 'เบอร์โทรผู้ดูแล', inputType: TextInputType.phone, isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempCaretakerAddressController, 'ที่อยู่ผู้ดูแล', isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempEmergencyPhoneController, 'เบอร์โทรฉุกเฉิน', inputType: TextInputType.phone, isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempDoctorNameController, 'ชื่อแพทย์', isOptional: true),
                      SizedBox(height: 10),
                      _buildDialogTextField(tempDoctorPhoneController, 'เบอร์โทรแพทย์', inputType: TextInputType.phone, isOptional: true),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : () async {
                    if(!mounted) return;

                    _usernameController.text = tempUsernameController.text;
                    _ageController.text = tempAgeController.text;
                    if (currentDialogGender == 'อื่นๆ') {
                      _genderController.text = currentDialogOtherGenderController.text.trim();
                    } else {
                      _genderController.text = currentDialogGender ?? '';
                    }
                    _allergiesController.text = tempAllergiesController.text;
                    _severityController.text = currentDialogSeverity ?? '';
                    _caretakerNameController.text = tempCaretakerNameController.text;
                    _caretakerAgeController.text = tempCaretakerAgeController.text;
                    _caretakerGenderController.text = tempCaretakerGenderController.text;
                    _caretakerRelationController.text = tempCaretakerRelationController.text;
                    _caretakerPhoneController.text = tempCaretakerPhoneController.text;
                    _caretakerAddressController.text = tempCaretakerAddressController.text;
                    _emergencyPhoneController.text = tempEmergencyPhoneController.text;
                    _doctorNameController.text = tempDoctorNameController.text;
                    _doctorPhoneController.text = tempDoctorPhoneController.text;

                    await _saveUserInfo();

                    if (mounted) Navigator.of(context).pop();
                  },
                  child: Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tempUsernameController.dispose();
        tempAgeController.dispose();
        currentDialogOtherGenderController.dispose();
        tempAllergiesController.dispose();
        tempCaretakerNameController.dispose();
        tempCaretakerAgeController.dispose();
        tempCaretakerGenderController.dispose();
        tempCaretakerRelationController.dispose();
        tempCaretakerPhoneController.dispose();
        tempCaretakerAddressController.dispose();
        tempEmergencyPhoneController.dispose();
        tempDoctorNameController.dispose();
        tempDoctorPhoneController.dispose();
      });
    });
  }

  // --- Helper สำหรับสร้าง TextField ใน Dialog ---
  Widget _buildDialogTextField(TextEditingController controller, String label,
      {TextInputType inputType = TextInputType.text, bool isOptional = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      decoration: _inputDecoration(label + (isOptional ? ' (ถ้ามี)' : '')),
      validator: (value) {
        if (!isOptional && (value == null || value.trim().isEmpty)) {
          return 'กรุณากรอกข้อมูล';
        }
        return null;
      },
    );
  }

  // --- Helper สำหรับสร้าง Input Decoration ---
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    );
  }

  // --- Helper สำหรับสร้าง Text Field แบบ ReadOnly ---
  Widget _buildReadOnlyTextField(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
      margin: const EdgeInsets.only(bottom: 10.0),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.black54, fontSize: 12)),
            SizedBox(height: 2),
            Text(value.isNotEmpty ? value : '-', style: TextStyle(color: Colors.black87, fontSize: 15)),
          ]
      ),
    );
  }

  // --- Helper สำหรับสร้าง Title ของแต่ละ Section ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15.0, bottom: 5.0),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  // --- Build Method หลักของหน้า ---
  @override
  Widget build(BuildContext context) {
    ImageProvider? buildMainBackgroundImage() {
      if (_pickedImage != null) {
        return FileImage(_pickedImage!);
      } else if (_pickedImageBytes != null) {
        return MemoryImage(_pickedImageBytes!);
      } else if (_imageUrl != null) {
        return NetworkImage(_imageUrl!);
      } else {
        return null;
      }
    }

    Widget? buildMainAvatarChild() {
      if (_pickedImage == null && _pickedImageBytes == null && _imageUrl == null) {
        return Icon(Icons.person, size: 60, color: Colors.grey[600]);
      } else {
        return null;
      }
    }

    final ImageProvider? mainBackgroundImage = buildMainBackgroundImage();

    return Scaffold(
      appBar: AppBar(
        title: Text('ข้อมูลผู้ใช้'),
        actions: [
          IconButton(
            icon: Icon(Icons.edit),
            tooltip: 'แก้ไขข้อมูล',
            onPressed: _isLoading ? null : _showEditDialog,
          )
        ],
      ),
      body: _isLoading && _imageUrl == null && _usernameController.text.isEmpty
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _fetchUserInfo,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _isLoading ? null : _showEditDialog,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: mainBackgroundImage,
                  // --- แก้ไข Assertion Error ---
                  // กำหนด onBackgroundImageError เฉพาะเมื่อ mainBackgroundImage ไม่ใช่ null
                  onBackgroundImageError: mainBackgroundImage != null
                      ? (exception, stackTrace) {
                    print("Error loading main image: $exception");
                    if(mounted && _imageUrl != null) {
                      setState(() => _imageUrl = null); // เคลียร์ URL ถ้าโหลดไม่ได้
                    }
                  }
                      : null, // ถ้า mainBackgroundImage เป็น null ให้ onBackgroundImageError เป็น null
                  // --- จบการแก้ไข ---
                  child: buildMainAvatarChild(),
                ),
              ),
              SizedBox(height: 20),
              _buildReadOnlyTextField('รหัสผู้ใช้', _userIDController.text),
              _buildReadOnlyTextField('ชื่อผู้ป่วย', _usernameController.text),
              _buildReadOnlyTextField('อายุ', _ageController.text),
              _buildReadOnlyTextField('เพศ', _genderController.text),
              _buildReadOnlyTextField('ยาที่แพ้', _allergiesController.text),
              _buildReadOnlyTextField('ระดับความรุนแรง', _severityController.text),

              _buildSectionTitle("ข้อมูลผู้ดูแล"),
              _buildReadOnlyTextField('ชื่อ', _caretakerNameController.text),
              _buildReadOnlyTextField('อายุ', _caretakerAgeController.text),
              _buildReadOnlyTextField('ความสัมพันธ์', _caretakerRelationController.text),
              _buildReadOnlyTextField('เบอร์โทร', _caretakerPhoneController.text),
              _buildReadOnlyTextField('ที่อยู่', _caretakerAddressController.text),

              _buildSectionTitle("ข้อมูลติดต่อฉุกเฉินและแพทย์"),
              _buildReadOnlyTextField('เบอร์โทรฉุกเฉิน', _emergencyPhoneController.text),
              _buildReadOnlyTextField('ชื่อแพทย์', _doctorNameController.text),
              _buildReadOnlyTextField('เบอร์โทรแพทย์', _doctorPhoneController.text),

              SizedBox(height: 30),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}