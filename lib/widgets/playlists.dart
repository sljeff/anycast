import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/widget_utils.dart';
import 'package:anycast/widgets/detail.dart';
import 'package:flutter/material.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/playlist_episode.dart';
import 'package:provider/provider.dart';

class Playlists extends StatefulWidget {
  const Playlists({super.key});

  @override
  State<Playlists> createState() => _PlaylistsState();
}

class _PlaylistsState extends State<Playlists> {
  DatabaseHelper helper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    helper.db.then((db) {
      if (db == null) {
        throw Exception('Unable to open database');
      }
      PlaylistModel.listAll(db).then((value) {
        Provider.of<PlaylistProvider>(context, listen: false).load(value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, value, child) {
        var playlists = value.playlists;
        return DefaultTabController(
          length: playlists.length,
          child: Scaffold(
              appBar: AppBar(
                title: const Text('Playlists'),
                bottom: TabBar(
                    tabs: playlists.map((playlist) {
                  return Tab(text: playlist.title);
                }).toList()),
              ),
              body: TabBarView(
                  children: playlists.map((playlist) {
                return PlaylistEpisodesList(playlist: playlist);
              }).toList())),
        );
      },
    );
  }
}

class PlaylistEpisodesList extends StatefulWidget {
  final PlaylistModel playlist;

  const PlaylistEpisodesList({Key? key, required this.playlist})
      : super(key: key);

  @override
  State<PlaylistEpisodesList> createState() => _PlaylistEpisodesListState();
}

class _PlaylistEpisodesListState extends State<PlaylistEpisodesList>
    with AutomaticKeepAliveClientMixin {
  final DatabaseHelper helper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    helper.db.then((db) {
      if (db == null) {
        throw Exception('Unable to open database');
      }
      var playlistId = widget.playlist.id!;
      PlaylistEpisodeModel.listByPlaylistId(db, playlistId).then((value) {
        Provider.of<PlaylistEpisodeProvider>(context, listen: false)
            .loadByPlaylistId(playlistId, value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<PlaylistEpisodeProvider>(
      builder: (context, value, child) {
        var episodes = value.episodes[widget.playlist.id!] ?? [];
        return ListView.builder(
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            var episode = episodes[index];
            return ExpansionTile(
              controlAffinity: ListTileControlAffinity.leading,
              leading: episode.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                              context: context,
                              builder: (context) => DetailWidget(episode));
                        },
                        child: Image.network(episode.imageUrl!,
                            width: 48, height: 48),
                      ),
                    )
                  : const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.image),
                    ),
              title: Text(episode.title!, style: const TextStyle(fontSize: 14)),
              subtitle: Row(
                children: [
                  Text(
                    episode.channelTitle!,
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
                    formatRemainingTime(
                      Duration(milliseconds: episode.duration!),
                      Duration(milliseconds: episode.playedDuration ?? 0),
                    ),
                    style: const TextStyle(fontSize: 9),
                  ),
                  const Text(
                    " • ",
                    style: TextStyle(fontSize: 9),
                  ),
                  Text(
                    formatDatetime(episode.pubDate!),
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ),
              children: [
                ButtonBar(
                  alignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                        onPressed: () {
                          if (index != 0) {
                            // move to top
                            helper.db.then((db) {
                              if (db == null) {
                                throw Exception('Unable to open database');
                              }
                              PlaylistEpisodeModel.insertOrUpdateByIndex(
                                      db, widget.playlist.id!, 0, episode)
                                  .then((_) {
                                Provider.of<PlaylistEpisodeProvider>(context,
                                        listen: false)
                                    .moveToTop(widget.playlist.id!, episode);
                                playByEpisode(context, episode);
                              });
                            });
                          } else {
                            playByEpisode(context, episode);
                          }
                        },
                        icon: Icon(Icons.play_arrow)),
                    IconButton(
                        onPressed: () {
                          // remove from playlist db
                          helper.db.then((db) {
                            if (db == null) {
                              throw Exception('Unable to open database');
                            }
                            PlaylistEpisodeModel.delete(db, episode.id!);
                            Provider.of<PlaylistEpisodeProvider>(context,
                                    listen: false)
                                .removeFromPlaylist(
                                    widget.playlist.id!, episode.id!);
                            MyAudioHandler().removeQueueItemAt(index);
                          });
                        },
                        icon: Icon(Icons.delete)),
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
