import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('이 플랫폼은 지원하지 않습니다.');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAwi2lpRsu3SzNcg4D5WGnb9fLWfTpqj5M',
    appId: '1:29901179190:ios:4c92c7f622c39abb07cb97',
    messagingSenderId: '29901179190',
    projectId: 'todays-lck',
    storageBucket: 'todays-lck.firebasestorage.app',
    iosClientId: '29901179190-p0nbq8vopvmp2llf0sspevjk9lub0tbs.apps.googleusercontent.com',
    iosBundleId: 'com.lckapp.lckApp',
  );
}
