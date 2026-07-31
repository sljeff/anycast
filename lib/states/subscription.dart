import 'package:anycast/models/helper.dart';
import 'package:anycast/models/subscription.dart';
import 'package:get/get.dart';

abstract interface class SubscriptionStore {
  Future<List<SubscriptionModel>> listAll();

  Future<void> addMany(List<SubscriptionModel> subscriptions);

  Future<void> remove(SubscriptionModel subscription);
}

class _DatabaseSubscriptionStore implements SubscriptionStore {
  _DatabaseSubscriptionStore(this._helper);

  final DatabaseHelper _helper;

  @override
  Future<List<SubscriptionModel>> listAll() async {
    final db = await _helper.db;
    return SubscriptionModel.listAll(db);
  }

  @override
  Future<void> addMany(List<SubscriptionModel> subscriptions) async {
    final db = await _helper.db;
    await SubscriptionModel.addMany(db, subscriptions);
  }

  @override
  Future<void> remove(SubscriptionModel subscription) async {
    final db = await _helper.db;
    await SubscriptionModel.remove(db, subscription);
  }
}

class SubscriptionController extends GetxController {
  SubscriptionController({SubscriptionStore? store})
      : _store = store ?? _DatabaseSubscriptionStore(DatabaseHelper());

  final subscriptions = <SubscriptionModel>[].obs;
  final isLoading = true.obs;
  final loadError = RxnString();

  final SubscriptionStore _store;

  // Kept public for compatibility with existing callers. The default store
  // uses the same singleton DatabaseHelper instance.
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
      subscriptions.value = await _store.listAll();
    } catch (_) {
      loadError.value = 'Unable to load subscriptions.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addMany(List<SubscriptionModel> subscriptions) async {
    await _store.addMany(subscriptions);
    await load();
  }

  Future<void> remove(SubscriptionModel subscription) async {
    final index = subscriptions
        .indexWhere((element) => element.title == subscription.title);
    if (index != -1) {
      subscriptions.removeAt(index);
    }
    await _store.remove(subscription);
  }

  bool exists(SubscriptionModel m) {
    // rssFeedUrl or title or id exists
    for (var s in subscriptions) {
      if ((m.rssFeedUrl != null && s.rssFeedUrl == m.rssFeedUrl) ||
          (m.title != null && s.title == m.title) ||
          (m.id != null && s.id == m.id)) {
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
