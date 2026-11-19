"""Loader for content.json, the shared snapshot of the real demo content."""
import json
from pathlib import Path

_data = json.loads((Path(__file__).with_name("content.json")).read_text(encoding="utf-8"))

HOST = _data["host"]
SHOWS = _data["shows"]
CATEGORIES = _data["categories"]
CHARTS = _data["charts"]
HERO = _data["hero"]
EPISODES = _data["episodes"]
INBOX = [(e["slug"], e["number"]) for e in _data["inbox"]]
QUEUE = [(e["slug"], e["number"]) for e in _data["queue"]]
QUEUE_PLAYED = {(e["slug"], e["number"]): e["playedSeconds"] for e in _data["queue"] if "playedSeconds" in e}
HISTORY = [(e["slug"], e["number"]) for e in _data["history"]]
DOWNLOADS = [(e["slug"], e["number"]) for e in _data["downloads"]]
CHAT = _data["chat"]
