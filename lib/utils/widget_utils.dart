import 'package:flutter/material.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/helper.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:provider/provider.dart';
import 'package:anycast/models/player.dart';

Future<void> playByEpisode(
    BuildContext context, PlaylistEpisodeModel episode) async {
  var playlistId = episode.playlistId!;
  var player = PlayerModel.fromMap({
    'playlistEpisodeGuid': episode.guid,
  });

  var db = await DatabaseHelper().db;

  if (db == null) {
    throw Exception('Unable to open database');
  }
  PlayerModel.update(db, player).then((_) {
    Provider.of<PlayerProvider>(context, listen: false)
        .setPlayer(player, episode);
    MyAudioHandler.setPlaylistByPlaylistId(playlistId).then((_) {
      MyAudioHandler().play();
    });
  });
}
