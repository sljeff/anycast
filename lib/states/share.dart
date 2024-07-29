import 'dart:async';

import 'package:anycast/pages/feeds.dart';
import 'package:anycast/widgets/share.dart';
import 'package:get/get.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

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

      _parseOPML().then((_) {
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
        _parseOPML().then((_) {
          Get.dialog(const ShareDialog(), barrierDismissible: false);
        });
      });

      // Tell the library that we are done processing the intent.
      ReceiveSharingIntent.instance.reset();
    });
  }

  Future<void> _parseOPML() async {
    if (sharedFile == null) {
      return;
    }
    var path = sharedFile!.path;
    if (path.startsWith('file://')) {
      path = Uri.parse(sharedFile!.path).toFilePath();
    }

    var result = await parseOPML(path);
    _opmls.value = result;
  }
}
