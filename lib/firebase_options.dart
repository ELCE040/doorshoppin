// Same Firebase project as DoorShoppin (admin_orders topic). Run 'flutterfire configure' to add a separate app if needed.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('DefaultFirebaseOptions have not been configured for web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA-Nj1jnAXOUldaL_WtOr-i9dvJhd4SeUM',
    appId: '1:589803206897:android:7dc29ad454b67fbe2e1150',
    messagingSenderId: '589803206897',
    projectId: 'doorshoppin-7f073',
    storageBucket: 'doorshoppin-7f073.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCJxIvlhmt4r_YE-mvi6oGLSIrZVi0R1tc',
    appId: '1:589803206897:ios:ecf6c733ce0b1a862e1150',
    messagingSenderId: '589803206897',
    projectId: 'doorshoppin-7f073',
    storageBucket: 'doorshoppin-7f073.firebasestorage.app',
    iosBundleId: 'com.example.doorshoppin',
  );
}
