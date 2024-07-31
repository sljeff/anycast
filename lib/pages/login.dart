import 'package:anycast/api/user.dart';
import 'package:anycast/states/user.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/privacy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:iconify_flutter/icons/ri.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:jiffy/jiffy.dart';
import 'package:carousel_slider/carousel_slider.dart';

class LoginPage extends GetView<AuthController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111316),
      child: SafeArea(
        child: Column(
          children: [
            const Handler(),
            Obx(() {
              if (controller.user.value == null) {
                return Expanded(
                  child: Container(
                    width: 300,
                    alignment: Alignment.center,
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
                        Text(
                          "Sign up now \n\n&\n\nGet 3 free audio transcriptions!",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.comfortaa(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
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
                          onPressed: () async {
                            Get.dialog(
                              const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                            await controller.signInWithApple();
                            Get.back();
                          },
                        ),
                        const SizedBox(height: 10),
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
                          onPressed: () async {
                            Get.dialog(
                              const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                            await controller.signInWithGoogle();
                            Get.back();
                          },
                        ),
                        const SizedBox(height: 10),
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
                              Iconify(Ic.email),
                              SizedBox(width: 10),
                              Text('Sign in with Email'),
                            ],
                          ),
                          onPressed: () async {
                            showMaterialModalBottomSheet(
                                context: context,
                                builder: (context) {
                                  return const EmailLogin();
                                });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildUserInfo(),
                    const SizedBox(height: 20),
                    _buildSubscriptionInfo(),
                    const SizedBox(height: 20),
                    _buildPaywall(context),
                    const SizedBox(height: 30),
                    const Privacy(),
                    const SizedBox(height: 30),
                    const RemoveAccount(),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    var icon = Ic.round_apple;
    if (controller.user.value!.providerData[0].providerId == 'google.com') {
      icon = Ri.google_fill;
    } else if (controller.user.value!.providerData[0].providerId ==
        'password') {
      icon = Ic.email;
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

      var remainingText = FutureBuilder(
        future: getUser(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Text('...');
          }
          var user = snapshot.data!;
          var total = 3;
          var right = ' Transcriptions left';
          if (user.plus == 1) {
            total = 50;
            right = ' Transcriptions left (this month)';
          }

          return Row(
            children: [
              Text('${user.remaining}/$total',
                  style: TextStyle(
                    color: Colors.green.shade200,
                    fontWeight: FontWeight.bold,
                  )),
              Text(
                right,
                style: GoogleFonts.comfortaa(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          );
        },
      );

      if (!rcController.isSubscribed) {
        return Card(
          color: const Color(0xFF1E1E1E),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Basic Plan',
                  style: GoogleFonts.comfortaa(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                remainingText,
              ],
            ),
          ),
        );
      }

      var expirationStrUTC = '';
      var ent = rcController.customerInfo.entitlements.active['plus'];

      if (ent != null) {
        expirationStrUTC = ent.expirationDate!;
      }

      var expiration =
          Jiffy.parse(expirationStrUTC, isUtc: true).toLocal().format(
                pattern: 'yyyy-MM-dd HH:mm',
              );

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
                const Text('Anycast+ Plus',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Plan expires on $expiration'),
                const SizedBox(height: 8),
                remainingText,
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPaywall(BuildContext context) {
    var slideController = CarouselController();

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
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Anycast+ Plus Plan'),
                  Tooltip(
                    message: 'Auto renewal is on.\n'
                        'But you can easily cancel it at any time\nfrom App Store.',
                    showDuration: Duration(milliseconds: 4000),
                    triggerMode: TooltipTriggerMode.tap,
                    child: Icon(Icons.info_outline, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              CarouselSlider(
                items: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/subscription_intro.png',
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/subscription_intro_2.png',
                    ),
                  ),
                ],
                options: CarouselOptions(
                  aspectRatio: 2 / 1,
                  viewportFraction: 1,
                  autoPlay: true,
                ),
                carouselController: slideController,
              ),
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
                      const PlusIntro(),
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
                        onPressed: () async {
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

                          Get.dialog(const Center(
                            child: CircularProgressIndicator(
                                strokeCap: StrokeCap.round),
                          ));
                          await rcController.purchasePackage(plan);
                          Get.back();
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
              GestureDetector(
                onTap: () async {
                  Get.dialog(const Center(
                    child: SizedBox(
                      height: 50,
                      width: 50,
                      child:
                          CircularProgressIndicator(strokeCap: StrokeCap.round),
                    ),
                  ));
                  var rcController = Get.find<RevenueCatController>();
                  var success = await rcController.restorePurchases();
                  Get.back();

                  if (!success) {
                    Get.dialog(
                      AlertDialog(
                        title: Text('Error',
                            style: GoogleFonts.comfortaa(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        content: Text(
                          'No active entitlements',
                          style: GoogleFonts.comfortaa(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                    return;
                  }

                  Get.dialog(
                    AlertDialog(
                      title: Text('Success',
                          style: GoogleFonts.comfortaa(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      content: Text(
                        'Restored purchases',
                        style: GoogleFonts.comfortaa(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                },
                child: const Center(
                  child: Text(
                    'restore purchases',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
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
        final choosen = choosenPlan == plan.storeProduct.identifier;
        var background = Colors.grey[800];

        if (choosen) {
          background = const Color.fromARGB(255, 56, 121, 58);
        }

        return Column(
          children: [
            GestureDetector(
              onTap: () {
                rcController.choosenPlan.value = plan.storeProduct.identifier;
              },
              child: Card(
                color: background,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 28),
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
            ),
            const SizedBox(height: 5),
            Text(
              'Auto Renewal\n${plan.storeProduct.priceString}/${per.toLowerCase()}',
              style: GoogleFonts.comfortaa(
                color: choosen ? Colors.green : Colors.white70,
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlusIntro extends StatelessWidget {
  const PlusIntro({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(
      () {
        var rcController = Get.find<RevenueCatController>();
        var choosenPlan = rcController.choosenPlan.value;
        var name = 'Monthly';
        if (choosenPlan.contains('annual')) {
          name = 'Annually';
        }
        return ExpansionTile(
          tilePadding: const EdgeInsets.all(0),
          initiallyExpanded: true,
          collapsedIconColor: Colors.white,
          iconColor: Colors.white,
          title: Text(
            "Anycast+ Plus ($name)",
            style: GoogleFonts.comfortaa(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          childrenPadding: const EdgeInsets.only(left: 12, bottom: 12),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                DefaultTextStyle(
                    style: GoogleFonts.comfortaa(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.4,
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text("- "),
                            Text("50 TIMES",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                )),
                            Text(" AI Transcription every month"),
                          ],
                        ),
                        // 翻译：无限双语字幕翻译
                        Row(
                          children: [
                            Text("- "),
                            Text("Unlimited",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                )),
                            Text(" subtitle translation"),
                          ],
                        ),
                        // 翻译：导出字幕到你的笔记软件
                        Text("- Export subtitle to your note app"),
                      ],
                    )),
              ],
            ),
          ],
        );
      },
    );
  }
}

class RemoveAccount extends StatelessWidget {
  const RemoveAccount({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () {
          Get.dialog(
            AlertDialog(
              title: Text("Permanently Delete Your Account?",
                  style: GoogleFonts.comfortaa(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              content: Text(
                "Warning: This action will permanently delete your account and all associated data. Once deleted, your account cannot be recovered. Are you sure you want to proceed?",
                style: GoogleFonts.comfortaa(color: Colors.white, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back();
                  },
                  child: Text("Cancel",
                      style: GoogleFonts.comfortaa(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                TextButton(
                  onPressed: () async {
                    Get.dialog(
                      const Center(
                        child: SizedBox(
                          height: 50,
                          width: 50,
                          child: CircularProgressIndicator(
                              strokeCap: StrokeCap.round),
                        ),
                      ),
                    );
                    await deleteUser();
                    Get.back();
                    Get.back();
                    Get.find<AuthController>().signOut();
                  },
                  child: Text("Confirm",
                      style: GoogleFonts.comfortaa(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              ],
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white30,
          ),
          child: Text(
            "Permanently Delete Account",
            style: GoogleFonts.comfortaa(
              color: Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class EmailLogin extends StatefulWidget {
  final inputDec = const InputDecoration(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Colors.white, width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Colors.white, width: 2),
    ),
  );

  const EmailLogin({
    super.key,
  });

  @override
  State<EmailLogin> createState() => _EmailLoginState();
}

class _EmailLoginState extends State<EmailLogin> {
  var emailController = TextEditingController();
  var passwordController = TextEditingController();
  var passwordConfirmController = TextEditingController();

  bool login = true;

  void setLogin(bool value) {
    setState(() {
      login = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    var wd = login ? loginWidget() : registerWidget();
    return SafeArea(
      child: Column(
        children: [
          const Handler(),
          const SizedBox(height: 100),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: wd,
            ),
          ),
        ],
      ),
    );
  }

  Widget loginWidget() {
    return Column(
      children: [
        TextField(
          style: const TextStyle(color: Colors.white),
          controller: emailController,
          decoration: widget.inputDec.copyWith(
            hintText: "Email",
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        TextField(
          style: const TextStyle(color: Colors.white),
          controller: passwordController,
          decoration: widget.inputDec.copyWith(
            hintText: "Password",
          ),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
          ),
          onPressed: () {
            Get.find<AuthController>().loginWithEmail(
              emailController.text,
              passwordController.text,
            );
          },
          child: const Text("Login"),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            setLogin(false);
          },
          child: const Text("Don't have an account? Register"),
        ),
      ],
    );
  }

  Widget registerWidget() {
    return Column(
      children: [
        TextField(
          style: const TextStyle(color: Colors.white),
          controller: emailController,
          decoration: widget.inputDec.copyWith(
            hintText: "Email",
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        TextField(
          style: const TextStyle(color: Colors.white),
          controller: passwordController,
          decoration: widget.inputDec.copyWith(
            hintText: "Password",
          ),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        TextField(
          style: const TextStyle(color: Colors.white),
          controller: passwordConfirmController,
          decoration: widget.inputDec.copyWith(
            hintText: "Confirm Password",
          ),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
          ),
          onPressed: () {
            if (passwordController.text != passwordConfirmController.text) {
              Get.snackbar("Error", "Passwords don't match");
              return;
            }

            Get.find<AuthController>().registerWithEmail(
              emailController.text,
              passwordController.text,
            );
          },
          child: const Text("Register"),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            setLogin(true);
          },
          child: const Text("Already have an account? Login"),
        ),
      ],
    );
  }
}
