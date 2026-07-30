import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:get/get.dart';

class SubscriptionController extends GetxController {
  final subscriptions = <SubscriptionModel>[].obs;
  final isLoading = true.obs;
  final loadError = RxnString();

  final DatabaseHelper helper = DatabaseHelper();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    loadError.value = null;
    try {
      final db = await helper.db;
      subscriptions.value = await SubscriptionModel.listAll(db);
    } catch (_) {
      loadError.value = 'Unable to load subscriptions.';
    } finally {
      isLoading.value = false;
    }
  }

  void addMany(List<SubscriptionModel> subscriptions) {
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
