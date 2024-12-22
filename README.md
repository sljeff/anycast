<h1 align="center" style="border-bottom: none">
    <b>
        <a href="https://anycast.website">Anycast</a><br>
    </b>
    An AI-powered Podcast App<br>
</h1>

<p align="center">
    Cross-platform, Seamless RSS Integration, Global Content Discovery, and AI
</p>

<p align="center">
<a href="https://apps.apple.com/hk/app/anycast/id6499069246">
<img height="50" src="docs/img/appstore.svg" />
</a>
<a href="https://groups.google.com/g/anycastplus/c/MW2VDoMNWQU">
<img height="50" src="docs/img/playstore.svg" />
</a>
<a href="https://www.producthunt.com/posts/anycast?embed=true&utm_source=badge-featured&utm_medium=badge&utm_souce=badge-anycast">
<img height="50" src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=479006&theme=dark" />
</a>
<a href="https://t.me/+GlVRhl1nEVk2MmNl">
<img height="50" src="https://upload.wikimedia.org/wikipedia/commons/8/83/Telegram_2019_Logo.svg" />
</a>
</p>

<p align="center">
<img src="docs/img/main.png" />
</p>

## Website

[https://anycast.website](https://anycast.website)

## Features
<!-- | Feature | Description | Image |
| --- | --- | --- |
| AI Transcription | AI transcribes your podcast | ![AI Transcription](docs/img/feat_ai_trans.png)  -->

<table>
<tr>
<td style="width: 75%"> <img src="docs/img/feat_ai_trans.png" /></td>
<td>
<b>AI Transcription</b>
<br>
<ul>
<li>Support 10+ languages</li>
<li>Bilingual Subtitle</li>
<li>Export to LRC</li>
</ul>
</td>
</tr>
<tr>
<td> <img src="docs/img/feat_ai_chat.png" /></td>
<td>
<b>AI Chat</b>
<br>
Curious about this podcast? Ask it anything.
</td>
</tr>
<tr>
<td> <img src="docs/img/feat_rss.png" /></td>
<td>
<b>Good RSS Integration</b>
<br>
<ul>
<li>Subscribe to podcasts from any iTunes compatible RSS feed.</li>
<li>Import or export your subscriptions with OPML.</li>
</ul>
</td>
</tr>
<tr>
<td> <img src="docs/img/feat_country.png" /></td>
<td>
<b>Access podcasts from all over the world</b>
<br>
<ul>
<li>Tens of countries available.</li>
<li>A variety of types of podcasts.</li>
</ul>
</td>
</tr>
</table>

## TODO

- [ ] Create different playlists
- [ ] Brand new UI design
- [ ] Support time navigation in show notes
- [ ] Support for custom ASR API and Chat API without mandatory login
- [ ] Compiler conditions for the open-source version, without requiring Firebase / RevenueCat configurations
- [ ] Carplay support
- [ ] AI recommendations
- [ ] Enhanced note-taking features

## Contributing

Conditional compilation will be supported soon, allowing you to compile with minimal (or no) extra steps.

Currently, when cloning and compiling the project, the following additional files are required:

- `.env`
- `android/app/google-services.json`
- `android/key.properties`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

## License

Anycast is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
