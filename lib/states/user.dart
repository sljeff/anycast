import 'dart:io';

import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Rx<User?> user = Rx<User?>(null);

  @override
  void onInit() {
    super.onInit();
    // user.bindStream(_auth.authStateChanges());
    _auth.authStateChanges().listen((User? user) {
      this.user.value = user;
      if (user != null) {
        loginToRevenueCat();
      }
    });
  }

  Future<String?> getToken() async {
    if (user.value == null) {
      return null;
    }

    var token = await user.value!.getIdToken();
    return token;
  }

  Future<void> loginToRevenueCat() async {
    try {
      await Purchases.logIn(user.value!.uid);
    } catch (e) {
      print('Error logging in to RevenueCat: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
    } catch (e) {
      print('Error signing in with Google: $e');
    }
  }

  Future<void> signInWithApple() async {
    try {
      AppleAuthProvider appleProvider = AppleAuthProvider();
      appleProvider = appleProvider.addScope('email');
      appleProvider = appleProvider.addScope('name');
      await FirebaseAuth.instance.signInWithProvider(appleProvider);
    } catch (e) {
      print('Error signing in with Apple: $e');
    }
  }

  Future<void> signOut() async {
    Get.find<RevenueCatController>().signOut();
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}

class RevenueCatController extends GetxController {
  final RxBool _isSubscribed = false.obs;
  late final Rx<CustomerInfo> _customerInfo;

  var choosenPlan = 'anycast_monthly'.obs;

  bool get isSubscribed => _isSubscribed.value;
  CustomerInfo get customerInfo => _customerInfo.value;

  @override
  void onInit() {
    super.onInit();
    initPlatformState();

    if (Platform.isAndroid) {
      choosenPlan.value = 'anycast_plus:monthly';
    }
  }

  Future<void> initPlatformState() async {
    var configuration =
        PurchasesConfiguration('IOS_KEY');
    if (Platform.isAndroid) {
      configuration =
          PurchasesConfiguration('ANDROID_KEY');
    }
    var user = Get.find<AuthController>().user.value;
    if (user?.uid != null) {
      configuration.appUserID = user?.uid;
    }
    await Purchases.configure(configuration);
    await Purchases.setLogLevel(LogLevel.debug);

    CustomerInfo customerInfo = await Purchases.getCustomerInfo();
    _customerInfo = customerInfo.obs;
    _updateCustomerInfo(customerInfo);

    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      _updateCustomerInfo(customerInfo);
    });
  }

  Future<void> purchasePackage(Package package) async {
    try {
      CustomerInfo customerInfo = await Purchases.purchasePackage(package);
      _updateCustomerInfo(customerInfo);
    } catch (e) {
      print('Error purchasing package: $e');
    }
  }

  Future<bool> restorePurchases() async {
    try {
      var info = await Purchases.restorePurchases();
      if (info.entitlements.active.isEmpty) {
        return false;
      }
      _updateCustomerInfo(info);
    } catch (e) {
      print('Error restoring purchases: $e');
      return false;
    }

    return true;
  }

  void _updateCustomerInfo(CustomerInfo customerInfo) {
    _customerInfo.value = customerInfo;
    _isSubscribed.value = customerInfo.entitlements.active.isNotEmpty;
  }

  void signOut() {
    Purchases.logOut();
    _isSubscribed.value = false;
  }

  @override
  void onClose() {
    // 移除监听器
    Purchases.removeCustomerInfoUpdateListener(_updateCustomerInfo);
    super.onClose();
  }
}
