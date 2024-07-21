import 'package:anycast/states/user.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:iconify_flutter/icons/ri.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class LoginPage extends GetView<AuthController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DismissiblePage(
      backgroundColor: const Color(0xFF111316),
      isFullScreen: false,
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: Column(
        children: [
          const Handler(),
          Obx(() {
            if (controller.user.value == null) {
              return Container(
                width: 300,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Image.asset(
                      'assets/icon/icon.png',
                      width: 100,
                      height: 100,
                    ),
                    const SizedBox(height: 50),
                    // Google Sign In Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Iconify(Ic.round_apple),
                          SizedBox(width: 10),
                          Text('Sign in with Apple'),
                        ],
                      ),
                      onPressed: () => controller.signInWithApple(),
                    ),
                    const SizedBox(height: 20),
                    // Apple Sign In Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Iconify(Ri.google_fill),
                          SizedBox(width: 10),
                          Text('Sign in with Google'),
                        ],
                      ),
                      onPressed: () => controller.signInWithGoogle(),
                    ),
                  ],
                ),
              );
            }

            return SizedBox(
              height: Get.height - 100,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildUserInfo(),
                  const SizedBox(height: 20),
                  _buildSubscriptionInfo(),
                  const SizedBox(height: 20),
                  _buildPaywall(context),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUserInfo() {
    var icon = Ic.round_apple;
    if (controller.user.value!.providerData[0].providerId == 'google.com') {
      icon = Ri.google_fill;
    }

    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "User Info",
              style: GoogleFonts.comfortaa(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.grey[800],
                  child: Iconify(icon, color: Colors.white70),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    controller.user.value!.email ?? 'No email',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                  ),
                ),
                PopupMenuButton(
                    color: Colors.black.withOpacity(0.9),
                    shadowColor: Colors.black87,
                    iconColor: Colors.white70,
                    itemBuilder: (context) {
                      return [
                        PopupMenuItem(
                          onTap: () {
                            Clipboard.setData(ClipboardData(
                              text: controller.user.value!.email ?? '',
                            ));
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Iconify(
                                Ic.content_copy,
                                size: 16,
                                color: Colors.white,
                              ),
                              Text(
                                'Copy email',
                                style: GoogleFonts.roboto(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          onTap: () {
                            // controller.signOut();
                            Get.dialog(
                              AlertDialog(
                                title: Text(
                                  'Sign out',
                                  style: GoogleFonts.roboto(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: Text(
                                  'Are you sure you want to sign out?',
                                  style: GoogleFonts.roboto(
                                    color: Colors.red,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'Sign out',
                                      style: GoogleFonts.roboto(
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () {
                                      controller.signOut();
                                      Get.back();
                                    },
                                  ),
                                  TextButton(
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.roboto(
                                        color: Colors.green,
                                      ),
                                    ),
                                    onPressed: () {
                                      Get.back();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(
                                Icons.exit_to_app,
                                size: 16,
                                color: Colors.red.shade900,
                              ),
                              Text(
                                'Sign out',
                                style: GoogleFonts.roboto(
                                  fontSize: 12,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionInfo() {
    return Obx(() {
      var rcController = Get.find<RevenueCatController>();
      var plan = 'Basic';
      var remainingDays = '0';

      if (rcController.isSubscribed) {
        plan = 'Anycast+ Plus';
        var ent = rcController.customerInfo.entitlements.active['plus'];

        if (ent != null) {
          remainingDays = ent.expirationDate!;
        }
      }

      return Card(
        color: const Color(0xFF1E1E1E),
        child: DefaultTextStyle(
          style: GoogleFonts.comfortaa(
            color: Colors.white,
            fontSize: 14,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Your plan: '),
                    Text(plan,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Remaining Days: $remainingDays'),
                const SizedBox(height: 8),
                Text('Remaining Transcriptions: 0'),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPaywall(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: DefaultTextStyle(
          style: GoogleFonts.comfortaa(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Anycast+ Plus'),
              const SizedBox(height: 15),
              Container(
                height: 150,
                color: Colors.grey[800],
                alignment: Alignment.center,
                child: const Text('[功能展示轮播图]',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 15),
              FutureBuilder(
                future: Purchases.getOfferings(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var offerings = snapshot.data;
                  var currentOffering = offerings!.current;
                  var availablePlans = currentOffering!.availablePackages;
                  List<Widget> planCards = [];
                  for (var plan in availablePlans) {
                    planCards.add(
                      Expanded(child: _buildPlanCard(plan)),
                    );
                  }

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: planCards,
                      ),
                      const SizedBox(height: 15),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightGreenAccent,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: () {
                          var rcController = Get.find<RevenueCatController>();
                          Package? plan;

                          for (var p in availablePlans) {
                            if (p.storeProduct.identifier ==
                                rcController.choosenPlan.value) {
                              plan = p;
                              break;
                            }
                          }

                          if (plan == null) {
                            Get.dialog(
                              AlertDialog(
                                title: Text('Error',
                                    style: GoogleFonts.comfortaa(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold)),
                                content: Text(
                                  'Invalid plan',
                                  style: GoogleFonts.comfortaa(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                            return;
                          }
                          rcController.purchasePackage(plan);
                        },
                        child: Text('Confirm purchase',
                            style: GoogleFonts.comfortaa(
                                color: Colors.black,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'restore purchases',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(Package plan) {
    var title = 'Monthly';
    var per = 'Month';

    if (plan.packageType == PackageType.annual) {
      title = 'Yearly';
      per = 'Year';
    }

    return Obx(
      () {
        var rcController = Get.find<RevenueCatController>();
        var choosenPlan = rcController.choosenPlan.value;
        var background = Colors.grey[800];

        if (choosenPlan == plan.storeProduct.identifier) {
          background = Colors.greenAccent[700];
        }

        return GestureDetector(
          onTap: () {
            rcController.choosenPlan.value = plan.storeProduct.identifier;
          },
          child: Card(
            color: background,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: DefaultTextStyle(
                style: GoogleFonts.comfortaa(
                  color: Colors.white,
                  fontSize: 12,
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.comfortaa(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${plan.storeProduct.priceString}/$per',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
