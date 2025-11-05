// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios; // Safe to keep; you pasted the iOS plist too
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ANDROID — from your google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBqSRFERvB60xti6kfXj3rmrsGLR5ccNy4',
    appId: '1:484492060714:android:8a5da7792a8d5a73d0fb53',
    messagingSenderId: '484492060714',
    projectId: 'tellme-65fdf',
    storageBucket: 'tellme-65fdf.appspot.com',
  );

  // iOS — from your GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAlzb1nAhBayUwHUVWIpamiox7adFGhEec',
    appId: '1:484492060714:ios:6c9ae9fb21f55716d0fb53',
    messagingSenderId: '484492060714',
    projectId: 'tellme-65fdf',
    storageBucket: 'tellme-65fdf.appspot.com',
    iosBundleId: 'com.mstoreapp.tellme',
  );
}
