import 'dart:convert';
import 'dart:io';
import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/widget_utils.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:http/http.dart' as http;
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:anycast/states/subscription.dart';
import 'package:provider/provider.dart';
import 'package:webfeed_plus/webfeed_plus.dart';

import 'package:flutter/material.dart';
import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:anycast/models/subscription.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;

class Feeds extends StatefulWidget {
  const Feeds({Key? key}) : super(key: key);

  @override
  State<Feeds> createState() => _FeedsState();
}

class _FeedsState extends State<Feeds> with AutomaticKeepAliveClientMixin {
  final DatabaseHelper databaseHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    databaseHelper.db.then((db) {
      if (db == null) {
        throw Exception('Unable to open database');
      }
      FeedEpisodeModel.listAll(db).then((value) {
        Provider.of<FeedEpisodeProvider>(context, listen: false).load(value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<FeedEpisodeProvider>(
      builder: (context, value, child) {
        if (value.episodes.isEmpty) {
          return const ImportBlock();
        }
        return ListView.builder(
          itemCount: value.episodes.length,
          itemBuilder: (context, index) {
            return ExpansionTile(
              controlAffinity: ListTileControlAffinity.leading,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: GestureDetector(
                  onTap: () {
                    // show bottom sheet
                    showModalBottomSheet(
                        context: context,
                        builder: (context) =>
                            DetailWidget(value.episodes[index]));
                  },
                  child: Image.network(
                    value.episodes[index].imageUrl!,
                    fit: BoxFit.cover,
                    width: 48,
                  ),
                ),
              ),
              title: Text(
                value.episodes[index].title!,
                style: const TextStyle(
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        value.episodes[index].channelTitle!,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                            color: Colors.brown),
                      ),
                      const Text(
                        " • ",
                        style: TextStyle(fontSize: 9),
                      ),
                      Text(
                        value.episodes[index].duration != null
                            ? formatDuration(value.episodes[index].duration!)
                            : '',
                        style: const TextStyle(
                          fontSize: 9,
                        ),
                      ),
                      const Text(
                        " • ",
                        style: TextStyle(fontSize: 9),
                      ),
                      Text(
                        value.episodes[index].pubDate != null
                            ? formatDatetime(value.episodes[index].pubDate!)
                            : '',
                        style: const TextStyle(
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    htmlToText(value.episodes[index].description!)!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              children: [
                ButtonBar(
                  alignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                        onPressed: () {
                          addToPlaylist(databaseHelper, context,
                                  value.episodes[index])
                              .then((value) {
                            playByEpisode(context, value);
                          });
                        },
                        icon: const Icon(Icons.play_arrow)),
                    IconButton(
                        onPressed: () {
                          addToPlaylist(
                              databaseHelper, context, value.episodes[index]);
                        },
                        icon: const Icon(Icons.playlist_add)),
                    IconButton(
                        onPressed: () {
                          databaseHelper.db.then((db) {
                            if (db == null) {
                              throw Exception('Unable to open database');
                            }
                            FeedEpisodeModel.removeByGuid(
                                db, value.episodes[index].guid!);
                            Provider.of<FeedEpisodeProvider>(context,
                                    listen: false)
                                .removeByGuids([value.episodes[index].guid!]);
                          });
                        },
                        icon: const Icon(Icons.delete)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ImportBlock extends StatefulWidget {
  const ImportBlock({Key? key}) : super(key: key);

  @override
  State<ImportBlock> createState() => _ImportBlockState();
}

class _ImportBlockState extends State<ImportBlock> {
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    var controller = TextEditingController();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('No feeds found. Maybe you can:'),
          const SizedBox(height: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  // select xml file
                  FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['xml'],
                  ).then((value) {
                    if (value != null) {
                      setState(() {
                        isLoading = true;
                      });
                      parseOMPL(value.files.single.path).then((value) {
                        fetchPodcastsByUrls(value).then((value) {
                          Provider.of<FeedEpisodeProvider>(context,
                                  listen: false)
                              .addMany(
                                  value.map((e) => e.feedEpisode!).toList());
                          Provider.of<SubscriptionProvider>(context,
                                  listen: false)
                              .addMany(
                                  value.map((e) => e.subscription!).toList());
                          setState(() {
                            isLoading = false;
                          });
                        });
                      });
                    }
                  });
                },
                child: const Text('Import OMPL'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Provider.of<TabProvider>(context, listen: false).setIndex(2);
                },
                child: const Text('Search Podcasts'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                height: 50,
                child: TextField(
                  style: const TextStyle(fontSize: 10),
                  controller: controller,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.all(1),
                    border: const OutlineInputBorder(),
                    labelText: 'Enter a Podcast URL',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                        });
                        fetchPodcastsByUrls([controller.text]).then((value) {
                          Provider.of<FeedEpisodeProvider>(context,
                                  listen: false)
                              .addMany(
                                  value.map((e) => e.feedEpisode!).toList());
                          Provider.of<SubscriptionProvider>(context,
                                  listen: false)
                              .addMany(
                                  value.map((e) => e.subscription!).toList());
                          setState(() {
                            isLoading = false;
                          });
                        });
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<List<String>> parseOMPL(String? path) async {
  List<String> rssFeedUrls = [];

  if (path == null) {
    return rssFeedUrls;
  }

  File file = File(path);
  rssFeedUrls = await file.readAsString().then(
    (value) {
      XmlDocument document = XmlDocument.parse(value);
      List<String> xmlUrls = [];
      document.findAllElements('outline').forEach(
        (element) {
          xmlUrls.add(element.getAttribute('xmlUrl')!);
        },
      );
      return xmlUrls;
    },
  );

  return rssFeedUrls;
}

class PodcastImportData {
  SubscriptionModel? subscription;
  FeedEpisodeModel? feedEpisode;

  PodcastImportData(this.subscription, this.feedEpisode);
}

Future<List<PodcastImportData>> fetchPodcastsByUrls(
    List<String> rssFeedUrls) async {
  var db = await DatabaseHelper().db;
  if (db == null) {
    throw Exception('Unable to open database');
  }

  List<PodcastImportData> podcasts = [];

  var futures = rssFeedUrls.map((rssFeedUrl) {
    return http.get(Uri.parse(rssFeedUrl)).then((response) {
      var body = utf8.decode(response.bodyBytes);
      RssFeed channel;
      try {
        channel = RssFeed.parse(body);
      } catch (error) {
        print(error);
        return null;
      }
      var subscription = SubscriptionModel.fromMap(Map<String, dynamic>.from({
        'rssFeedUrl': rssFeedUrl,
        'title': channel.title?.trim(),
        'description': htmlToText(channel.description)?.trim(),
        'imageUrl': channel.image?.url ?? (channel.itunes?.image?.href ?? ''),
        'link': channel.link,
        'categories': channel.categories?.map((e) => e.value).join(','),
        'author': channel.itunes?.author,
        'email': channel.itunes?.owner?.email,
      }));
      var latestPubDate = channel.items?.first.pubDate;
      var latestIndex = 0;
      for (var i = 1; i < channel.items!.length; i++) {
        if (channel.items![i].pubDate!.isAfter(latestPubDate!)) {
          latestPubDate = channel.items![i].pubDate;
          latestIndex = i;
        }
      }
      var latestItem = channel.items![latestIndex];
      var feedEpisode = FeedEpisodeModel.fromMap(Map<String, dynamic>.from({
        'title': latestItem.title?.trim(),
        'description': latestItem.itunes?.summary?.trim() ??
            latestItem.description?.trim(),
        'guid': latestItem.guid,
        'duration': latestItem.itunes?.duration?.inMilliseconds,
        'enclosureUrl': latestItem.enclosure?.url,
        'pubDate': latestItem.pubDate?.millisecondsSinceEpoch,
        'imageUrl': latestItem.itunes?.image?.href ?? subscription.imageUrl,
        'channelTitle': subscription.title,
        'rssFeedUrl': subscription.rssFeedUrl,
      }));
      return PodcastImportData(subscription, feedEpisode);
    }).catchError((error) {
      print(error);
      return null;
    });
  }).toList();
  var result = await Future.wait(futures, eagerError: false);

  for (PodcastImportData? podcast in result) {
    if (podcast == null) {
      continue;
    }
    await podcast.subscription!.save(db);
    await podcast.feedEpisode?.save(db);
    podcasts.add(podcast);
  }

  return podcasts;
}

String? htmlToText(String? html) {
  if (html == null) {
    return null;
  }
  html = html.trim();

  if (!html.startsWith('<')) {
    return html;
  }

  try {
    var document = html_parser.parse(html);
    if (document.body == null) {
      return html;
    }
    return document.body?.text;
  } catch (error) {
    print(error);
    return html;
  }
}

Future<PlaylistEpisodeModel> addToPlaylist(DatabaseHelper helper,
    BuildContext context, FeedEpisodeModel episode) async {
  var playlistId = 1;

  // add to default playlist; remove from feeds
  var playlistEpisode = PlaylistEpisodeModel.fromMap(Map<String, dynamic>.from({
    'title': episode.title,
    'description': episode.description,
    'guid': episode.guid,
    'duration': episode.duration,
    'enclosureUrl': episode.enclosureUrl,
    'pubDate': episode.pubDate,
    'imageUrl': episode.imageUrl,
    'channelTitle': episode.channelTitle,
    'rssFeedUrl': episode.rssFeedUrl,
    'playlistId': playlistId,
    'position': double.infinity,
    'playedDuration': 0,
  }));
  return helper.db.then((db) {
    if (db == null) {
      throw Exception('Unable to open database');
    }

    PlaylistEpisodeModel.insertOrUpdateByIndex(
      db,
      playlistId,
      0,
      playlistEpisode,
    ).then((v) {
      Provider.of<PlaylistEpisodeProvider>(context, listen: false)
          .addToPlaylist(playlistId, playlistEpisode);
      MyAudioHandler().insertQueueItem(
        0,
        MyAudioHandler.playlistepisodeToMediaItem(playlistEpisode),
      );
    });
    FeedEpisodeModel.removeByGuid(db, episode.guid!).then((v) {
      Provider.of<FeedEpisodeProvider>(context, listen: false)
          .removeByGuids([episode.guid!]);
    });
    return playlistEpisode;
  });
}
