import Foundation

struct StudyApp:Codable,Identifiable,Equatable {
    var id:String
    var name:String
}
enum FocusPhase:String,Codable { case focus,shortBreak,longBreak
    var title:String { self == .focus ? "专注" : self == .shortBreak ? "短休息" : "长休息" }
}
struct FocusState:Codable,Equatable {
    var schemaVersion=1
    var phase=FocusPhase.focus
    var running=false
    var remaining:Double=25*60
    var endAt:Date?
    var focusMinutes=25
    var breakMinutes=5
    var longBreakMinutes=15
    var tomatoes=0
    var sessionID=UUID()
    var allowedApps=[StudyApp(id:"notion.id",name:"Notion"),StudyApp(id:"com.openai.codex",name:"ChatGPT"),StudyApp(id:"com.openai.chat",name:"ChatGPT（兼容标识）"),StudyApp(id:"com.electron.lark",name:"飞书 / Lark")]
    var domains=["notion.so","notion.site","chatgpt.com","chat.openai.com","feishu.cn","larksuite.com"]
    var monitor=true
    var edgeSites=true
    var graceSeconds=30
    var systemReminders=true
    var pinned=true
    var color="sage"
    var material="cotton"
    var textureSeed:UInt64=31618
    var frame:String?
    var seconds:Double { Double((phase == .focus ? focusMinutes : phase == .shortBreak ? breakMinutes : longBreakMinutes)*60) }
    func remaining(at now:Date)->Double { running ? max(0,(endAt ?? now).timeIntervalSince(now)) : remaining }
    mutating func start(at now:Date) { guard !running else { return };if remaining<=0 { remaining=seconds };running=true;endAt=now.addingTimeInterval(remaining) }
    mutating func pause(at now:Date) { remaining=remaining(at:now);running=false;endAt=nil }
    mutating func reset() { running=false;endAt=nil;remaining=seconds;sessionID=UUID() }
    @discardableResult mutating func finishIfDue(at now:Date)->Bool {
        guard running,remaining(at:now)<=0 else { return false }
        if phase == .focus { tomatoes += 1;phase=tomatoes%4==0 ? .longBreak : .shortBreak }
        else { phase = .focus }
        running=false;endAt=nil;remaining=seconds;sessionID=UUID();return true
    }
    var valid:Bool {
        schemaVersion==1 && (1...120).contains(focusMinutes) && (1...60).contains(breakMinutes) && (1...60).contains(longBreakMinutes) && remaining.isFinite && remaining>=0 && remaining<=7200 && tomatoes>=0 && (5...300).contains(graceSeconds)
    }
}
enum StudyVerdict:Equatable { case allowed,outside(String),unknown(String) }
enum StudyRules {
    static func cleanHost(_ value:String)->String? {
        let trimmed=value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        let url=URL(string:trimmed.contains("://") ? trimmed : "https://"+trimmed)
        guard let host=url?.host?.lowercased(),!host.isEmpty,!host.contains(" ") else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }
    static func allowed(host:String,domains:[String])->Bool {
        guard let h=cleanHost(host) else { return false }
        return domains.compactMap(cleanHost).contains { h==$0 || h.hasSuffix("."+$0) }
    }
    static func evaluate(appID:String,name:String,edgeHost:String?,edgeError:String?,state:FocusState,temporary:Set<String>=[])->StudyVerdict {
        if appID=="local.radishnotes.mac" { return .allowed }
        if appID=="com.microsoft.edgemac" && state.edgeSites {
            if let error=edgeError { return .unknown(error) }
            guard let host=edgeHost else { return .unknown("正在识别 Edge 网站…") }
            if allowed(host:host,domains:state.domains) || temporary.contains(host) { return .allowed }
            return .outside(host)
        }
        if state.allowedApps.contains(where:{$0.id==appID}) || temporary.contains(appID) { return .allowed }
        return .outside(name)
    }
}
struct DistractionTracker {
    var since:Date?
    var warned=false
    var current:StudyVerdict = .allowed
    mutating func update(_ verdict:StudyVerdict,at now:Date) {
        current=verdict
        if case .outside=verdict { if since==nil { since=now } }
        else { since=nil;warned=false }
    }
    mutating func shouldWarn(at now:Date,grace:Int)->Bool {
        guard case .outside=current,let since,!warned,now.timeIntervalSince(since)>=Double(grace) else { return false }
        warned=true;return true
    }
    mutating func clear() { since=nil;warned=false;current = .allowed }
}
