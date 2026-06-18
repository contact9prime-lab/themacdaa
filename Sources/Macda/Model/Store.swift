import Foundation

/// Tiny JSON-file store under ~/Library/Application Support/Macda.
/// Plenty for this scale; swap for SQLite/GRDB if the data grows.
final class Store {
    private let dir: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let custom = Settings.load().customDataDirectory
        if !custom.isEmpty {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
                .appendingPathComponent("Macda", isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            dir = base.appendingPathComponent("Macda", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// The folder where all Macda data lives (notes, meetings, recordings…).
    var baseDirectory: URL { dir }

    /// Folder where session audio chunks are written (1-day retention).
    var recordingsDir: URL {
        let r = dir.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: r, withIntermediateDirectories: true)
        return r
    }

    /// Delete recordings older than `maxAge` seconds (default 24h).
    func cleanupOldRecordings(maxAge: TimeInterval = 86_400) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: recordingsDir,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in files {
            let mdate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mdate, mdate < cutoff { try? fm.removeItem(at: url) }
        }
    }

    /// Delete the oldest recordings until total size is under `maxBytes`.
    func enforceStorageCap(maxBytes: Int64) {
        guard maxBytes > 0 else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: recordingsDir,
                                                      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        else { return }
        var infos = files.map { url -> (url: URL, date: Date, size: Int64) in
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (url, v?.contentModificationDate ?? .distantPast, Int64(v?.fileSize ?? 0))
        }
        var total = infos.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        infos.sort { $0.date < $1.date }            // oldest first
        for info in infos where total > maxBytes {
            try? fm.removeItem(at: info.url)
            total -= info.size
        }
    }

    /// Total size of retained recordings, for display.
    func recordingsByteSize() -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: recordingsDir,
                                                      includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    private func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }

    func loadMeetings() -> [Meeting] { load("meetings.json", as: [Meeting].self) ?? [] }
    func saveMeetings(_ m: [Meeting]) { save(m, to: "meetings.json") }

    func loadNotes() -> [NoteItem] { load("notes.json", as: [NoteItem].self) ?? [] }
    func saveNotes(_ n: [NoteItem]) { save(n, to: "notes.json") }

    func loadTodos() -> [TodoItem] { load("todos.json", as: [TodoItem].self) ?? [] }
    func saveTodos(_ t: [TodoItem]) { save(t, to: "todos.json") }

    func loadChat() -> [ChatMessage] { load("chat.json", as: [ChatMessage].self) ?? [] }
    func saveChat(_ c: [ChatMessage]) { save(c, to: "chat.json") }

    func loadPeople() -> [Person] { load("people.json", as: [Person].self) ?? [] }
    func savePeople(_ p: [Person]) { save(p, to: "people.json") }

    func loadPendingVoices() -> [PendingVoice] { load("pending_voices.json", as: [PendingVoice].self) ?? [] }
    func savePendingVoices(_ v: [PendingVoice]) { save(v, to: "pending_voices.json") }
}
