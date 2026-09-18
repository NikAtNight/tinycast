import Foundation

@main
@MainActor
struct TranscriptsTests {
    static var failures = 0
    static let sourceURL = URL(fileURLWithPath: "/synthetic/history/2026-09-18.md")
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func parse(_ text: String) -> [TranscriptEntry] {
        DictationHistoryParser.parse(text, sourceURL: sourceURL, calendar: calendar)
    }

    static func main() throws {
        dictations()
        try recordings()
        queries()
        print(failures == 0 ? "Transcript tests passed" : "\(failures) transcript tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func dictations() {
        expect(parse("").isEmpty, "an empty file has no entries")
        expect(parse("# Dictations 2026-09-18\n").isEmpty, "a header alone has no entries")
        let single = "# Dictations 2026-09-18\n\n## 09:15:30\nA synthetic dictation.\n"
        let entries = parse(single)
        expect(entries.count == 1, "one heading produces one entry")
        expect(entries.first?.text == "A synthetic dictation.", "outer blank lines are trimmed")
        expect(entries.first?.sourceURL == sourceURL, "the source URL is retained")
        expect(entries.first?.date == calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 18, hour: 9, minute: 15, second: 30)), "the heading supplies the timestamp")
        let multiple = single + "\n## 10:20:00\nFirst paragraph.\n\nSecond paragraph.\n"
        let many = parse(multiple)
        expect(many.count == 2, "headings separate dictations")
        expect(many.last?.text == "First paragraph.\n\nSecond paragraph.", "paragraph breaks survive")
        expect(many.first?.id == entries.first?.id, "appending does not change existing identity")
        expect(parse(multiple.replacingOccurrences(of: "\n", with: "\r\n")).map(\.text) == many.map(\.text),
               "CRLF headings and paragraphs parse")
        expect(parse(single.replacingOccurrences(of: "2026-09-18", with: "2026-02-30")).isEmpty,
               "impossible dates are rejected")
        expect(parse(single.replacingOccurrences(of: "09:15:30", with: "24:15:30")).isEmpty,
               "impossible times are rejected")
        expect(parse(single.replacingOccurrences(of: "# Dictations", with: "# Other")).isEmpty,
               "an unrelated Markdown file is ignored")
        expect(parse(single + "## invalid\nDiscard this body.\n").map(\.text) == entries.map(\.text),
               "malformed headings do not become text in the previous dictation")
        expect(parse(single + "## 09:15:30\nAnother entry.").map(\.id).count == 2,
               "two dictations within one second survive")
        expect(Set(parse(single + "## 09:15:30\nAnother entry.").map(\.id)).count == 2,
               "same-second dictations have distinct identities")
        var offset = calendar
        offset.timeZone = TimeZone(secondsFromGMT: 3_600)!
        let local = DictationHistoryParser.parse(single, sourceURL: sourceURL, calendar: offset)
        expect(local.first?.date == entries.first?.date.addingTimeInterval(-3_600),
               "the injected calendar controls time zone")
    }

    static func document(duration: String = "12.5", segments: String = "[]") -> Data {
        Data("""
        {"id":"synthetic-recording","title":"Planning notes","createdAt":"2026-09-18T09:00:00Z",
        "duration":\(duration),"segments":\(segments),"kind":"audio","status":"completed"}
        """.utf8)
    }

    static func recordings() throws {
        let url = URL(fileURLWithPath: "/synthetic/library/example/document.json")
        let empty = try ScribeDocumentDecoder.decode(document(), sourceURL: url)
        expect(empty.text.isEmpty && empty.segments.isEmpty, "an empty recording has no transcript")
        let segments = """
        [{"id":"one","text":"First sentence.","start":0,"end":4.5,"speaker":"Speaker 1"},
         {"id":"two","text":"Second paragraph.\\n\\nStill the second segment.","start":4.5,"end":12.5}]
        """
        let entry = try ScribeDocumentDecoder.decode(document(segments: segments), sourceURL: url)
        expect(entry.title == "Planning notes" && entry.duration == 12.5, "recording metadata decodes")
        expect(entry.segments.count == 2 && entry.segments[0].speaker == "Speaker 1",
               "segment timings and speakers decode")
        expect(entry.segments[1].speaker == nil, "a missing speaker is allowed")
        expect(entry.text == "First sentence.\nSecond paragraph.\n\nStill the second segment.",
               "the full transcript retains paragraphs and segment order")
        expect(entry.text(in: 0...0) == "First sentence.", "one segment can be copied")
        expect(entry.text(in: 0...1) == entry.text, "a segment range includes both endpoints")
        expect(entry.text(in: -1...0) == nil && entry.text(in: 1...2) == nil, "out-of-range segments are rejected")
        expect(empty.text(in: 0...0) == nil, "an empty transcript cannot copy a segment")
        let blank = try ScribeDocumentDecoder.decode(
            document(segments: "[{\"text\":\"  \",\"start\":0,\"end\":1}]"), sourceURL: url)
        expect(blank.text(in: 0...0) == nil, "a blank segment cannot trigger an empty copy")
        let invalid = [
            Data(), Data("{".utf8), Data("{}".utf8), document(duration: "-1"),
            document(duration: "1e308"),
            document(segments: "[{\"text\":\"Invalid\",\"start\":3,\"end\":2}]"),
            document(segments: "[{\"text\":\"Invalid\",\"start\":-1,\"end\":2}]"),
            document(segments: "[{\"text\":\"Invalid\"}]")
        ]
        for data in invalid {
            do {
                _ = try ScribeDocumentDecoder.decode(data, sourceURL: url)
                expect(false, "malformed documents and invalid ranges must throw")
            } catch {}
        }
    }

    static func queries() {
        let entries = parse("""
        # Dictations 2026-09-18
        ## 08:00:00
        Calendar
        ## 09:00:00
        Shopping list
        ## 10:00:00
        Calendar planning
        """)
        expect(TranscriptQuery.rank(entries, for: " ").map(\.text) ==
               ["Calendar planning", "Shopping list", "Calendar"], "blank queries show newest first")
        expect(TranscriptQuery.rank(entries, for: "calendar").first?.text == "Calendar", "exact matches rank first")
        expect(TranscriptQuery.rank(entries, for: "clndr").count == 2, "fuzzy subsequences match")
        expect(TranscriptQuery.rank(entries, for: "zzzz").isEmpty, "unmatched queries produce no rows")
        let tied = parse("# Dictations 2026-09-18\n## 09:00:00\nSame\n## 09:00:00\nSame")
        expect(TranscriptQuery.rank(tied, for: "Same").map(\.id) ==
               TranscriptQuery.rank(tied.reversed(), for: "Same").map(\.id), "ties have deterministic order")
        let body = parse("# Dictations 2026-09-18\n## 09:00:00\nTitle\n\nHidden keyword")
        expect(TranscriptQuery.rank(body, for: "keyword").count == 1, "search includes the full transcript")
        let large = parse("# Dictations 2026-09-18\n" + (0..<250).map {
            "## 09:00:00\nEntry \($0)\n"
        }.joined())
        expect(TranscriptQuery.rank(large, for: "").count == TranscriptQuery.resultLimit,
               "blank results obey the row limit")
        expect(TranscriptQuery.rank(large, for: "Entry").count == TranscriptQuery.resultLimit,
               "matching results obey the row limit")
    }
}
