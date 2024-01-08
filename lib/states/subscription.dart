import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:get/get.dart';

class SubscriptionController extends GetxController {
  final subscriptions = <SubscriptionModel>[].obs;

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    helper.db.then((db) => {
          SubscriptionModel.listAll(db!).then((subscriptions) {
            this.subscriptions.value = subscriptions;
          })
        });
  }

  void addMany(subscriptions) {
    helper.db.then((db) => {
          SubscriptionModel.addMany(db!, subscriptions).then((_) {
            load();
          })
        });
  }
}
