import 'dart:async';

import 'package:anycast/models/subscription.dart';
import 'package:anycast/states/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionController', () {
    test('load publishes stored subscriptions and clears loading state',
        () async {
      final pendingLoad = Completer<List<SubscriptionModel>>();
      final store = _FakeSubscriptionStore(onListAll: () => pendingLoad.future);
      final controller = SubscriptionController(store: store);
      controller.loadError.value = 'stale error';

      final load = controller.load();

      expect(controller.isLoading.value, isTrue);
      expect(controller.loadError.value, isNull);

      final stored = [
        _subscription(
          id: 1,
          title: 'Alpha',
          rssFeedUrl: 'https://example.com/alpha.xml',
        ),
        _subscription(
          id: 2,
          title: 'Beta',
          rssFeedUrl: 'https://example.com/beta.xml',
        ),
      ];
      pendingLoad.complete(stored);
      await load;

      expect(controller.subscriptions, orderedEquals(stored));
      expect(controller.isLoading.value, isFalse);
      expect(controller.loadError.value, isNull);
      expect(store.listAllCalls, 1);
    });

    test('load reports a storage failure and always leaves loading state',
        () async {
      final existing = _subscription(id: 1, title: 'Already loaded');
      final store = _FakeSubscriptionStore(
        onListAll: () => Future.error(StateError('database unavailable')),
      );
      final controller = SubscriptionController(store: store)
        ..subscriptions.add(existing);

      await expectLater(controller.load(), completes);

      expect(controller.subscriptions, [same(existing)]);
      expect(controller.loadError.value, 'Unable to load subscriptions.');
      expect(controller.isLoading.value, isFalse);
      expect(store.listAllCalls, 1);
    });

    test('addMany persists the input and reloads the authoritative list',
        () async {
      final existing = _subscription(id: 1, title: 'Existing');
      final added = _subscription(id: 2, title: 'Added');
      final events = <String>[];
      final store = _FakeSubscriptionStore(
        onAddMany: (subscriptions) async {
          events.add('addMany');
          expect(subscriptions, [same(added)]);
        },
        onListAll: () async {
          events.add('listAll');
          return [existing, added];
        },
      );
      final controller = SubscriptionController(store: store)
        ..subscriptions.add(existing);

      await controller.addMany([added]);

      expect(events, ['addMany', 'listAll']);
      expect(store.addManyCalls, 1);
      expect(store.listAllCalls, 1);
      expect(controller.subscriptions, [same(existing), same(added)]);
      expect(controller.isLoading.value, isFalse);
    });

    test('remove updates memory immediately and persists the removal',
        () async {
      final kept = _subscription(id: 1, title: 'Keep');
      final removed = _subscription(
        id: 2,
        title: 'Remove',
        rssFeedUrl: 'https://example.com/remove.xml',
      );
      final persisted = Completer<void>();
      final store = _FakeSubscriptionStore(
        onRemove: (subscription) {
          expect(subscription, same(removed));
          return persisted.future;
        },
      );
      final controller = SubscriptionController(store: store)
        ..subscriptions.addAll([kept, removed]);

      var removalCompleted = false;
      final removal = controller.remove(removed)
        ..then((_) => removalCompleted = true);

      expect(controller.subscriptions, [same(kept)]);
      expect(store.removeCalls, 1);
      expect(removalCompleted, isFalse);

      persisted.complete();
      await removal;

      expect(removalCompleted, isTrue);
    });

    test('remove still persists when the item is already absent', () async {
      final absent = _subscription(id: 7, title: 'Absent');
      final store = _FakeSubscriptionStore();
      final controller = SubscriptionController(store: store)
        ..subscriptions.add(_subscription(id: 1, title: 'Keep'));

      await controller.remove(absent);

      expect(controller.subscriptions.single.title, 'Keep');
      expect(store.removeCalls, 1);
      expect(store.removed.single, same(absent));
    });

    test('exists matches each stable identifier and rejects null collisions',
        () {
      final stored = _subscription(
        id: 42,
        title: 'Stored show',
        rssFeedUrl: 'https://example.com/stored.xml',
      );
      final unsaved = _subscription(
        title: 'Unsaved show',
        rssFeedUrl: 'https://example.com/unsaved.xml',
      );
      final controller = SubscriptionController(store: _FakeSubscriptionStore())
        ..subscriptions.addAll([stored, unsaved]);

      expect(controller.exists(_subscription(id: 42, title: 'Other')), isTrue);
      expect(
        controller.exists(_subscription(title: 'Stored show')),
        isTrue,
      );
      expect(
        controller.exists(
          _subscription(rssFeedUrl: 'https://example.com/stored.xml'),
        ),
        isTrue,
      );
      expect(
        controller.exists(
          _subscription(
            title: 'Different show',
            rssFeedUrl: 'https://example.com/different.xml',
          ),
        ),
        isFalse,
      );
      expect(controller.exists(_subscription()), isFalse);
    });

    test('getByTitle returns the matching instance or null', () {
      final first = _subscription(id: 1, title: 'First');
      final second = _subscription(id: 2, title: 'Second');
      final controller = SubscriptionController(store: _FakeSubscriptionStore())
        ..subscriptions.addAll([first, second]);

      expect(controller.getByTitle('Second'), same(second));
      expect(controller.getByTitle('Missing'), isNull);
    });
  });
}

SubscriptionModel _subscription({
  int? id,
  String? title,
  String? rssFeedUrl,
}) {
  return SubscriptionModel.fromMap({
    'id': id,
    'title': title,
    'rssFeedUrl': rssFeedUrl,
  });
}

class _FakeSubscriptionStore implements SubscriptionStore {
  _FakeSubscriptionStore({
    this.onListAll,
    this.onAddMany,
    this.onRemove,
  });

  final Future<List<SubscriptionModel>> Function()? onListAll;
  final Future<void> Function(List<SubscriptionModel>)? onAddMany;
  final Future<void> Function(SubscriptionModel)? onRemove;

  int listAllCalls = 0;
  int addManyCalls = 0;
  int removeCalls = 0;
  final removed = <SubscriptionModel>[];

  @override
  Future<List<SubscriptionModel>> listAll() {
    listAllCalls++;
    return onListAll?.call() ?? Future.value(<SubscriptionModel>[]);
  }

  @override
  Future<void> addMany(List<SubscriptionModel> subscriptions) {
    addManyCalls++;
    return onAddMany?.call(subscriptions) ?? Future.value();
  }

  @override
  Future<void> remove(SubscriptionModel subscription) {
    removeCalls++;
    removed.add(subscription);
    return onRemove?.call(subscription) ?? Future.value();
  }
}
