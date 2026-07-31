PRAGMA user_version = 3;

CREATE TABLE feedEpisode (
  id INTEGER PRIMARY KEY,
  title TEXT,
  description TEXT,
  duration INTEGER,
  enclosureUrl TEXT UNIQUE,
  pubDate INTEGER,
  imageUrl TEXT,
  channelTitle TEXT,
  rssFeedUrl TEXT
);

CREATE TABLE playlistEpisode (
  id INTEGER PRIMARY KEY,
  title TEXT,
  description TEXT,
  duration INTEGER,
  enclosureUrl TEXT UNIQUE,
  pubDate INTEGER,
  imageUrl TEXT,
  channelTitle TEXT,
  rssFeedUrl TEXT,
  playlistId INTEGER,
  position REAL,
  playedDuration INTEGER
);

CREATE TABLE subscription (
  id INTEGER PRIMARY KEY,
  rssFeedUrl TEXT UNIQUE,
  title TEXT UNIQUE,
  description TEXT,
  imageUrl TEXT,
  link TEXT,
  categories TEXT,
  author TEXT,
  email TEXT,
  lastUpdated INTEGER
);

CREATE TABLE playlist (
  id INTEGER PRIMARY KEY,
  title TEXT,
  position INTEGER
);

CREATE TABLE player (
  id INTEGER PRIMARY KEY,
  currentPlaylistId INTEGER
);

CREATE TABLE settings (
  id INTEGER PRIMARY KEY,
  darkMode INTEGER,
  speed REAL,
  skipSilence INTEGER,
  autoSleepTimer TEXT,
  maxCacheCount INTEGER,
  countryCode TEXT,
  targetLanguage TEXT,
  autoRefreshInterval INTEGER,
  maxFeedEpisodes INTEGER,
  maxHistoryEpisodes INTEGER
);

CREATE TABLE subtitle (
  id INTEGER PRIMARY KEY,
  enclosureUrl TEXT UNIQUE,
  status TEXT,
  subtitle TEXT,
  language TEXT,
  summary TEXT
);

CREATE TABLE historyEpisode (
  id INTEGER PRIMARY KEY,
  title TEXT,
  description TEXT,
  duration INTEGER,
  enclosureUrl TEXT UNIQUE,
  pubDate INTEGER,
  imageUrl TEXT,
  channelTitle TEXT,
  rssFeedUrl TEXT
);

CREATE TABLE translation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  enclosureUrl TEXT UNIQUE,
  status TEXT,
  translation TEXT,
  language TEXT
);

INSERT INTO settings (
  id,
  darkMode,
  speed,
  skipSilence,
  autoSleepTimer,
  maxCacheCount,
  countryCode,
  targetLanguage,
  autoRefreshInterval,
  maxFeedEpisodes,
  maxHistoryEpisodes
) VALUES (1, 1, 1.75, 1, '22,6,3', 37, 'TW', 'ja', 917, 321, 654);

INSERT INTO playlist (id, title, position)
VALUES (1, 'Default', 1);

INSERT INTO playlist (id, title, position)
VALUES (104, 'Released playlist', 8);

INSERT INTO player (id, currentPlaylistId)
VALUES (1, 104);

INSERT INTO feedEpisode (
  id,
  title,
  description,
  duration,
  enclosureUrl,
  pubDate,
  imageUrl,
  channelTitle,
  rssFeedUrl
) VALUES (
  101,
  'Released feed episode',
  'Feed data must survive upgrades',
  3600000,
  'https://released.example/feed-episode.mp3',
  1700000101,
  'https://released.example/feed.jpg',
  'Released feed',
  'https://released.example/feed.xml'
);

INSERT INTO playlistEpisode (
  id,
  title,
  description,
  duration,
  enclosureUrl,
  pubDate,
  imageUrl,
  channelTitle,
  rssFeedUrl,
  playlistId,
  position,
  playedDuration
) VALUES (
  102,
  'Released playlist episode',
  'Playback progress must survive upgrades',
  4200000,
  'https://released.example/playlist-episode.mp3',
  1700000102,
  'https://released.example/playlist.jpg',
  'Released feed',
  'https://released.example/feed.xml',
  104,
  2.5,
  4567
);

INSERT INTO subscription (
  id,
  rssFeedUrl,
  title,
  description,
  imageUrl,
  link,
  categories,
  author,
  email,
  lastUpdated
) VALUES (
  103,
  'https://released.example/feed.xml',
  'Released subscription',
  'Subscription data must survive upgrades',
  'https://released.example/subscription.jpg',
  'https://released.example',
  'technology,science',
  'Released author',
  'released@example.com',
  1700000103
);

INSERT INTO subtitle (
  id,
  enclosureUrl,
  status,
  subtitle,
  language,
  summary
) VALUES (
  105,
  'https://released.example/playlist-episode.mp3',
  'completed',
  '[{"start":0,"end":1000,"text":"released subtitle"}]',
  'en',
  'Released summary'
);

INSERT INTO historyEpisode (
  id,
  title,
  description,
  duration,
  enclosureUrl,
  pubDate,
  imageUrl,
  channelTitle,
  rssFeedUrl
) VALUES (
  106,
  'Released history episode',
  'History data must survive upgrades',
  1800000,
  'https://released.example/history-episode.mp3',
  1700000106,
  'https://released.example/history.jpg',
  'Released feed',
  'https://released.example/feed.xml'
);

INSERT INTO translation (
  id,
  enclosureUrl,
  status,
  translation,
  language
) VALUES (
  107,
  'https://released.example/playlist-episode.mp3',
  'completed',
  '[{"start":0,"end":1000,"text":"released translation"}]',
  'zh'
);
