import 'package:flutter/foundation.dart';
import 'package:anycast/models/subscription.dart';

class SubscriptionProvider extends ChangeNotifier {
  List<SubscriptionModel> _subscriptions = [];

  List<SubscriptionModel> get subscriptions => _subscriptions;

  void addMany(List<SubscriptionModel> subscriptions) {
    _subscriptions.addAll(subscriptions);
    // sort by title
    _subscriptions.sort((a, b) => a.title!.compareTo(b.title!));
    notifyListeners();
  }

  void removeByRssFeedUrls(List<String> rssFeedUrls) {
    _subscriptions.removeWhere(
        (subscription) => rssFeedUrls.contains(subscription.rssFeedUrl));
    notifyListeners();
  }

  void load(List<SubscriptionModel> subscriptions) {
    _subscriptions = subscriptions;
    notifyListeners();
  }

  void addManyAndRemoveDuplicates(List<SubscriptionModel> subscriptions) {
    for (SubscriptionModel subscription in subscriptions) {
      if (!_subscriptions.contains(subscription)) {
        _subscriptions.add(subscription);
      }
    }
    notifyListeners();
  }
}
