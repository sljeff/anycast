import 'package:sqflite/sqflite.dart';

Future<void> subscriptionTableCreator(DatabaseExecutor db) {
  return db.execute("""
    CREATE TABLE IF NOT EXISTS subscription (
      id INTEGER PRIMARY KEY,
      rssFeedUrl TEXT,
      title TEXT,
      description TEXT,
      imageUrl TEXT,
      link TEXT,
      categories TEXT,
      author TEXT,
      email TEXT
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
    for (SubscriptionModel subscription in subscriptions) {
      batch.insert('subscription', subscription.toMap());
    }
    await batch.commit(noResult: true);
  }
}
