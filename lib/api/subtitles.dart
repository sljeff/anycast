import 'dart:convert';
import 'package:http/http.dart' as http;

const host = 'api.anycast.website';

class Subtitle {
  double? start;
  double? end;
  String? text;

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'text': text,
      };

  static Subtitle fromMap(Map<String, dynamic> json) {
    var subtitle = Subtitle();
    subtitle.start = json['start'];
    subtitle.end = json['end'];
    subtitle.text = json['text'];
    return subtitle;
  }
}

class SubtitleResult {
  String? status;
  String? language;
  List<Subtitle>? subtitles;
  String? summary;
}

Future<SubtitleResult> getSubtitles(String enclosureUrl) async {
  print('getSubtitles $enclosureUrl');
  var url = Uri(
    host: host,
    scheme: 'https',
    path: '/subtitles',
  );
  var req = jsonEncode({'enclosure_url': enclosureUrl});
  var headers = {'Content-Type': 'application/json'};

  var response = await http.post(url, body: req, headers: headers);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);

  var result = SubtitleResult();
  if (data['status'] != 'succeeded') {
    result.status = data['status'];
    return result;
  }

  result.language = data['subtitle']['detected_language'];
  result.status = data['status'];
  result.summary = '';

  result.subtitles = [];
  for (var item in data['subtitle']['segments']) {
    var subtitle = Subtitle();
    subtitle.start = item['start'];
    subtitle.end = item['end'];
    subtitle.text = item['text'];
    result.subtitles!.add(subtitle);
  }
  return result;
}

Future<List<Subtitle>?> getTranslation(
    String enclosureUrl, String language) async {
  print('getTranslation $enclosureUrl $language');
  var url = Uri(
    host: host,
    scheme: 'https',
    path: '/subtitles/translate',
  );
  var req = jsonEncode({'enclosure_url': enclosureUrl, 'language': language});
  var headers = {'Content-Type': 'application/json'};

  var response = await http.post(url, body: req, headers: headers);
  var body = utf8.decode(response.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);
  if (data['translation'] == null) {
    return null;
  }

  var result = <Subtitle>[];
  for (var item in data['translation']) {
    result.add(Subtitle.fromMap({
      'start': item['start'],
      'end': item['end'],
      'text': item['text'],
    }));
  }
  return result;
}
