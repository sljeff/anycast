#!/usr/bin/env python3
"""Builds the seeded demo state dir (Documents/ + Library/) for demo mode.

    python3 build_demo_state.py --container <app data container> --out <state dir>

<container> is the data container of the app right after its first launch in
a fresh simulator (so anycast.db is the app's own latest schema plus its seed
rows). The script copies that DB, refuses to continue unless it is schema
version 5 with the expected columns, and seeds rows in the copy. It never
edits the app schema or the tracked fixtures. Requires curl and Pillow.
"""
import argparse
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time
import uuid
from email.utils import parsedate_to_datetime
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image

import content

HOST = content.HOST
SHOW = {s["slug"]: s for s in content.SHOWS}

EXPECTED_COLUMNS = {
    "feedEpisode": "id title description duration enclosureUrl pubDate imageUrl channelTitle rssFeedUrl",
    "playlistEpisode": "id title description duration enclosureUrl pubDate imageUrl channelTitle rssFeedUrl playlistId position playedDuration",
    "subscription": "id rssFeedUrl title description imageUrl link categories author email lastUpdated",
    "playlist": "id title position",
    "player": "id currentPlaylistId",
    "settings": "id darkMode speed skipSilence autoSleepTimer maxCacheCount countryCode targetLanguage autoRefreshInterval maxFeedEpisodes maxHistoryEpisodes continuousPlaying",
    "subtitle": "id enclosureUrl status subtitle language summary",
    "historyEpisode": "id title description duration enclosureUrl pubDate imageUrl channelTitle rssFeedUrl lastPlayedAt",
    "translation": "id enclosureUrl status translation language",
}


def fmt(ms):
    seconds = ms // 1000
    return f"{seconds // 60}:{seconds % 60:02d}"


def feed_url(slug):
    return f"{HOST}/feeds/{slug}.xml"


def download(url, cache):
    """Cache by source URL, publishing the file only after curl succeeds."""
    path = cache / hashlib.sha256(url.encode()).hexdigest()
    if not path.is_file():
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            partial = Path(directory) / "asset"
            subprocess.run(
                ["curl", "--fail", "--silent", "--show-error", "--location",
                 "--retry", "2", "--max-time", "120", "--output", str(partial), url],
                check=True,
            )
            partial.replace(path)
    return path


def art_url(slug):
    return f"{HOST}/art/{slug}.jpg"


def stamp(lines, text):
    # Chat pills seek in whole seconds. Round up so they land inside the line.
    return re.sub(r"\{t:(\d+)\}", lambda m: fmt(
        ((lines[int(m.group(1))]["startMs"] + 999) // 1000) * 1000), text)


# MARK: - Main

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--container", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    container = Path(args.container).resolve()
    out = Path(args.out).resolve()
    if container.is_relative_to(out):
        raise SystemExit("--out would overwrite the source container")
    source_db = container / "Documents" / "anycast.db"
    if not source_db.is_file():
        raise SystemExit(f"no app database at {source_db}: launch the app once in a fresh container first")

    if out.exists():
        shutil.rmtree(out)
    docs = out / "Documents"
    demo = docs / "demo"
    caches = out / "Library" / "Caches" / "anycast_episode"
    support = out / "Library" / "Application Support"
    asset_cache = out.parent / "demo-assets"
    for directory in (demo / "art", demo / "api", demo / "feeds", demo / "audio", caches, support / "Moments"):
        directory.mkdir(parents=True)
    asset_cache.mkdir(exist_ok=True)

    shutil.copy(source_db, docs / "anycast.db")
    db = sqlite3.connect(docs / "anycast.db")
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version != 5:
        raise SystemExit(f"schema version {version}, expected 5: update DemoContent for the new schema")
    for table, columns in EXPECTED_COLUMNS.items():
        actual = " ".join(row[1] for row in db.execute(f"PRAGMA table_info({table})"))
        if actual != columns:
            raise SystemExit(f"{table} columns drifted:\n  have {actual}\n  want {columns}")

    now_ms = int(time.time() * 1000)

    for slug, show in SHOW.items():
        with Image.open(download(show["artworkUrl"], asset_cache)) as cover:
            cover.thumbnail((1400, 1400))
            cover.convert("RGB").save(demo / "art" / f"{slug}.jpg", quality=90)

    hero_key = content.HERO["slug"], content.HERO["number"]
    lines = content.HERO["lines"]
    episodes = {}
    for item in content.EPISODES:
        slug, number = item["slug"], item["number"]
        suffix = {"audio/mpeg": "mp3", "audio/mp4": "m4a"}[item["enclosureType"]]
        filename = f"{slug}-{number:02d}.{suffix}"
        episodes[(slug, number)] = dict(
            slug=slug, title=item["title"], duration=item["duration"] * 1000,
            pub=int(parsedate_to_datetime(item["pubDate"]).timestamp() * 1000), pub_date=item["pubDate"],
            description="".join(f"<p>{escape(p)}</p>" for p in item["notes"].split("\n\n")),
            url=f"{HOST}/audio/{filename}", filename=filename, suffix=suffix,
            image=art_url(slug), show=SHOW[slug]["title"], feed=feed_url(slug),
            enclosure_bytes=item["enclosureBytes"], enclosure_type=item["enclosureType"],
            source_url=item["enclosureUrl"])

    hero = episodes[hero_key]
    downloads = []
    for key in content.DOWNLOADS:
        episode = episodes[key]
        source_url = episode["source_url"]
        if key == hero_key:
            source_url = content.HERO["audioUrl"]
        source = download(source_url, asset_cache)
        if key == hero_key and hashlib.sha256(source.read_bytes()).hexdigest() != content.HERO["audioSha256"]:
            raise SystemExit("Hero audio differs from the recording used to align the transcript")
        episode["enclosure_bytes"] = source.stat().st_size
        local_audio = demo / "audio" / episode["filename"]
        shutil.copyfile(source, local_audio)
        cache_file = f"{uuid.uuid4()}.{episode['suffix']}"
        shutil.copyfile(local_audio, caches / cache_file)
        downloads.append((episode["url"], cache_file, episode["enclosure_bytes"]))

    def episode_row(key, **extra):
        e = episodes[key]
        return dict(title=e["title"], description=e["description"], duration=e["duration"],
                    enclosureUrl=e["url"], pubDate=e["pub"], imageUrl=e["image"],
                    channelTitle=e["show"], rssFeedUrl=e["feed"], **extra)

    def insert(table, row):
        names = ", ".join(row)
        marks = ", ".join("?" for _ in row)
        db.execute(f"INSERT INTO {table} ({names}) VALUES ({marks})", list(row.values()))

    with db:
        for table in ("feedEpisode", "playlistEpisode", "subscription", "historyEpisode", "subtitle", "translation"):
            db.execute(f"DELETE FROM {table}")
        for slug, show in SHOW.items():
            insert("subscription", dict(
                rssFeedUrl=feed_url(slug), title=show["title"], description=show["description"],
                imageUrl=art_url(slug), link=feed_url(slug), categories=show["category"],
                author=show["author"], email="", lastUpdated=episodes[(slug, 1)]["pub"]))
        for key in content.INBOX:
            insert("feedEpisode", episode_row(key))
        for position, key in enumerate(content.QUEUE, start=1):
            resume = content.QUEUE_PLAYED.get(key, 0) * 1000
            if key == hero_key:
                resume = lines[content.HERO["resumeLine"]]["startMs"]
            insert("playlistEpisode", episode_row(key, playlistId=1, position=float(position), playedDuration=resume))
        for offset, key in enumerate(content.HISTORY):
            insert("historyEpisode", episode_row(key, lastPlayedAt=now_ms - (offset + 1) * 6 * 3600 * 1000))
        hero_url = hero["url"]
        segments = [dict(start=l["startMs"] / 1000, end=l["endMs"] / 1000, text=l["text"]) for l in lines]
        translated = [dict(start=l["startMs"] / 1000, end=l["endMs"] / 1000, text=l["zh"]) for l in lines]
        dump = lambda value: json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        insert("subtitle", dict(enclosureUrl=hero_url, status="succeeded", subtitle=dump(segments), language=content.HERO["language"]))
        insert("translation", dict(enclosureUrl=hero_url, status="succeeded", translation=dump(translated), language=content.HERO["translationLanguage"]))
        db.execute("UPDATE player SET currentPlaylistId = 1")
        db.execute("UPDATE settings SET targetLanguage = 'zh', countryCode = 'US', autoRefreshInterval = 1000000, "
                   "maxFeedEpisodes = 100, maxHistoryEpisodes = 100")
    db.close()

    # Audio cache index (same layout the app writes)
    meta = sqlite3.connect(support / "anycast_episode.db")
    with meta:
        meta.execute("CREATE TABLE cacheObject (_id INTEGER PRIMARY KEY, url TEXT, key TEXT, relativePath TEXT, "
                     "eTag TEXT, validTill INTEGER, touched INTEGER, length INTEGER)")
        meta.executemany("INSERT INTO cacheObject (url, key, relativePath, eTag, validTill, touched, length) "
                     "VALUES (?, ?, ?, NULL, ?, ?, ?)",
                     [(url, url, name, now_ms + 3650 * 86400 * 1000, now_ms, size)
                      for url, name, size in downloads])
        meta.execute("PRAGMA user_version = 3")
    meta.close()

    # Moments (newest first); createdAt is seconds since 2001-01-01.
    reference_now = time.time() - 978307200
    moments = []
    for order, index in enumerate(content.HERO["momentLines"]):
        line = lines[index]
        moments.append(dict(id=str(uuid.uuid4()).upper(), enclosureURL=hero["url"], rssFeedURL=hero["feed"],
                            episodeTitle=hero["title"], showTitle=hero["show"], artworkURL=hero["image"],
                            startMilliseconds=line["startMs"], text=line["text"], translation=line["zh"],
                            createdAt=reference_now - (order * 5 + 1) * 3600))
    (support / "Moments" / "moments.json").write_text(
        json.dumps(dict(version=1, moments=moments), ensure_ascii=False), encoding="utf-8")

    # RSS per show (channel pages and refresh)
    for slug, show in SHOW.items():
        items = ""
        for (s, _), e in episodes.items():
            if s != slug:
                continue
            items += (f"<item><title>{escape(e['title'])}</title><description>{escape(e['description'])}</description>"
                      f"<pubDate>{escape(e['pub_date'])}</pubDate><guid>{e['url']}</guid>"
                      f"<enclosure url=\"{e['url']}\" length=\"{e['enclosure_bytes']}\" type=\"{e['enclosure_type']}\"/>"
                      f"<itunes:duration>{e['duration'] // 1000}</itunes:duration></item>")
        (demo / "feeds" / f"{slug}.xml").write_text(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss version=\"2.0\" "
            "xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"><channel>"
            f"<title>{escape(show['title'])}</title><link>{feed_url(slug)}</link>"
            f"<description>{escape(show['description'])}</description><language>{escape(show['language'])}</language>"
            f"<itunes:author>{escape(show['author'])}</itunes:author>"
            f"<itunes:image href=\"{art_url(slug)}\"/>{items}</channel></rss>", encoding="utf-8")

    # Canned API answers
    def channel(slug):
        show = SHOW[slug]
        return dict(rss_url=feed_url(slug), title=show["title"], description=show["description"],
                    small_cover_url=art_url(slug), link=feed_url(slug), keywords=[], author=show["author"])

    api = demo / "api"
    write = lambda name, value: (api / name).write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    write("categories.json", dict(data=[
        dict(name=category["name"], id=category["id"], image_url=art_url(content.CHARTS[category["id"]][0]),
             night_image_url=art_url(content.CHARTS[category["id"]][0]))
        for category in content.CATEGORIES]))
    for cid, slugs in content.CHARTS.items():
        name = "top-channels.json" if cid == "top" else f"top-channels.{cid}.json"
        write(name, dict(data=dict(list=[channel(s) for s in slugs])))
    write("search.channels.json", dict(data=dict(channel_list=[channel(s) for s in SHOW])))
    write("search.episodes.json", dict(data=[
        dict(title=e["title"], description=e["description"], duration=e["duration"], url=e["url"],
             release_date=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e["pub"] / 1000)),
             cover_url=e["image"], channel=channel(e["slug"])) for e in episodes.values()][:8]))
    write("chat.json", dict(
        followUpQuestion=content.CHAT["followUpQuestion"],
        replies=[dict(match=item["match"], result=stamp(lines, item["result"])) for item in content.CHAT["replies"]],
        fallback=stamp(lines, content.CHAT["fallback"])))

    print(f"state ready: {out} (hero audio {fmt(hero['duration'])}, {len(content.HERO['lines'])} lines)")


if __name__ == "__main__":
    main()
