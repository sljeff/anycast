import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class UserController extends GetxController {
  @override
  void onInit() {
    super.onInit();

    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        print('User is currently signed out!');
      } else {
        print(user);
        print('User is signed in!');
        print(user.providerData[0].providerId);
        if (user.providerData[0].providerId == 'apple.com') {
          print('User is signed in with Apple');
        } else if (user.providerData[0].providerId == 'google.com') {
          print('User is signed in with Google');
        }
      }
    });
  }
}
