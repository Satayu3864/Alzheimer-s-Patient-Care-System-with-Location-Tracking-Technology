// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAmKEb4pHyiqQVeuQoG3iWInuRtnP7rfnE',
    appId: '1:608540798688:web:20dff3df1f38a000e2ea85',
    messagingSenderId: '608540798688',
    projectId: 'testcode-project',
    authDomain: 'testcode-project.firebaseapp.com',
    storageBucket: 'testcode-project.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDPHIlE1sO7e7bC7OhbbuCNoTq0GU7I7ys',
    appId: '1:608540798688:android:f52daba27b4f875de2ea85',
    messagingSenderId: '608540798688',
    projectId: 'testcode-project',
    storageBucket: 'testcode-project.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDLSgaDolDTqztJkqxFrDN43RkEWZ_l0Wo',
    appId: '1:608540798688:ios:87ce8bde9e21afc6e2ea85',
    messagingSenderId: '608540798688',
    projectId: 'testcode-project',
    storageBucket: 'testcode-project.firebasestorage.app',
    iosBundleId: 'com.example.testcode',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDLSgaDolDTqztJkqxFrDN43RkEWZ_l0Wo',
    appId: '1:608540798688:ios:87ce8bde9e21afc6e2ea85',
    messagingSenderId: '608540798688',
    projectId: 'testcode-project',
    storageBucket: 'testcode-project.firebasestorage.app',
    iosBundleId: 'com.example.testcode',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAmKEb4pHyiqQVeuQoG3iWInuRtnP7rfnE',
    appId: '1:608540798688:web:0365da1c628b2f81e2ea85',
    messagingSenderId: '608540798688',
    projectId: 'testcode-project',
    authDomain: 'testcode-project.firebaseapp.com',
    storageBucket: 'testcode-project.firebasestorage.app',
  );
}
