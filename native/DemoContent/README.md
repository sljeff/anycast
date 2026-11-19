# Demo content

Demo mode runs the real app with a local snapshot of ten real podcasts for
website and App Store screenshots. It is available in DEBUG simulator builds
that launch with `-anycast-demo-content` or `ANYCAST_DEMO_CONTENT=1`.

## Content and assets

`content.json` holds the publisher RSS metadata, source URLs, five recent
episodes per show, and selections for Inbox, Playlist, Library, and Discover.
The Discover lists are curated, with The Daily and The Ezra Klein Show drawn
from [Apple Podcasts’ US Top 25](https://rss.applemarketingtools.com/api/v2/us/podcasts/top/25/podcasts.json).
Show and episode descriptions retain the feed text with outbound links removed.

The queue opens on “Know the Score” from 99% Invisible. Its opening was aligned
from the actual recording with Whisper and translated into Simplified Chinese.
The same transcript supplies the three Moments and the jump destinations for
the scripted Ask AI conversation. The builder checks the hero audio against
the checksum in `content.json` to preserve the transcript alignment.

The builder requires Python 3, Pillow, and curl. It downloads publisher covers
and resizes them to at most 1400 pixels per side. It stages full audio for the
three episodes marked downloaded. It caches source assets in `demo-assets`
next to the output directory. The app serves the staged feeds, artwork, and API
responses from `Documents/demo` at `https://demo.anycast.example`. The demo
network protocol fails requests to other hosts.

## Build and capture

```sh
native/scripts/demo_shots.sh
native/scripts/demo_shots.sh --appearance dark --skip-build
```

The capture script seeds `native/build/runs/demo-state` and writes screenshots
to `native/build/runs/demo-shots/<timestamp>/{light,dark}/`. Generated state,
downloaded assets, and transcription tools belong under `native/build/runs/`.

To rebuild the state from an existing demo container without launching the app:

```sh
python3 native/DemoContent/build_demo_state.py \
  --container native/build/runs/demo-state \
  --out native/build/runs/demo-state-real-check
```

Use a separate output directory. The builder copies the app-created database,
requires schema version 5 and the expected columns, and seeds rows in the copy.
