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
          SubscriptionModel.listAll(db).then((subscriptions) {
            this.subscriptions.value = subscriptions;
          })
        });
  }

  void addMany(subscriptions) {
    helper.db.then((db) => {
          SubscriptionModel.addMany(db, subscriptions).then((_) {
            load();
          })
        });
  }

  void remove(SubscriptionModel subscription) {
    var index = subscriptions
        .indexWhere((element) => element.title == subscription.title);
    subscriptions.removeAt(index);
    helper.db.then((db) {
      SubscriptionModel.remove(db, subscription);
    });
  }

  bool exists(SubscriptionModel m) {
    // rssFeedUrl or title or id exists
    for (var s in subscriptions) {
      if (s.rssFeedUrl == m.rssFeedUrl || s.title == m.title || s.id == m.id) {
        return true;
      }
    }
    return false;
  }

  SubscriptionModel? getByTitle(String title) {
    for (var s in subscriptions) {
      if (s.title == title) {
        return s;
      }
    }
    return null;
  }
}
