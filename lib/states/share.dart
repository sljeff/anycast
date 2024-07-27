import 'dart:async';
import 'dart:io';

import 'package:anycast/widgets/share.dart';
import 'package:get/get.dart';
import 'package:opml/opml.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class OPML {
  final String title;
  final String url;

  OPML(this.title, this.url);
}

class ShareController extends GetxController {
  late StreamSubscription _intentSub;
  final _sharedFiles = <SharedMediaFile>[].obs;
  final progress = 0.0.obs;
  final _opmls = <OPML>[].obs;

  SharedMediaFile? get sharedFile =>
      _sharedFiles.isNotEmpty ? _sharedFiles.first : null;
  List<OPML> get opmls => _opmls;

  @override
  void onInit() {
    super.onInit();
    _initReceiveSharingIntent();
  }

  @override
  void onClose() {
    super.onClose();
    _intentSub.cancel();
  }

  void _initReceiveSharingIntent() {
    // Listen to media sharing coming from outside the app while the app is in the memory.
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      _sharedFiles.clear();
      _sharedFiles.addAll(value);

      parseOPML().then((_) {
        Get.dialog(const ShareDialog());
      });
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });

    // Get the media sharing coming from outside the app while the app is closed.
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isEmpty) {
        return;
      }

      _sharedFiles.clear();
      _sharedFiles.addAll(value);

      Future.delayed(const Duration(seconds: 2), () {
        parseOPML().then((_) {
          Get.dialog(const ShareDialog(), barrierDismissible: false);
        });
      });

      // Tell the library that we are done processing the intent.
      ReceiveSharingIntent.instance.reset();
    });
  }

  Future<void> parseOPML() async {
    if (sharedFile == null) {
      return;
    }
    var path = sharedFile!.path;
    if (path.startsWith('file://')) {
      path = Uri.parse(sharedFile!.path).toFilePath();
    }
    var content = await File(path).readAsString();
    final opml = OpmlDocument.parse(content);

    var result = <OPML>[];
    for (var outline in opml.body) {
      if (outline.title == null || outline.xmlUrl == null) {
        continue;
      }
      if (outline.title!.isEmpty || outline.xmlUrl!.isEmpty) {
        continue;
      }
      result.add(OPML(outline.title!, outline.xmlUrl!));
    }
    _opmls.value = result;
  }
}
