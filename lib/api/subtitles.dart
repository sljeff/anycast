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
  List<Subtitle>? subtitles;
}

Future<SubtitleResult> getSubtitles(String enclosureUrl) async {
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
  result.status = data['status'];

  if (result.status != 'succeeded') {
    return result;
  }

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
