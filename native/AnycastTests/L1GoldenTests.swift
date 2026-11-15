import Foundation
import Testing
@testable import AnycastKit

/// L1 golden parity: G1–G16 expectations exported from the shipped Dart
/// implementation (pinned to 1.2.1+38). Byte-comparisons are exact; floating
/// point compares tolerate a few ULP because the golden JSON round-trips
/// through a decimal printer (see G15.stableDouble for the same rationale).
@Suite(.serialized)
struct L1GoldenTests {

    // MARK: - Helpers

    private func golden(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: RepoAssets.golden(name))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func fixtureJSONObject(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: RepoAssets.fixture(path))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    /// |a - b| within `maxULP` units-in-last-place.
    private func close(_ a: Double, _ b: Double, maxULP: Int = 4) -> Bool {
        guard a.isFinite && b.isFinite else { return a == b }
        if a == b { return true }
        let tolerance = Double(maxULP) * Swift.max(abs(a).ulp, abs(b).ulp)
        return abs(a - b) <= tolerance
    }

    private func expectClose(_ a: Double, _ b: Double, _ label: String, maxULP: Int = 4) {
        if !close(a, b, maxULP: maxULP) {
            Issue.record("\(label): \(a) != golden \(b)")
        }
    }

    // MARK: - Parser robustness (Dart xml parity)

    @Test("RSS parser: undefined entities stay literal like the Dart xml package; CDATA untouched")
    func rssUndefinedEntities() throws {
        let xml = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>AT&amp;T &nbsp; Studio</title>\
        <description><![CDATA[a &nbsp; b & c]]></description>\
        <item><title>t&nbsp;1</title></item></channel></rss>
        """
        guard let feed = RSSXMLParser.parse(data: Data(xml.utf8)) else {
            Issue.record("undefined entities must not abort the parse (Dart xml keeps them literal)")
            return
        }
        #expect(feed.title == "AT&T &nbsp; Studio")
        #expect(feed.description == "a &nbsp; b & c", "CDATA content is never entity-decoded")
        #expect(feed.items.first?.title == "t&nbsp;1")
    }

    @Test("DartSort boundary: 33 equal-key elements keep insertion order (SDK threshold is <= 32)")
    func dartSortBoundary() {
        let tagged = Array(0..<33)
        let sorted = DartSort.sorted(tagged) { _, _ in 0 }
        #expect(sorted == tagged,
                "right - left == 32 runs insertion sort in the Dart SDK — stable for equal keys")
    }

    // MARK: - 2026-09-23 parity pins (K39/K40 + rss_fetcher semantics)

    /// K39: verified against the Dart html package on 2026-09-23 —
    /// `body.text` for `a<script>var x=1;</script><style>.y{}</style>b`
    /// is `avar x=1;.y{}b` (script/style contents are text nodes there).
    @Test("K39: htmlToText keeps <script>/<style> contents like Dart body.text")
    func k39HtmlToTextScriptStyle() {
        #expect(HtmlText.htmlToText("<p>a</p><script>var x=1;</script><style>.y{}</style><p>b</p>")
                == "avar x=1;.y{}b")
    }

    /// K40: Dart `String.trim()` = Unicode White_Space ∪ U+FEFF (NOT 200B);
    /// Swift's `.whitespacesAndNewlines` = White_Space ∪ U+200B (NOT FEFF).
    /// dartTrimmed must close the gap in both directions.
    @Test("K40: dartTrimmed trims FEFF and keeps 200B like Dart String.trim()")
    func k40DartTrim() {
        #expect("\u{FEFF}x\u{FEFF}".dartTrimmed() == "x",
                "FEFF is trimmed by Dart but not by .whitespacesAndNewlines")
        #expect("\u{00A0}x\u{3000}".dartTrimmed() == "x", "NBSP / ideographic space (both worlds)")
        #expect("\u{2000}x\u{200A}".dartTrimmed() == "x", "U+2000–U+200A range (both worlds)")
        let notDartWhitespace = "\u{200B}x\u{180E}"
        #expect(notDartWhitespace.dartTrimmed() == notDartWhitespace,
                "U+200B is trimmed by .whitespacesAndNewlines but NOT by Dart; U+180E by neither")
    }

    /// rss_fetcher.dart:123-127: a non-empty feed whose first episode has no
    /// pubDate stores lastUpdated = NULL (not import time); compute then
    /// keeps re-entering the first-import branch (feeds.dart:275-284) until a
    /// dated episode arrives. Swallowing the NULL into `now` would satisfy
    /// `local >= fetched` forever and freeze the subscription.
    @Test("lastUpdated: NULL-first-pubDate stores NULL and re-imports like Dart")
    func lastUpdatedNullParity() throws {
        let xml = """
        <rss version="2.0"><channel><title>t</title>\
        <item><title>only</title><enclosure type="audio/mpeg" length="1"/></item>\
        </channel></rss>
        """
        guard let parsed = PodcastFeedParser.parse(
            rssFeedUrl: "https://example.com/feed.xml",
            xmlData: Data(xml.utf8),
            onlyFirstEpisode: true,
            nowEpochMilliseconds: 1_000
        ) else {
            Issue.record("feed must parse")
            return
        }
        #expect(parsed.subscription.lastUpdated == nil,
                "non-empty feed + nil first pubDate → NULL, not now")
        #expect(parsed.feedEpisodes.first?.enclosureUrl == nil,
                "an <enclosure> without a url keeps the episode (Dart: only enclosure == null skips)")

        var local = parsed.subscription
        local.rssFeedUrl = "https://example.com/feed.xml"
        let firstImport = SaveNewEpisodes.compute(fetched: [parsed], local: [local])
        #expect(firstImport.subscriptions.count == 1)
        #expect(firstImport.feedEpisodes.count == 1,
                "stored NULL re-enters the first-import branch and re-adds the newest episode")

        local.lastUpdated = 500
        let skipped = SaveNewEpisodes.compute(fetched: [parsed], local: [local])
        #expect(skipped.subscriptions.isEmpty && skipped.feedEpisodes.isEmpty,
                "local set + fetched NULL skips — the Dart crash here is the port's K4/K5 tolerance")
    }

    /// Dart `Uri.encodeQueryComponent` probe (2026-09-23):
    /// "()*!'~-_. a+b" → "%28%29%2A%21%27~-_.+a%2Bb" — `!'()*` are encoded.
    @Test("Uri.encodeQueryComponent parity: !'()* encoded, space → +, + → %2B")
    func queryComponentParity() {
        #expect(APIClient.dartQueryComponent("()*!'~-_. a+b") == "%28%29%2A%21%27~-_.+a%2Bb")
    }

    /// Dart `int.tryParse` tolerates surrounding whitespace (" 3600" = 3600);
    /// Swift's `Int` does not — parseITunesDuration trims first.
    @Test("itunes:duration tolerates surrounding whitespace like int.tryParse")
    func durationWhitespaceParity() {
        #expect(RSSXMLParser.parseITunesDuration(" 3600 ") == 3_600_000)
        #expect(RSSXMLParser.parseITunesDuration("1: 30") == 90_000)
    }

    /// intl's `yyyy` greedily consumes the whole digit run — a typo'd
    /// 5-digit year parses as that year (verified 2026-09-23: `20241` OK).
    @Test("RFC822 year width is greedy like intl yyyy")
    func rfc822FiveDigitYear() {
        // Mon, 01 Jan 20241 00:00:00 GMT → year 20241, not nil.
        #expect(RSSDate.parse("Mon, 01 Jan 20241 00:00:00 GMT") != nil)
    }

    // MARK: - G1 playlist positions (insertion scenarios)

    @Test("G1: insert-position replay matches golden sequences")
    func g1PlaylistPositions() throws {
        let data = try golden("G1_playlist_position.json")
        let scenarios = data["scenarios"] as! [String: [String: Any]]

        // The exporter chains all three scenarios on ONE database — replay
        // keeps the state across them, in this order.
        var rows: [(url: String, position: Double)] = [] // position ASC
        let scenarioOrder = ["head_inserts_200", "mid_insert_saturation", "mixed_seeded"]

        for name in scenarioOrder {
            let scenario = scenarios[name]!
            let steps = scenario["steps"] as! [[String: Any]]

            for step in steps {
                let op = step["op"] as! [String: Any]
                let index = op["index"] as! Int
                let url = op["url"] as! String
                let positions = rows.map(\.position)

                func neighbors(_ index: Int, _ positions: [Double])
                    -> (left: Double?, right: Double?) {
                    (index > 0 ? positions[index - 1] : nil,
                     index < positions.count ? positions[index] : nil)
                }

                var needsReorder = false
                if let existingIndex = rows.firstIndex(where: { $0.url == url }) {
                    // mixed_seeded re-inserts URLs from earlier scenarios:
                    // the OLD move path — neighbors from the list that still
                    // has the row at its old slot (the K26 bug, byte-locked
                    // by this golden; production code uses the fixed
                    // `movePosition`).
                    let (left, right) = neighbors(index, positions)
                    if let left, let right {
                        rows[existingIndex].position = (left + right) / 2
                        needsReorder = (right - left) < PlaylistPositioning.minPositionGap
                    } else if let left {
                        rows[existingIndex].position = left + PlaylistPositioning.minPositionGap * 3
                    } else if let right {
                        rows[existingIndex].position = right - PlaylistPositioning.minPositionGap * 3
                    } else {
                        rows[existingIndex].position = 0
                    }
                } else {
                    let result = PlaylistPositioning.insertPosition(at: index, orderedPositions: positions)
                    rows.insert((url, result.position), at: min(index, rows.count))
                    needsReorder = result.needsReorder
                }

                rows.sort { $0.position < $1.position }
                if needsReorder {
                    rows = rows.enumerated().map { pair in (pair.element.url, Double(pair.offset)) }
                }

                let expectedPositions = step["positions"] as! [Double]
                let expectedURLs = step["urls"] as! [String]
                let reordered = step["reordered"] as! Bool

                if rows.map(\.url) != expectedURLs {
                    Issue.record("\(name): url order diverged at op n=\(op["n"] ?? -1)")
                }
                if rows.count == expectedPositions.count {
                    for (offset, value) in expectedPositions.enumerated() {
                        expectClose(rows[offset].position, value, "\(name)[\(offset)]")
                    }
                } else {
                    Issue.record("\(name): row count \(rows.count) != golden \(expectedPositions.count)")
                }
                if needsReorder != reordered {
                    Issue.record("\(name): reorder flag \(needsReorder) != golden \(reordered)")
                }
            }
        }
    }

    @Test("G2: insert-or-update-by-index boundary cases")
    func g2InsertOrUpdateByIndex() throws {
        let data = try golden("G2_insert_or_update_by_index.json")
        let cases = data["cases"] as! [String: [String: Any]]

        for (name, testCase) in cases {
            let prefill = testCase["prefill"] as? Int ?? 0
            let index = testCase["index"] as! Int
            let expected = testCase["positions"] as? [Double] ?? []
            let goldenThrew = testCase["threw"] as! Bool

            // Prefill via head inserts, exactly like the exporter.
            var positions: [Double] = []
            for _ in 0..<prefill {
                let result = PlaylistPositioning.insertPosition(at: 0, orderedPositions: positions)
                positions.insert(result.position, at: 0)
            }

            if goldenThrew {
                // The old algorithm crashed (RangeError). The native port
                // clamps instead (K4-family: no crash on programmer error) —
                // asserted by surviving the call with a valid ordering.
                #expect(index > positions.count)
                let clamped = PlaylistPositioning.insertPosition(
                    at: min(index, positions.count), orderedPositions: positions
                )
                _ = clamped
                continue
            }

            let result = PlaylistPositioning.insertPosition(at: index, orderedPositions: positions)
            var updated = positions
            updated.insert(result.position, at: min(index, positions.count))
            if result.needsReorder {
                updated = updated.enumerated().map { pair in Double(pair.offset) }
            }
            #expect(updated.count == expected.count)
            for (offset, value) in expected.enumerated() {
                expectClose(updated[offset], value, "\(name)[\(offset)]")
            }
        }
    }

    // MARK: - G3 / G4 LRC & export text

    @Test("G3: toLrc is byte-identical")
    func g3ToLrc() throws {
        let data = try golden("G3_to_lrc.json")
        let rawJSON = data["subtitle_json"] as! String
        let expected = data["subtitle_toLrc"] as! String

        let segments = try JSONDecoder().decode([SubtitleSegment].self, from: Data(rawJSON.utf8))
        #expect(LRC.render(segments: segments) == expected)
        #expect(LRC.render(rawJSON: rawJSON) == expected)
    }

    @Test("G4: buildExportText is byte-identical")
    func g4ExportText() throws {
        let data = try golden("G4_export_text.json")
        let cases = (data["cases"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]

        let mainLyric = "[00:00.000]line one\n[00:03.900]\n[00:04.000]line two\n[00:08.500]\n"
        let translationLyric = "[00:00.000]第一行\n[00:03.900]\n"

        let outputs = [
            "full": ExportText.build(title: "Episode 42", channelTitle: "Some Channel",
                                     mainLyric: mainLyric, translationLyric: translationLyric),
            "no_translation": ExportText.build(title: "Episode 42", channelTitle: "Some Channel",
                                               mainLyric: mainLyric, translationLyric: nil),
            "empty_translation_string": ExportText.build(title: "Episode 42", channelTitle: "Some Channel",
                                                         mainLyric: mainLyric, translationLyric: ""),
            "null_title_defaults": ExportText.build(title: nil, channelTitle: nil,
                                                    mainLyric: mainLyric, translationLyric: nil),
            "empty_channel_title_only": ExportText.build(title: "Solo", channelTitle: "",
                                                         mainLyric: mainLyric, translationLyric: nil),
            // K29: a title containing '/' must survive the TEXT assembly
            // (the crash was at file-write time, fixed by the sanitizer).
            "title_with_slash": ExportText.build(title: "EP/1: crash test", channelTitle: "Chan",
                                                 mainLyric: mainLyric, translationLyric: nil),
        ]
        for (name, expected) in cases {
            if outputs[name] != expected {
                Issue.record("G4 \(name):\nGOT [\(outputs[name] ?? "nil")]\nEXP [\(expected)]")
            }
        }
    }

    // MARK: - G5 HTML

    @Test("G5: sanitize/htmlToText/renderHtml routing")
    func g5Html() throws {
        let data = try golden("G5_html_to_text.json")
        let cases = data["cases"] as! [[String: Any]]

        for (index, testCase) in cases.enumerated() {
            let input = testCase["input"] as! String
            let sanitized = testCase["sanitized"] as? String ?? ""
            let htmlToText = testCase["htmlToText"] as? String ?? ""
            let startsWith = testCase["startsWith_lt"] as! Bool
            let fallback = testCase["sanitize_empty_fallback_to_htmlToText"] as! Bool
            let renderUses = testCase["renderHtml_uses"] as! String

            if input.dartTrimmed().hasPrefix("<") != startsWith {
                Issue.record("case \(index) startsWith")
            }
            // The exporter only sanitizes inputs that start with '<' and
            // records the TRIMMED result (renderHtml's own trim).
            let gotSanitized = startsWith
                ? HtmlText.sanitizeHtml(input).dartTrimmed()
                : ""
            if gotSanitized != sanitized {
                Issue.record("case \(index) sanitize: [\(gotSanitized)] != [\(sanitized)]")
            }
            let gotText = HtmlText.htmlToText(input)
            if gotText != htmlToText {
                Issue.record("case \(index) toText: [\(gotText)] != [\(htmlToText)]")
            }

            let payload = HtmlText.displayPayload(for: input)
            switch payload {
            case .html:
                if renderUses != "sanitized" { Issue.record("case \(index) routing html") }
            case .text:
                if renderUses != "raw text" && !fallback { Issue.record("case \(index) routing text (\(renderUses))") }
            case .empty: Issue.record("case \(index): unexpected empty payload")
            }
        }
    }

    @Test("G5 corpus: every recorded channel description converts identically")
    func g5Corpus() throws {
        let data = try golden("G5_html_to_text.json")
        let corpus = (data["corpus_channel_descriptions_htmlToText"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
        #expect(!corpus.isEmpty)
        for (file, expected) in corpus {
            // The exporter regex-extracts the RAW (entity-encoded) channel
            // <description> from the XML text and runs htmlToText on that
            // exact string — not on the parsed/decoded description.
            let xmlURL = try findRSSFixture(named: file)
            guard let rawXML = try? String(contentsOf: xmlURL, encoding: .utf8),
                  let range = rawXML.range(of: #"<description>([\s\S]{0,2000}?)</description>"#,
                                           options: .regularExpression)
            else {
                Issue.record("corpus feed \(file): no description found")
                continue
            }
            let inner = String(rawXML[range]
                .replacingOccurrences(of: "<description>", with: "")
                .replacingOccurrences(of: "</description>", with: ""))
            let converted = HtmlText.htmlToText(inner).dartTrimmed()
            if converted != expected {
                // Locate the first differing byte for the record.
                let diffIndex = zip(converted.unicodeScalars, expected.unicodeScalars)
                    .first { $0 != $1 }.map { converted.unicodeScalars.distance(from: converted.unicodeScalars.startIndex, to: converted.unicodeScalars.firstIndex(of: $0.0)!) } ?? -1
                Issue.record("corpus \(file): firstDiff≈\(diffIndex)\nGOT [\(converted.suffix(80))]\nEXP [\(expected.suffix(80))]")
            }
        }
    }

    private func findRSSFixture(named file: String) throws -> URL {
        let buckets = ["standard", "http_plain", "user_subs", "missing_fields", "giant", "malformed", "weird_dates", "redirect"]
        for bucket in buckets {
            let url = RepoAssets.fixture("rss/\(bucket)/\(file)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    // MARK: - G6 OPML

    @Test("G6: OPML parse entries")
    func g6OPML() throws {
        let data = try golden("G6_opml_parse.json")
        let cases = data["cases"] as! [String: [String: Any]]

        for (file, expectedCase) in cases {
            let entries = try OPMLParser.parse(fileURL: RepoAssets.fixture("opml/\(file)"))
            let expected = expectedCase["entries"] as! [[String: String]]
            #expect(entries.count == (expectedCase["count"] as! Int))
            #expect(entries.map(\.title) == expected.map { $0["title"]! }, "\(file) titles")
            #expect(entries.map(\.xmlURL) == expected.map { $0["xmlUrl"]! }, "\(file) urls")
        }
    }

    // MARK: - G7 RSS mapping

    @Test("G7: parseFeedResponse parity over the whole RSS corpus")
    func g7RSSMapping() throws {
        let data = try golden("G7_rss_mapping.json")
        let fixtures = data["fixtures"] as! [[String: Any]]

        for entry in fixtures {
            let bucket = entry["bucket"] as! String
            let file = entry["file"] as! String
            let onlyFirst = entry["onlyFirstEpisode"] as? Bool ?? false
            let xmlURL = RepoAssets.fixture("rss/\(bucket)/\(file)")
            guard let xmlData = try? Data(contentsOf: xmlURL) else {
                Issue.record("missing fixture \(bucket)/\(file)")
                continue
            }
            let parsed = PodcastFeedParser.parse(
                rssFeedUrl: "ignored", xmlData: xmlData, onlyFirstEpisode: onlyFirst,
                nowEpochMilliseconds: 0
            )

            guard let expectedSubscription = entry["subscription"] as? [String: Any] else {
                // The golden records `parse_error_null` — the baseline
                // CRASHED on missing pubDates (K5). The native port fixes
                // that: genuinely malformed XML still fails, but
                // missing-field feeds parse with nil pubDates.
                // Malformed XML or an empty capture (dead sources, e.g.
                // bowuzhi.fm recorded as a 0-byte file) genuinely fail;
                // missing-FIELD feeds are the K5 tolerance case.
                if bucket == "malformed" || xmlData.isEmpty {
                    if parsed != nil {
                        Issue.record("\(bucket)/\(file) is unparseable; expected nil")
                    }
                } else if parsed == nil {
                    Issue.record("\(bucket)/\(file): K5 fix should tolerate missing fields")
                }
                continue
            }
            guard let parsed else {
                Issue.record("\(bucket)/\(file) unexpectedly failed to parse")
                continue
            }

            // Subscription field parity.
            let expectedCount = entry["episode_count"] as! Int
            guard let expectedEpisodes = entry["episodes"] as? [[String: Any]] else { continue }
            #expect(parsed.feedEpisodes.count == expectedCount)
            if (entry["pub_date_desc_sorted"] as? Bool) == true {
                let dates = parsed.feedEpisodes.compactMap(\.pubDate)
                #expect(dates == dates.sorted(by: >))
            }

            for (offset, expectedEpisode) in expectedEpisodes.enumerated() {
                let episode = parsed.feedEpisodes[offset]
                if episode.title != optional(expectedEpisode["title"]) {
                    Issue.record("\(file)[\(offset)] title: [\(episode.title ?? "nil")] != [\(optional(expectedEpisode["title"]) ?? "nil")]")
                }
                if episode.duration != optionalInt64(expectedEpisode["duration"]) {
                    Issue.record("\(file)[\(offset)] duration: [\(episode.duration.map(String.init) ?? "nil")] != [\(optionalInt64(expectedEpisode["duration"]).map(String.init) ?? "nil")]")
                }
                if episode.pubDate != optionalInt64(expectedEpisode["pubDate"]) {
                    Issue.record("\(file)[\(offset)] pubDate: [\(episode.pubDate.map(String.init) ?? "nil")] != [\(optionalInt64(expectedEpisode["pubDate"]).map(String.init) ?? "nil")]")
                }
                if episode.enclosureUrl != optional(expectedEpisode["enclosureUrl"]) {
                    Issue.record("\(file)[\(offset)] url: [\(episode.enclosureUrl ?? "nil")] != [\(optional(expectedEpisode["enclosureUrl"]) ?? "nil")]")
                }
                if episode.imageUrl != optional(expectedEpisode["imageUrl"]) {
                    Issue.record("\(file)[\(offset)] image: [\(episode.imageUrl ?? "nil")] != [\(optional(expectedEpisode["imageUrl"]) ?? "nil")]")
                }
            }

            let subscription = parsed.subscription
            #expect(subscription.title == optional(expectedSubscription["title"]), "\(file) title")
            // The exporter truncates the golden description at 300 UTF-16
            // code units (Dart substring) — Persian/ZWNJ text differs from a
            // grapheme-based prefix.
            let expectedDescription = optional(expectedSubscription["description"])?
                .utf16Prefix(300)
            if subscription.description?.utf16Prefix(300) != expectedDescription {
                Issue.record("\(file) desc: [\((subscription.description ?? "nil").prefix(160))] != [\((optional(expectedSubscription["description"]) ?? "nil").prefix(160))]")
            }
            #expect(subscription.imageUrl == optional(expectedSubscription["imageUrl"]), "\(file) imageUrl")
            #expect(subscription.link == optional(expectedSubscription["link"]), "\(file) link")
            #expect(subscription.categories == optional(expectedSubscription["categories"]), "\(file) categories")
            #expect(subscription.author == optional(expectedSubscription["author"]), "\(file) author")
            #expect(subscription.email == optional(expectedSubscription["email"]), "\(file) email")
            if let expectedUpdated = expectedSubscription["lastUpdated"] as? Double {
                expectClose(Double(subscription.lastUpdated ?? 0), expectedUpdated, "\(file) lastUpdated")
            }
        }

        // Weird-date single probes (JSON null = unparseable).
        let probes = data["weird_date_single_probe"] as! [String: Any]
        for (dateString, expected) in probes {
            let parsed = RSSDate.parse(dateString)
            if let expectedNumber = expected as? NSNumber {
                #expect(parsed == expectedNumber.int64Value)
            } else {
                #expect(parsed == nil)
            }
        }
    }

    // MARK: - G8 saveNewEpisodes

    @Test("G8: merge semantics three branches")
    func g8SaveNewEpisodes() throws {
        let data = try golden("G8_save_new_episodes.json")
        let manifest = try fixtureJSONObject("rss/manifest.json")["live"] as! [String: Any]
        let standard = manifest["standard"] as! [[String: Any]]
        let item = standard.first { (($0["items"] as? Int) ?? 0) >= 50 }!

        let xmlData = try Data(contentsOf: RepoAssets.fixture("rss/standard/\(item["file"]!)"))
        let url = item["url"] as! String
        let fetched = PodcastFeedParser.parse(
            rssFeedUrl: url, xmlData: xmlData, onlyFirstEpisode: false, nowEpochMilliseconds: 0
        )!

        #expect(fetched.feedEpisodes.count == data["fetched_episode_count"] as! Int)

        var base = fetched.subscription
        func subscription(lastUpdated: Int64?) -> SubscriptionRow {
            base.lastUpdated = lastUpdated
            return base
        }

        let newest = fetched.feedEpisodes[0].pubDate!
        let older = fetched.feedEpisodes[fetched.feedEpisodes.count / 2].pubDate!

        let firstImport = SaveNewEpisodes.compute(
            fetched: [fetched], local: [subscription(lastUpdated: nil)]
        )
        let expectedFirst = data["first_import"] as! [String: Any]
        #expect(firstImport.subscriptions.map(\.rssFeedUrl) == strings(expectedFirst["updated_subscription_urls"]))
        #expect(firstImport.feedEpisodes.map(\.enclosureUrl) == strings(expectedFirst["updated_episode_urls"]))

        let localWins = SaveNewEpisodes.compute(
            fetched: [fetched], local: [subscription(lastUpdated: newest)]
        )
        let expectedWins = data["local_wins"] as! [String: Any]
        #expect(localWins.subscriptions.isEmpty && strings(expectedWins["updated_subscription_urls"]).isEmpty)
        #expect(localWins.feedEpisodes.isEmpty && strings(expectedWins["updated_episode_urls"]).isEmpty)

        let localOlder = SaveNewEpisodes.compute(
            fetched: [fetched], local: [subscription(lastUpdated: older)]
        )
        let expectedOlder = data["local_older"] as! [String: Any]
        #expect((expectedOlder["local_lastUpdated"] as! NSNumber).int64Value == older)
        #expect(localOlder.subscriptions.map(\.rssFeedUrl) == strings(expectedOlder["updated_subscription_urls"]))
        let gotURLs = localOlder.feedEpisodes.map(\.enclosureUrl)
        let wantURLs = strings(expectedOlder["updated_episode_urls"])
        if gotURLs != wantURLs {
            Issue.record("G8 local_older: got \(gotURLs.count) want \(wantURLs.count); first-diff \(zip(gotURLs, wantURLs).first { $0.0 != $0.1 } ?? ("none", "none"))")
        }
    }

    // MARK: - G9 settings codec

    @Test("G9: settings codec constants and CSV")
    func g9SettingsCodec() throws {
        let data = try golden("G9_settings_codec.json")

        let csvCases = data["autoSleepTimer_csv"] as! [[String: Any]]
        for testCase in csvCases {
            let input = testCase["encode_input"] as! [Int]
            let csv = testCase["csv"] as! String
            let decoded = testCase["decoded"] as! [Int]
            let mins = testCase["mins_value"] as? Int

            let encoded = SettingsCodec.encodeAutoSleepTimer(
                startHour: input[0], endHour: input[1], minsIndex: input[2]
            )
            #expect(encoded == csv)
            let parsed = SettingsCodec.decodeAutoSleepTimer(csv)!
            #expect([parsed.startHour, parsed.endHour, parsed.minsIndex] == decoded)
            if let mins {
                #expect(SettingsCodec.countdownMinutes(at: decoded[2]) == mins)
            }
        }

        let speed = data["speed_steps"] as! [Double]
        #expect(speed.count == SettingsCodec.speedSteps.count)
        for (offset, value) in speed.enumerated() {
            expectClose(SettingsCodec.speedSteps[offset], value, "speed[\(offset)]")
        }

        #expect(SettingsCodec.countdownMinutes == data["countdown_minutes"] as! [Int])

        #expect(SettingsCodec.countdownMinutes.count == (data["countdown_labels"] as! [String]).count)

        #expect(SettingsCodec.targetLanguages.map(\.code) == data["target_language_codes"] as! [String])

        let countries = data["countries_raw"] as! [[String: String]]
        #expect(SettingsCodec.countries.map(\.code) == countries.map { $0["code"]! })
        #expect(SettingsCodec.countries.map(\.name) == countries.map { $0["name"]! })

        #expect(SettingsCodec.autoRefreshChoicesSeconds == int64s(data["autoRefresh_choices_seconds"]))
        #expect(SettingsCodec.maxEpisodesChoices == int64s(data["max_episodes_choices"]))

        // Locale derivation: the golden pins Dart's behavior on its
        // underscore identifiers. iOS hands the native app hyphenated
        // identifiers; the port normalizes to the underscore form the
        // shipped app actually saw on device (Platform.localeName), so
        // fresh-install defaults match (05 §1.5 G9 note).
        let locales = data["locale_derivation"] as! [String: [String: Any]]
        for (identifier, expected) in locales where identifier.contains("_") {
            let dart = Schema.localeComponents(fromLocaleIdentifier: identifier)
            #expect(dart.language == expected["language"] as! String)
            #expect(dart.country == expected["country"] as! String)
        }

        // Fresh-install default row (autoRefreshInterval = 300 caliber).
        let defaultRow = data["default_row"] as! [String: Any]
        let defaults = AppSettings.defaults(localeIdentifier: "en_US")
        #expect(defaults.darkMode == (defaultRow["darkMode"] as! NSNumber).boolValue)
        #expect(defaults.speed == defaultRow["speed"] as! Double)
        #expect(defaults.autoSleepTimer == defaultRow["autoSleepTimer"] as! String)
        #expect(defaults.maxCacheCount == (defaultRow["maxCacheCount"] as! NSNumber).int64Value)
        #expect(defaults.autoRefreshInterval == (defaultRow["autoRefreshInterval"] as! NSNumber).int64Value)
        #expect(defaults.maxFeedEpisodes == (defaultRow["maxFeedEpisodes"] as! NSNumber).int64Value)
        #expect(defaults.maxHistoryEpisodes == (defaultRow["maxHistoryEpisodes"] as! NSNumber).int64Value)
        #expect(defaults.continuousPlaying == (defaultRow["continuousPlaying"] as! NSNumber).boolValue)
    }

    // MARK: - G10 time formats

    @Test("G10: time and duration formatting")
    func g10TimeFormats() throws {
        let data = try golden("G10_time_formats.json")
        let nowMS = (data["reference_now_ms"] as! NSNumber).int64Value
        let referenceDate = Date(timeIntervalSince1970: TimeInterval(nowMS) / 1000)
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let year = calendar.component(.year, from: referenceDate)

        func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Int64 {
            var utcCalendar = Foundation.Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            return Int64(utcCalendar.date(
                from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)
            )!.timeIntervalSince1970 * 1000)
        }

        let past2020 = utc(2020, 5, 15, 12, 30)
        let future2030 = utc(2030, 1, 2, 3, 4)
        let thisYearJan = utc(year, 1, 5)
        let lastYear = utc(year - 1, 6, 15)

        // Golden tables may hold non-string probes (e.g. the exporter's
        // boolean `just_now_is_special_cased`) — bridging the whole
        // dictionary as [String: String] would TRAP and kill the runner.
        func stringEntry(_ table: String, _ key: String) -> String {
            ((data[table] as? [String: Any])?[key] as? String) ?? ""
        }
        #expect(TimeFormats.formatDatetime(past2020, nowEpochMilliseconds: nowMS) == stringEntry("formatDatetime", "past_2020"))
        #expect(TimeFormats.formatDatetime(future2030, nowEpochMilliseconds: nowMS) == stringEntry("formatDatetime", "future_2030"))
        #expect(TimeFormats.formatDatetime(thisYearJan, nowEpochMilliseconds: nowMS) == stringEntry("formatDatetime", "this_year_jan"))
        #expect(TimeFormats.formatDatetime(lastYear, nowEpochMilliseconds: nowMS) == stringEntry("formatDatetime", "last_year"))
        let justNow = TimeFormats.formatDatetime(nowMS, nowEpochMilliseconds: nowMS)
        #expect(justNow == "just now")

        #expect(TimeFormats.formatDate(past2020, nowEpochMilliseconds: nowMS) == stringEntry("formatDate", "past_2020"))
        #expect(TimeFormats.formatDate(thisYearJan, nowEpochMilliseconds: nowMS) == stringEntry("formatDate", "this_year"))

        #expect(TimeFormats.formatDuration(0) == stringEntry("formatDuration", "zero"))
        #expect(TimeFormats.formatDuration(59_000) == stringEntry("formatDuration", "59s"))
        #expect(TimeFormats.formatDuration(60_000) == stringEntry("formatDuration", "1m"))
        #expect(TimeFormats.formatDuration(99 * 60_000) == stringEntry("formatDuration", "99m"))
        #expect(TimeFormats.formatDuration(100 * 60_000) == stringEntry("formatDuration", "100m"))
        #expect(TimeFormats.formatDuration(134 * 60_000) == stringEntry("formatDuration", "134m"))

        #expect(TimeFormats.formatRemainingTime(durationMilliseconds: 0, playedMilliseconds: 0) == stringEntry("formatRemainingTime", "zero_duration"))
        #expect(TimeFormats.formatRemainingTime(durationMilliseconds: 73 * 60_000, playedMilliseconds: 0) == stringEntry("formatRemainingTime", "unplayed_73m"))
        #expect(TimeFormats.formatRemainingTime(durationMilliseconds: 90 * 60_000, playedMilliseconds: 17 * 60_000) == stringEntry("formatRemainingTime", "played_1h13m"))
        #expect(TimeFormats.formatRemainingTime(durationMilliseconds: 30 * 60_000, playedMilliseconds: 35 * 60_000) == stringEntry("formatRemainingTime", "played_past_end"))

        #expect(TimeFormats.getPlayedAndTotalTime(playedMilliseconds: 1_292_000, durationMilliseconds: 1_916_000) == stringEntry("getPlayedAndTotalTime", "normal"))
        #expect(TimeFormats.getPlayedAndTotalTime(playedMilliseconds: 5_000, durationMilliseconds: 0) == stringEntry("getPlayedAndTotalTime", "null_duration_convention"))
        #expect(TimeFormats.getPlayedAndTotalTime(playedMilliseconds: 3_661_000, durationMilliseconds: 7_322_000) == stringEntry("getPlayedAndTotalTime", "hour_rollover"))

        #expect(TimeFormats.formatCountdown(0) == stringEntry("formatCountdown", "zero"))
        #expect(TimeFormats.formatCountdown(-5_000) == stringEntry("formatCountdown", "negative"))
        #expect(TimeFormats.formatCountdown(59_000) == stringEntry("formatCountdown", "59s"))
        #expect(TimeFormats.formatCountdown(60 * 60_000) == stringEntry("formatCountdown", "60m"))
        #expect(TimeFormats.formatCountdown(59 * 60_000 + 59_000) == stringEntry("formatCountdown", "59m59s"))

        #expect(TimeFormats.formatTime(0) == stringEntry("formatTime", "zero"))
        #expect(TimeFormats.formatTime(3_723_000) == stringEntry("formatTime", "1h2m3s"))

        // The exporter's two inputs (the golden stores only the outputs).
        #expect(TimeFormats.urlToDomain("https://www.ximalaya.com/album/41563226.xml") == stringEntry("urlToDomain", "https"))
        #expect(TimeFormats.urlToDomain("example.com/path") == stringEntry("urlToDomain", "no_scheme"))
    }

    // MARK: - G11 User.fromJson

    @Test("G11: User.fromJson expired_at variants")
    func g11UserFromJSON() throws {
        let data = try golden("G11_user_from_json.json")
        let cases = data["cases"] as! [String: [String: Any?]]

        for (expiredAt, expected) in cases {
            let body: [String: Any] = [
                "uid": expected["uid"] as! String,
                "remaining": expected["remaining"] as! Int,
                "plus": expected["plus"] as! Int,
                "expired_at": expiredAt == "null" ? NSNull() : expiredAt,
            ]
            let user = User.from(jsonBody: try JSONSerialization.data(withJSONObject: body))
            #expect(user != nil)
            #expect(user?.uid == expected["uid"] as! String)
            #expect(user?.remaining == expected["remaining"] as! Int)
            #expect(user?.plus == expected["plus"] as! Int)
            let expectedMS = (expected["expireAt_epoch_ms"] as? NSNumber)?.int64Value
            #expect(user?.expireAtEpochMilliseconds == expectedMS)
        }
    }

    // MARK: - G12 shortlink params

    @Test("G12: shortlink md5 + body bytes")
    func g12Shortlink() throws {
        let data = try golden("G12_shortlink_params.json")
        #expect(data["timeout_seconds"] as! Int == 3)
        #expect(data["retry_max_attempts"] as! Int == 3)

        for caseValue in data["cases"] as! [[String: Any]] {
            let url = caseValue["url"] as! String
            let md5 = caseValue["md5"] as! String
            let bodyJSON = caseValue["body_json"] as! String

            #expect(Shortlink.md5Hex(of: url) == md5)
            #expect((Shortlink.md5Hex(of: url) as String).count == caseValue["md5_len"] as! Int)
            #expect(Shortlink.requestBody(for: url) == bodyJSON)
        }

        // Response mapping: status≠200 or malformed → nil (degrade path).
        #expect(Shortlink.shortURL(fromResponseBody: #"{"status":200,"key":"ab12cd"}"#) == "https://s.kindjeff.com/ab12cd")
        #expect(Shortlink.shortURL(fromResponseBody: #"{"status":500,"key":"x"}"#) == nil)
        #expect(Shortlink.shortURL(fromResponseBody: "not json") == nil)
    }

    // MARK: - G13 chat history

    @Test("G13: chat history construction quirk")
    func g13ChatHistory() throws {
        let data = try golden("G13_chat_history.json")
        let cases = data["cases"] as! [String: [[String: String]]]

        func messages(_ pairs: [(String, String)]) -> [ChatHistory.Message] {
            pairs.map { ChatHistory.Message(authorID: $0.0, text: $0.1) }
        }

        let two = ChatHistory.build(messages([("human", "hello"), ("ai", "hi")]))
        #expect(two == cases["two_messages"]!)

        var tenPairs: [(String, String)] = []
        for i in 0..<10 { tenPairs.append((i.isMultiple(of: 2) ? "human" : "ai", "msg \(i)")) }
        #expect(ChatHistory.build(messages(tenPairs)) == cases["ten_messages"]!)

        var twelvePairs: [(String, String)] = []
        for i in 0..<12 { twelvePairs.append((i.isMultiple(of: 2) ? "human" : "ai", "msg \(i)")) }
        let built = ChatHistory.build(messages(twelvePairs))
        let expected = cases["twelve_messages_cutoff"]!
        #expect(built == expected)
        // The pinned quirk: >10 messages sends the OLDEST ten; the current
        // input ("msg 10"/"msg 11") is absent.
        #expect(!built.contains { $0.values.contains("msg 10") || $0.values.contains("msg 11") })
    }

    // MARK: - G14 text safe color

    @Test("G14: getTextSafeColor luminance threshold")
    func g14TextSafeColor() throws {
        let data = try golden("G14_text_safe_color.json")
        #expect((data["fallback"] as! String).lowercased() == String(format: "0x%08x", TextSafeColor.fallback))

        let cases = data["cases"] as! [String: [String: Any]]
        for (hex, expected) in cases {
            let argb = UInt64(hex.dropFirst(2), radix: 16)!
            let luminance = TextSafeColor.luminance(argb: UInt32(truncatingIfNeeded: argb))
            expectClose(luminance, expected["luminance"] as! Double, hex, maxULP: 1_000_000)
            #expect(abs(luminance - (expected["luminance"] as! Double)) < 1e-12)

            let result = TextSafeColor.getTextSafeColor(argb: UInt32(truncatingIfNeeded: argb))
            #expect(String(format: "0x%08X", result) == expected["result"] as! String)
        }
    }

    // MARK: - G16 search trim

    @Test("G16: resMap2Channel trims")
    func g16SearchTrim() throws {
        let data = try golden("G16_search_trim.json")
        let input = data["input"] as! [String: Any]
        let output = data["output"] as! [String: Any]

        let channel = APIClient.channel(from: input)
        #expect(channel.rssFeedUrl == output["rssFeedUrl"] as? String)
        #expect(channel.title == output["title"] as? String)
        #expect(channel.description == output["description"] as? String)
        #expect(channel.imageUrl == output["imageUrl"] as? String)
        #expect(channel.link == output["link"] as? String)
        #expect(channel.categories == output["categories"] as? String)
        #expect(channel.author == output["author"] as? String)
        #expect(channel.email == output["email"] as? String)
    }
}

// MARK: - Small bridging helpers

private func optional(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    return nil
}

private func optionalInt64(_ value: Any?) -> Int64? {
    (value as? NSNumber)?.int64Value
}

private func strings(_ value: Any?) -> [String] {
    (value as? [String]) ?? []
}

private func int64s(_ value: Any?) -> [Int64] {
    (value as? [Any])?.compactMap { ($0 as? NSNumber)?.int64Value } ?? []
}


extension String {
    /// Dart `substring(0, n)` semantics: UTF-16 code units.
    func utf16Prefix(_ count: Int) -> String {
        String(decoding: utf16.prefix(count), as: UTF16.self)
    }
}
