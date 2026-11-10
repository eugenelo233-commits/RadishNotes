import AppKit
import CoreText

struct Handwriting: Identifiable {
    let id: String
    let name: String
    let postScript: String?
}
enum FontBook {
    static let chinese = [Handwriting(id:"default",name:"跟随默认",postScript:nil), Handwriting(id:"wenkai",name:"霞鹜文楷 GB",postScript:"LXGWWenKaiGB-Regular"), Handwriting(id:"yozai",name:"悠哉手写 · Medium",postScript:"Yozai-Medium"), Handwriting(id:"system",name:"系统字体",postScript:nil)]
    static let latin = [Handwriting(id:"default",name:"跟随默认",postScript:nil), Handwriting(id:"caveat",name:"Caveat",postScript:"Caveat-Regular"), Handwriting(id:"kalam",name:"Kalam",postScript:"Kalam-Regular"), Handwriting(id:"patrick",name:"Patrick Hand",postScript:"PatrickHand-Regular"), Handwriting(id:"system",name:"系统字体",postScript:nil)]
    static var registrationErrors: [String] = []
    static func register(in directory: URL? = nil) {
        guard let folder = directory ?? Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys:nil)) ?? [] where url.pathExtension == "ttf" {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error), let e = error?.takeRetainedValue() {
                registrationErrors.append("\(url.lastPathComponent): \(e)")
            }
        }
    }
    static func resolved(_ id: String, chinese: Bool) -> String {
        let value = id == "default" ? AppPreferences.defaults.string(forKey: chinese ? "defaultChineseFont" : "defaultLatinFont") ?? (chinese ? "wenkai" : "caveat") : id
        return chinese && value == "chenyu" ? "yozai" : value
    }
    static func font(_ id: String, size: Double, chinese isChinese: Bool) -> NSFont {
        let resolved = resolved(id, chinese:isChinese)
        let entries = isChinese ? chinese : latin
        guard let ps = entries.first(where: { $0.id == resolved })?.postScript, let font = NSFont(name:ps,size:size) else { return .systemFont(ofSize:size) }
        return font
    }
    static func isChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x2E80...0xA4CF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value) || (0x20000...0x323AF).contains($0.value) }
    }
    static func supports(_ text: String, font: NSFont) -> Bool {
        let chars = Array(text.utf16); var glyphs = Array<CGGlyph>(repeating:0,count:chars.count)
        return CTFontGetGlyphsForCharacters(font as CTFont, chars, &glyphs, chars.count)
    }
    static func font(for text: String, note: Note) -> NSFont {
        let cjk = isChinese(text)
        if text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return NSFont(name:"AppleColorEmoji",size:note.fontSize) ?? .systemFont(ofSize:note.fontSize) }
        let preferred = font(cjk ? note.chineseFont : note.latinFont, size:note.fontSize, chinese:cjk)
        if supports(text,font:preferred) || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return preferred }
        if cjk { let fallback = font("wenkai",size:note.fontSize,chinese:true); if supports(text,font:fallback) { return fallback } }
        return .systemFont(ofSize:note.fontSize)
    }
    static func style(_ storage: NSTextStorage, note: Note, range: NSRange? = nil) {
        let string = storage.string as NSString
        let target = range ?? NSRange(location:0,length:string.length)
        guard target.length > 0 else { return }
        let ink = (Ink(rawValue:note.ink) ?? .charcoal).color.withAlphaComponent(note.completed ? 0.82 : 1)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor,value:ink,range:target)
        var offset = target.location
        while offset < NSMaxRange(target) {
            let r = string.rangeOfComposedCharacterSequence(at:offset)
            let selected = font(for:string.substring(with:r),note:note)
            if (storage.attribute(.font,at:offset,effectiveRange:nil) as? NSFont) != selected { storage.addAttribute(.font,value:selected,range:r) }
            offset = NSMaxRange(r)
        }
        storage.endEditing()
    }
    static func attributed(_ text: String, note: Note) -> NSAttributedString {
        let storage = NSTextStorage(string:text); style(storage,note:note); return storage
    }
}
