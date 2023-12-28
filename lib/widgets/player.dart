import 'package:flutter/material.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:provider/provider.dart';

class PlayerWidget extends StatefulWidget {
  const PlayerWidget({super.key});

  @override
  State<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends State<PlayerWidget> {
  DatabaseHelper helper = DatabaseHelper();
  PlaylistEpisodeModel? episode;

  @override
  void initState() {
    super.initState();
    helper.db.then((db) {
      if (db == null) {
        throw Exception('Unable to open database');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, value, child) {
        var isPlaying = value.isPlaying;
        var player = value.player;

        if (player == null || player.playlistEpisodeGuid == null) {
          return const SizedBox.shrink();
        }

        if (episode == null || episode?.guid != player.playlistEpisodeGuid) {
          helper.db.then((db) {
            if (db == null) {
              throw Exception('Unable to open database');
            }
            PlaylistEpisodeModel.getByGuid(db, player.playlistEpisodeGuid!)
                .then((value) {
              setState(() {
                print('setting state');
                episode = value;
              });
            });
          });
        }

        var imageUrl = episode?.imageUrl;

        return SizedBox(
          width: 100,
          child: FloatingActionButton(
            onPressed: () {
              // toggle play/pause
              value.setIsPlaying(!isPlaying);
            },
            child: Row(
              // center and space between
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(imageUrl, width: 40, height: 40))
                    : const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.image),
                      ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: isPlaying
                      ? const Icon(Icons.pause)
                      : const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
