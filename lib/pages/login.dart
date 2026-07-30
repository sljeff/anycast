import 'package:anycast/api/user.dart';
import 'package:anycast/states/user.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:anycast/widgets/privacy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
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
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
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
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 50),
                        // Google Sign In Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.inverseSurface,
                            foregroundColor: theme.colorScheme.onInverseSurface,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
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
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHigh,
                            foregroundColor: theme.colorScheme.onSurface,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
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
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHigh,
                            foregroundColor: theme.colorScheme.onSurface,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Iconify(Ic.email, size: 16),
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
                    _buildUserInfo(context),
                    const SizedBox(height: 20),
                    _buildSubscriptionInfo(context),
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

  Widget _buildUserInfo(BuildContext context) {
    var icon = Ic.round_apple;
    if (controller.user.value!.providerData[0].providerId == 'google.com') {
      icon = Ri.google_fill;
    } else if (controller.user.value!.providerData[0].providerId ==
        'password') {
      icon = Ic.email;
    }

    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "User Info",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  child: Iconify(
                    icon,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    controller.user.value!.email ?? 'No email',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                  ),
                ),
                PopupMenuButton(
                    color: theme.colorScheme.surface,
                    shadowColor: theme.colorScheme.shadow,
                    iconColor: theme.colorScheme.onSurfaceVariant,
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
                              Iconify(
                                Ic.content_copy,
                                size: 16,
                                color: theme.colorScheme.onSurface,
                              ),
                              Text(
                                'Copy email',
                                style: theme.textTheme.labelMedium,
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
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: Text(
                                  'Are you sure you want to sign out?',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    child: Text(
                                      'Sign out',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color: theme.colorScheme.error,
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
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        color: theme.colorScheme.primary,
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
                                color: theme.colorScheme.error,
                              ),
                              Text(
                                'Sign out',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.error,
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

  Widget _buildSubscriptionInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      var rcController = Get.find<RevenueCatController>();

      var remainingText = FutureBuilder(
        future: getUser(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Text('...');
          }
          var user = snapshot.data!;
          var right = ' Transcriptions left';
          if (user.plus == 1) {
            right = ' Transcriptions left (this month)';
          }

          return Row(
            children: [
              Text('${user.remaining}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
              Text(
                right,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          );
        },
      );

      if (!rcController.isSubscribed) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Basic Plan',
                  style: theme.textTheme.titleMedium?.copyWith(
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
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Anycast Plus',
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
    var slideController = CarouselSliderController();
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(
            fontWeight: FontWeight.bold,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Anycast Plus Plan'),
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
                      Expanded(child: _buildPlanCard(context, plan)),
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
                                title: Text(
                                  'Error',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                content: Text(
                                  'Invalid plan',
                                  style: theme.textTheme.bodyMedium,
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
                        child: const Text('Confirm purchase'),
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
                        title: Text(
                          'Error',
                          style: theme.textTheme.headlineSmall,
                        ),
                        content: Text(
                          'No active entitlements',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    );
                    return;
                  }

                  Get.dialog(
                    AlertDialog(
                      title: Text(
                        'Success',
                        style: theme.textTheme.headlineSmall,
                      ),
                      content: Text(
                        'Restored purchases',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                },
                child: Center(
                  child: Text(
                    'restore purchases',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, Package plan) {
    var title = 'Monthly';
    var per = 'Month';

    if (plan.packageType == PackageType.annual) {
      title = 'Yearly';
      per = 'Year';
    }

    return Obx(
      () {
        final theme = Theme.of(context);
        var rcController = Get.find<RevenueCatController>();
        var choosenPlan = rcController.choosenPlan.value;
        final choosen = choosenPlan == plan.storeProduct.identifier;
        var background = theme.colorScheme.surfaceContainerHigh;

        if (choosen) {
          background = theme.colorScheme.primaryContainer;
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
                    style: theme.textTheme.labelMedium!.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
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
              style: theme.textTheme.labelSmall?.copyWith(
                color: choosen
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
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
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          iconColor: theme.colorScheme.onSurface,
          title: Text(
            "Anycast Plus ($name)",
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          childrenPadding: const EdgeInsets.only(left: 12, bottom: 12),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                DefaultTextStyle(
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    return Center(
      child: GestureDetector(
        onTap: () {
          Get.dialog(
            AlertDialog(
              title: Text("Permanently Delete Your Account?",
                  style: theme.textTheme.headlineSmall),
              content: Text(
                "Warning: This action will permanently delete your account and all associated data. Once deleted, your account cannot be recovered. Are you sure you want to proceed?",
                style: theme.textTheme.bodyMedium,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back();
                  },
                  child: const Text("Cancel"),
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
                  child: Text(
                    "Confirm",
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.error.withValues(alpha: .10),
          ),
          child: Text(
            "Permanently Delete Account",
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.error,
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
    final theme = Theme.of(context);
    return Column(
      children: [
        TextField(
          style: theme.textTheme.bodyLarge,
          controller: emailController,
          decoration: const InputDecoration(hintText: "Email"),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        TextField(
          style: theme.textTheme.bodyLarge,
          controller: passwordController,
          decoration: const InputDecoration(hintText: "Password"),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
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
            // setLogin(false);
            Get.dialog(
              AlertDialog(
                title: Text(
                  "Sorry!",
                  style: theme.textTheme.headlineSmall,
                ),
                content: Text(
                  "Please sign in with Apple or Google.\n\n"
                  "We don't support email registration yet.",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          },
          child: const Text("Don't have an account? Register"),
        ),
      ],
    );
  }

  Widget registerWidget() {
    final theme = Theme.of(context);
    return Column(
      children: [
        TextField(
          style: theme.textTheme.bodyLarge,
          controller: emailController,
          decoration: const InputDecoration(hintText: "Email"),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        TextField(
          style: theme.textTheme.bodyLarge,
          controller: passwordController,
          decoration: const InputDecoration(hintText: "Password"),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        TextField(
          style: theme.textTheme.bodyLarge,
          controller: passwordConfirmController,
          decoration: const InputDecoration(hintText: "Confirm Password"),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            if (passwordController.text != passwordConfirmController.text) {
              Get.snackbar("Error", "Passwords don't match");
              return;
            }

            // Get.find<AuthController>().registerWithEmail(
            //   emailController.text,
            //   passwordController.text,
            // );
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
