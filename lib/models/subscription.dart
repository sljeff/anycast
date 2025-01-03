import 'package:anycast/utils/rss_fetcher.dart';
import 'package:sqflite/sqflite.dart';

Future<void> subscriptionTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS subscription (
      id INTEGER PRIMARY KEY,
      rssFeedUrl TEXT UNIQUE,
      title TEXT UNIQUE,
      description TEXT,
      imageUrl TEXT,
      link TEXT,
      categories TEXT,
      author TEXT,
      email TEXT,
      lastUpdated INTEGER
    )
  """);
}

class SubscriptionModel {
  int? id;
  String? rssFeedUrl;
  String? title;
  String? description;
  String? imageUrl;
  String? link;
  String? categories; // comma separated list of categories
  String? author;
  String? email;
  int? lastUpdated; // unix timestamp

  SubscriptionModel.empty();

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      'rssFeedUrl': rssFeedUrl,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'link': link,
      'categories': categories,
      'author': author,
      'email': email,
      'lastUpdated': lastUpdated,
    };
    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  SubscriptionModel.fromMap(Map<String, dynamic> map) {
    id = map['id'];
    rssFeedUrl = map['rssFeedUrl'];
    title = map['title'];
    description = map['description'];
    imageUrl = map['imageUrl'];
    link = map['link'];
    categories = map['categories'];
    author = map['author'];
    email = map['email'];
    lastUpdated = map['lastUpdated'];
  }

  Future<void> save(DatabaseExecutor db) async {
    if (id == null) {
      id = await db.insert('subscription', toMap());
    } else {
      await db
          .update('subscription', toMap(), where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<List<SubscriptionModel>> listAll(DatabaseExecutor db) async {
    return db
        .rawQuery('SELECT * FROM subscription ORDER BY title ASC')
        .then((List<Map<String, dynamic>> maps) {
      return List.generate(maps.length, (i) {
        return SubscriptionModel.fromMap(maps[i]);
      });
    });
  }

  static Future<void> addMany(
      DatabaseExecutor db, List<SubscriptionModel> subscriptions) async {
    Batch batch = db.batch();
    // insert or update
    for (var subscription in subscriptions) {
      batch.insert('subscription', subscription.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> remove(
      DatabaseExecutor db, SubscriptionModel subscription) async {
    await db.delete('subscription',
        where: 'rssFeedUrl = ? or title = ?',
        whereArgs: [subscription.rssFeedUrl, subscription.title]);
  }

  Future<PodcastImportData> listAllEpisodes() async {
    return fetchPodcastsByUrls([rssFeedUrl!], onlyFistEpisode: false)
        .then((value) {
      if (value.isEmpty) {
        return PodcastImportData(this, []);
      }
      return value[0];
    });
  }

  static Future<SubscriptionModel?> getOrFetch(
      DatabaseExecutor db, String rssFeedUrl) async {
    return db.rawQuery('SELECT * FROM subscription WHERE rssFeedUrl = ?',
        [rssFeedUrl]).then((List<Map<String, dynamic>> maps) async {
      if (maps.isEmpty) {
        var data = await fetchPodcastsByUrls([rssFeedUrl]);
        return data[0].subscription;
      } else {
        return SubscriptionModel.fromMap(maps.first);
      }
    });
  }
}
