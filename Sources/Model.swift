import AppKit

struct Note: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String = ""
    var color: String = "cream"
    var fontSize: Double = 19
    var x: Double = 120
    var y: Double = 180
    var width: Double = 240
    var height: Double = 230
    var screenID: UInt32? = nil
    var pinned: Bool = false
    var completed: Bool = false
    var archived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var chineseFont: String = "default"
    var latinFont: String = "default"
    var ink: String = "charcoal"
    var paperStyle: String = "fiber"
    var textureSeed: UInt64 = UInt64.random(in: 1...UInt64.max)
    var paperOriginAt: Date? = nil
    var agingEnabled: Bool = true
    var completedAt: Date? = nil
    var frozenPaperAge: Double? = nil
    var dueAt: Date? = nil
    var dueTimeZone: String? = nil
    var reminderEnabled: Bool = false
    var advanceMinutes: Int = 0
    var notificationSound: Bool = false
    var revision: Int = 0
    init() {}
    enum CodingKeys: String, CodingKey { case id, text, color, fontSize, x, y, width, height, screenID, pinned, completed, archived, createdAt, updatedAt, chineseFont, latinFont, ink, paperStyle, textureSeed, paperOriginAt, agingEnabled, completedAt, frozenPaperAge, dueAt, dueTimeZone, reminderEnabled, advanceMinutes, notificationSound, revision }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        color = try c.decode(String.self, forKey: .color)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        screenID = try c.decodeIfPresent(UInt32.self, forKey: .screenID)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        completed = try c.decode(Bool.self, forKey: .completed)
        archived = try c.decode(Bool.self, forKey: .archived)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        chineseFont = try c.decodeIfPresent(String.self, forKey: .chineseFont) ?? "default"
        latinFont = try c.decodeIfPresent(String.self, forKey: .latinFont) ?? "default"
        ink = try c.decodeIfPresent(String.self, forKey: .ink) ?? "charcoal"
        paperStyle = try c.decodeIfPresent(String.self, forKey: .paperStyle) ?? "fiber"
        textureSeed = try c.decodeIfPresent(UInt64.self, forKey: .textureSeed) ?? Self.seed(for: id)
        paperOriginAt = try c.decodeIfPresent(Date.self, forKey: .paperOriginAt)
        agingEnabled = try c.decodeIfPresent(Bool.self, forKey: .agingEnabled) ?? true
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        frozenPaperAge = try c.decodeIfPresent(Double.self, forKey: .frozenPaperAge)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        dueTimeZone = try c.decodeIfPresent(String.self, forKey: .dueTimeZone)
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        advanceMinutes = try c.decodeIfPresent(Int.self, forKey: .advanceMinutes) ?? 0
        notificationSound = try c.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? false
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
    static func seed(for id: UUID) -> UInt64 {
        id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    var frame: NSRect {
        get { NSRect(x: x, y: y, width: width, height: height) }
        set { x = newValue.minX; y = newValue.minY; width = newValue.width; height = newValue.height }
    }
    var paperStart: Date { paperOriginAt ?? createdAt }
    func paperAge(at now: Date) -> Double {
        if completed, let frozenPaperAge { return max(0, frozenPaperAge) }
        return max(0, now.timeIntervalSince(paperStart))
    }
    mutating func setCompleted(_ value: Bool, at now: Date) {
        guard completed != value else { return }
        if value { frozenPaperAge = paperAge(at: now); completedAt = now }
        else { frozenPaperAge = nil; completedAt = nil }
        completed = value
    }
    mutating func renewPaper(at now: Date) {
        paperOriginAt = now; textureSeed = UInt64.random(in: 1...UInt64.max)
        if completed { frozenPaperAge = 0 }
    }
}
struct NoteDocument: Codable {
    var schemaVersion = 2
    var notes: [Note] = []
}
enum Paper: String, CaseIterable {
    case cream, coral, sage, blue, lilac, ivory, warmWhite, apricot, grayBlue, kraft
    var title: String { ["cream":"奶油黄", "coral":"浅珊瑚", "sage":"鼠尾草绿", "blue":"雾蓝", "lilac":"淡丁香", "ivory":"米白", "warmWhite":"暖白", "apricot":"浅杏", "grayBlue":"淡灰蓝", "kraft":"浅牛皮色"][rawValue]! }
    var hex: UInt32 { ["cream":0xF5E6A9, "coral":0xF3C6BE, "sage":0xCFE0CB, "blue":0xCADDE6, "lilac":0xDED2E9, "ivory":0xEEE6D9, "warmWhite":0xF7F3E8, "apricot":0xF4D9B8, "grayBlue":0xDBE1E4, "kraft":0xDCC49F][rawValue]! }
    var color: NSColor { NSColor(hex: hex) }
}
extension NSColor {
    convenience init(hex: UInt32) { self.init(srgbRed: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, alpha: 1) }
}
enum Ink: String, CaseIterable {
    case charcoal, blue, brown
    var title: String { switch self { case .charcoal: return "炭黑"; case .blue: return "深蓝墨水"; case .brown: return "深棕" } }
    var color: NSColor { NSColor(hex: self == .charcoal ? 0x292D31 : self == .blue ? 0x243D54 : 0x493327) }
}
enum PaperMaterial: String, CaseIterable {
    case fiber, recycled, cotton
    var title: String { self == .fiber ? "纤维纸" : self == .recycled ? "再生纸" : "棉麻纸" }
}
enum DeadlineState: String {
    case none, distant, soon, urgent, overdue
    static func evaluate(_ note: Note, now: Date) -> DeadlineState {
        guard !note.completed, let due = note.dueAt else { return .none }
        let delta = due.timeIntervalSince(now)
        if delta <= 0 { return .overdue }
        if delta <= 30*60 { return .urgent }
        if delta <= 3*3600 { return .soon }
        return .distant
    }
}
struct ReminderPlan: Equatable {
    var id: String
    var noteID: UUID
    var fireAt: Date
    var title: String
    var fingerprint: String
    var sound: Bool
    static func requests(for note: Note, now: Date) -> [ReminderPlan] {
        guard note.reminderEnabled, !note.completed, let due = note.dueAt else { return [] }
        let title = String(note.text.split(separator: "\n").first ?? "便签到期了").prefix(80).description
        var nodes: [(String, Date)] = [("due", due)]
        if note.advanceMinutes > 0 { nodes.append(("advance", due.addingTimeInterval(-Double(note.advanceMinutes)*60))) }
        return nodes.filter { $0.1 > now }.map { kind, date in
            let id = "radish.\(note.id.uuidString).\(kind)"
            return ReminderPlan(id: id, noteID: note.id, fireAt: date, title: title,
                                fingerprint: "\(Int64(date.timeIntervalSince1970))|\(title)|\(note.notificationSound)", sound: note.notificationSound)
        }
    }
}
struct TearGesture {
    var distance: CGFloat = 0
    var active = false
    var cancelled = false
    mutating func begin() { active = true; cancelled = false; distance = 0 }
    mutating func update(dx: CGFloat, dy: CGFloat) {
        guard active, !cancelled else { return }
        distance = dx < -8 || dy < -8 ? 0 : max(0, (dx + dy) / sqrt(2))
    }
    var ready: Bool { active && !cancelled && distance >= 72 }
    var progress: CGFloat { max(0, min(1.4, (distance-8)/64)) }
    mutating func cancel() { active = false; cancelled = true; distance = 0 }
    mutating func release() -> Bool { let commit = ready; active = false; return commit }
}
enum Shape: String, CaseIterable {
    case strip, square, tall
    var title: String { switch self { case .strip: return "横条"; case .square: return "方形"; case .tall: return "竖条" } }
    var size: NSSize { switch self { case .strip: return NSSize(width: 330, height: 110); case .square: return NSSize(width: 240, height: 230); case .tall: return NSSize(width: 210, height: 320) } }
}
enum ScreenLayout {
    static let minimum = NSSize(width: 190, height: 100)
    static func fit(_ frame: NSRect, in screens: [NSRect]) -> NSRect {
        guard !screens.isEmpty else { return frame }
        let best = screens.max { a, b in
            let ai = a.intersection(frame); let bi = b.intersection(frame)
            return (ai.isNull ? 0 : ai.width * ai.height) < (bi.isNull ? 0 : bi.width * bi.height)
        }!
        let width = min(max(frame.width.isFinite ? frame.width : 240, minimum.width), best.width)
        let height = min(max(frame.height.isFinite ? frame.height : 230, minimum.height), best.height)
        return NSRect(x: min(max(frame.minX.isFinite ? frame.minX : best.minX, best.minX), best.maxX-width),
                      y: min(max(frame.minY.isFinite ? frame.minY : best.minY, best.minY), best.maxY-height), width: width, height: height)
    }
    static var frames: [NSRect] { NSScreen.screens.map(\.visibleFrame) }
    static var current: NSScreen? { NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main }
    static func id(_ screen: NSScreen?) -> UInt32? { (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

struct TearUndo {
    var before: Note
    var committedRevision: Int
}
final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var saveError: String?
    let directory: URL
    var file: URL { directory.appendingPathComponent("notes.json") }
    var backup: URL { directory.appendingPathComponent("notes.backup.json") }
    private var pending: DispatchWorkItem?
    private(set) var dirty = false
    private(set) var lastTear: TearUndo?
    private(set) var migrationSnapshot: URL?
    var onCommit: (([Note]) -> Void)?
    var beforeWrite: (() throws -> Void)? // Fault injection for isolated persistence tests.
    var blocked = false
    var now: () -> Date = { Date() }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RadishNotes", isDirectory: true)
    }
    func decode(_ data: Data) throws -> NoteDocument {
        let doc = try JSONDecoder().decode(NoteDocument.self, from: data)
        guard (1...2).contains(doc.schemaVersion) else { throw failure("数据版本不受支持，已停止写入。请使用对应版本的应用打开。") }
        guard Set(doc.notes.map(\.id)).count == doc.notes.count,
              doc.notes.allSatisfy({ $0.fontSize.isFinite && $0.fontSize >= 10 && $0.fontSize <= 40 && $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.height.isFinite && Paper(rawValue: $0.color) != nil && PaperMaterial(rawValue: $0.paperStyle) != nil && Ink(rawValue: $0.ink) != nil && [0,10,30,60].contains($0.advanceMinutes) && $0.revision >= 0 && ($0.frozenPaperAge == nil || $0.frozenPaperAge!.isFinite) }) else {
            throw failure("数据包含无效字段，原文件已保留。")
        }
        return doc
    }
    func failure(_ text: String) -> NSError { NSError(domain: "RadishNotes", code: 1, userInfo: [NSLocalizedDescriptionKey:text]) }
    func load() throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        do {
            let data = try Data(contentsOf: file)
            let doc = try decode(data)
            var converted = doc.notes
            if doc.schemaVersion == 1 {
                let instant = now()
                for i in converted.indices {
                    converted[i].paperOriginAt = converted[i].createdAt
                    if converted[i].completed { converted[i].frozenPaperAge = max(0, instant.timeIntervalSince(converted[i].createdAt)) }
                    // No completedAt is fabricated from updatedAt.
                }
                let snapshot = directory.appendingPathComponent("notes.schema1-before-v2-\(UUID().uuidString).json")
                try data.write(to: snapshot, options: .atomic); migrationSnapshot = snapshot
                try persist(converted)
            }
            notes = converted
            return true
        } catch { blocked = true; saveError = error.localizedDescription; throw error }
    }
    func update(_ id: UUID, immediate: Bool = false, _ body: (inout Note) -> Void) {
        guard !blocked, let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var changedNote = notes[i]; body(&changedNote)
        changedNote.updatedAt = now(); changedNote.revision += 1; notes[i] = changedNote
        changed(immediate: immediate)
    }
    func changed(immediate: Bool = false) {
        dirty = true; pending?.cancel()
        if immediate { _ = flush() }
        else {
            let job = DispatchWorkItem { [weak self] in _ = self?.flush() }
            pending = job; DispatchQueue.main.asyncAfter(deadline: .now()+0.35, execute: job)
        }
    }
    private func persist(_ values: [Note]) throws {
        try beforeWrite?()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(NoteDocument(notes: values))
        if let old = try? Data(contentsOf: file), (try? decode(old)) != nil { try old.write(to: backup, options: .atomic) }
        try data.write(to: file, options: .atomic)
    }
    @discardableResult func flush() -> Bool {
        pending?.cancel(); pending = nil
        guard !blocked else { return false }
        guard dirty else { return true }
        do {
            try persist(notes); dirty = false
            if saveError != nil { saveError = nil }
            onCommit?(notes); return true
        } catch { saveError = error.localizedDescription; return false }
    }
    // Transactional commands publish state and notify the scheduler only after durable success.
    @discardableResult func transaction(_ id: UUID, _ body: (inout Note) -> Void) -> Bool {
        guard !blocked, flush(), let i = notes.firstIndex(where: { $0.id == id }) else { return false }
        var values = notes; body(&values[i]); values[i].revision = notes[i].revision + 1; values[i].updatedAt = now()
        do {
            try persist(values); notes = values; dirty = false
            if saveError != nil { saveError = nil }; onCommit?(notes); return true
        } catch { saveError = error.localizedDescription; return false }
    }
    @discardableResult func tear(_ id: UUID) -> Bool {
        guard flush(), let before = notes.first(where: { $0.id == id }), !before.archived else { return false }
        let date = now()
        guard transaction(id, { $0.setCompleted(true, at: date); $0.archived = true }) else { return false }
        lastTear = TearUndo(before: before, committedRevision: before.revision + 1); return true
    }
    var canUndoTear: Bool {
        guard let undo = lastTear, let n = notes.first(where: { $0.id == undo.before.id }) else { return false }
        return n.revision == undo.committedRevision
    }
    @discardableResult func undoTear() -> Bool {
        guard let undo = lastTear, canUndoTear else { return false }
        guard transaction(undo.before.id, { $0 = undo.before }) else { return false }
        lastTear = nil; return true
    }
    func recoverBackup() throws {
        _ = try decode(Data(contentsOf: backup))
        let copy = directory.appendingPathComponent("notes.damaged-\(UUID().uuidString).json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: file, to: copy) }
        try Data(contentsOf: backup).write(to: file, options: .atomic)
        blocked = false; _ = try load(); saveError = nil; dirty = false; onCommit?(notes)
    }
}
