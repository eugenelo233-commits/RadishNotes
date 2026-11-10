import AppKit
import Combine
import UserNotifications

final class FocusStore:NSObject,ObservableObject {
    @Published var state=FocusState()
    @Published var remaining:Double=1500
    @Published var message="我是小萝卜，陪你把一件事做好。"
    @Published var warning=false
    @Published var status="开始专注后，才会检查学习名单。"
    @Published var error:String?
    @Published var edgeStatus="仅识别当前域名，不读取网页正文"
    @Published var petTapped=false
    private let directory:URL
    private var timer:Timer?
    private var tracker=DistractionTracker()
    private var temporary=Set<String>()
    private var outsideKey:String?
    private var outsideName:String?
    private let edge=EdgeSiteReader()
    private var lastEdgeRead=Date.distantPast
    private var lastCheckpoint=Date.distantPast
    private var blocked=false
    private var notificationGeneration=0
    private var syncing=false
    var isReconciling:Bool { syncing }
    var onIdle:(()->Void)?
    private var warningToken:UUID?
    private var submittedWarning:UUID?
    var onShow:(()->Void)?
    var onChange:(()->Void)?
    init(directory:URL) {
        self.directory=directory;super.init()
        let file=directory.appendingPathComponent("focus.json")
        if FileManager.default.fileExists(atPath:file.path) {
            do {
                let loaded=try JSONDecoder().decode(FocusState.self,from:Data(contentsOf:file))
                guard loaded.valid else { throw NSError(domain:"Focus",code:1,userInfo:[NSLocalizedDescriptionKey:"番茄钟数据版本或字段无效，原文件已保留。"] ) }
                state=loaded
                if state.running { state.running=false;state.endAt=nil;message="上次计时已暂停，准备好后继续。" }
            } catch { blocked=true;self.error=error.localizedDescription }
        }
        remaining=state.remaining
        let center=NSWorkspace.shared.notificationCenter
        center.addObserver(self,selector:#selector(applicationActivated(_:)),name:NSWorkspace.didActivateApplicationNotification,object:nil)
        center.addObserver(self,selector:#selector(suspend),name:NSWorkspace.willSleepNotification,object:nil)
        center.addObserver(self,selector:#selector(suspend),name:NSWorkspace.sessionDidResignActiveNotification,object:nil)
        syncNotifications()
    }
    func save(_ value:FocusState)->Bool {
        guard !blocked else { return false }
        do {
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let path=directory.appendingPathComponent("focus.json")
            if let old=try? Data(contentsOf:path),(try? JSONDecoder().decode(FocusState.self,from:old))?.valid==true { try old.write(to:directory.appendingPathComponent("focus.backup.json"),options:.atomic) }
            try encoder.encode(value).write(to:path,options:.atomic);error=nil;return true
        } catch { self.error="番茄钟尚未保存：\(error.localizedDescription)";return false }
    }
    @discardableResult func change(_ body:(inout FocusState)->Void)->Bool {
        var next=state;body(&next);if next.running { next.remaining=next.remaining(at:Date()) };guard next.valid,save(next) else { return false };state=next;remaining=state.remaining(at:Date());onChange?();return true
    }
    func toggle() {
        if state.running { pause();return }
        guard change({$0.start(at:Date())}) else { return }
        message=state.phase == .focus ? "出发！这段时间只做好眼前这一件。" : "伸个懒腰，眼睛也休息一下。"
        tracker.clear();warning=false;lastCheckpoint=Date()
        timer?.invalidate();timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){ [weak self] _ in self?.tick() };timer?.tolerance=0.15
        if state.systemReminders {
            UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) { _,_ in DispatchQueue.main.async { self.syncNotifications() } }
        }
        syncNotifications();observeFront(force:true);RuntimeEvidence.focusEvent(self,"started")
    }
    func pause() {
        guard state.running else { return }
        guard change({$0.pause(at:Date())}) else { return }
        timer?.invalidate();timer=nil;clearWarning();status="计时暂停，不检查学习名单。";message="小萝卜替你守着，准备好再继续。";syncNotifications();RuntimeEvidence.focusEvent(self,"paused")
    }
    @objc func suspend() { pause() }
    func reset() {
        guard change({$0.reset()}) else { return };timer?.invalidate();timer=nil;clearWarning();temporary.removeAll();status="本轮已重置。";message="重新整理一下，再开始也没关系。";syncNotifications()
    }
    func skipBreak() { guard !state.running,state.phase != .focus else { return };_ = change{$0.phase = .focus;$0.reset()};message="准备下一颗番茄。" }
    func tick() {
        let now=Date();remaining=state.remaining(at:now)
        if remaining<=0 {
            let wasFocus=state.phase == .focus
            guard change({$0.finishIfDue(at:now)}) else { pause();return }
            timer?.invalidate();timer=nil;clearWarning();temporary.removeAll()
            message=wasFocus ? "长出一颗番茄！摸摸我，休息一下吧。" : "休息好了，下一件事慢慢来。"
            status=wasFocus ? "这一轮已完成，休息由你开始。" : "准备好后开始下一轮。";syncNotifications();RuntimeEvidence.focusEvent(self,"finished");return
        }
        if now.timeIntervalSince(lastCheckpoint)>=15 {
            var checkpoint=state;checkpoint.remaining=remaining
            if save(checkpoint) { lastCheckpoint=now }
        }
        guard state.phase == .focus,state.monitor else { status=state.phase == .focus ? "名单提醒已关闭。" : "休息时间，不检查应用。";return }
        observeFront(force:false)
        if tracker.shouldWarn(at:now,grace:state.graceSeconds) {
            warning=true;message="咦，离开学习名单一会儿了。我们回来继续吧？";warningToken=UUID();syncNotifications();RuntimeEvidence.focusEvent(self,"warning")
        }
    }
    @objc func applicationActivated(_ n:Notification) { guard state.running,state.phase == .focus,state.monitor else { return };observeFront(force:true) }
    func observeFront(force:Bool) {
        guard state.running,state.phase == .focus,state.monitor,let app=NSWorkspace.shared.frontmostApplication,let id=app.bundleIdentifier else { return }
        if id=="local.radishnotes.mac" {
            if !warning { tracker.update(.unknown("正在调整伙伴"),at:Date());status="正在调整伙伴，暂不判断分心。" }
            return
        }
        let name=app.localizedName ?? id
        if id=="com.microsoft.edgemac",state.edgeSites {
            if force { accept(.unknown("正在识别 Edge 网站…"),key:id) }
            if force || Date().timeIntervalSince(lastEdgeRead)>=4 {
                lastEdgeRead=Date()
                edge.read { [weak self] host,error in
                    guard let self,self.state.running,self.state.monitor,self.state.edgeSites,NSWorkspace.shared.frontmostApplication?.bundleIdentifier==id else { return }
                    self.edgeStatus=error ?? "已识别网站：\(host ?? "未知")"
                    self.accept(StudyRules.evaluate(appID:id,name:name,edgeHost:host,edgeError:error,state:self.state,temporary:self.temporary),key:host ?? id)
                }
            }
        } else { accept(StudyRules.evaluate(appID:id,name:name,edgeHost:nil,edgeError:nil,state:state,temporary:temporary),key:id) }
    }
    private func accept(_ verdict:StudyVerdict,key:String) {
        tracker.update(verdict,at:Date())
        switch verdict {
        case .allowed:
            if warning { message="欢迎回来，继续一点点推进。" };clearWarning(keepTracker:true);status="在学习名单内，小萝卜安心陪着你。"
        case .outside(let name):
            outsideKey=key;outsideName=name;status="当前：\(name) · 名单外超过 \(state.graceSeconds) 秒提醒"
        case .unknown(let reason): clearWarning(keepTracker:true);status=reason
        }
    }
    private func clearWarning(keepTracker:Bool=false) {
        let changed=warning || warningToken != nil
        warning=false;warningToken=nil
        if !keepTracker { tracker.clear() }
        if changed { syncNotifications() }
    }
    func allowThisSession() {
        guard let key=outsideKey else { return };temporary.insert(key);clearWarning();message="本轮放行 \(outsideName ?? "这个应用")。课程视频也可以安心看。";status="本轮临时放行，不修改永久名单。";RuntimeEvidence.focusEvent(self,"temporary-allowed")
    }
    func pet() {
        petTapped=true
        if warning { message="摸到啦！如果是在学习，点“本轮放行”告诉我。" }
        else { message=state.running ? "收到摸摸！我陪你再认真一小会儿。" : state.tomatoes>0 ? "今天已经收获 \(state.tomatoes) 颗番茄啦。" : "摸摸充电完毕，准备一起开始！" }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[weak self] in self?.petTapped=false}
    }
    func checkEdge() { edgeStatus="等待 Edge 自动化授权…";edge.read { [weak self] host,error in self?.edgeStatus=error ?? "识别成功：\(host ?? "无网页")" } }
    func updateMonitor() { clearWarning();lastEdgeRead = .distantPast;observeFront(force:true);syncNotifications() }
    func addApp(url:URL) {
        guard let bundle=Bundle(url:url),let id=bundle.bundleIdentifier else { return }
        let name=bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey:"CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        _ = change { if !$0.allowedApps.contains(where:{$0.id==id}) { $0.allowedApps.append(StudyApp(id:id,name:name)) } };updateMonitor()
    }
    func syncNotifications() {
        notificationGeneration += 1;guard !syncing else { return };syncing=true
        Task { @MainActor in
            let center=UNUserNotificationCenter.current()
            while true {
                let generation=notificationGeneration
                let snapshot=state;let token=warningToken
                let settings=await center.notificationSettings();let pending=await center.pendingNotificationRequests()
                if generation != notificationGeneration { continue }
                let permitted=snapshot.systemReminders && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                let end=snapshot.running ? snapshot.endAt : nil
                if !permitted || end==nil { center.removePendingNotificationRequests(withIdentifiers:["radishFocus.timer"]) }
                if !permitted || token==nil { center.removePendingNotificationRequests(withIdentifiers:["radishFocus.distraction"]);center.removeDeliveredNotifications(withIdentifiers:["radishFocus.distraction"]) }
                if permitted,let end,end>Date() {
                    let fingerprint="\(snapshot.sessionID)|\(Int64(end.timeIntervalSince1970))"
                    if !pending.contains(where:{$0.identifier=="radishFocus.timer" && $0.content.userInfo["fingerprint"] as? String==fingerprint}) {
                        let content=UNMutableNotificationContent();content.title=snapshot.phase == .focus ? "小萝卜：这一轮完成啦" : "小萝卜：休息结束啦";content.body="回到番茄伙伴，决定接下来做什么。";content.userInfo=["kind":"focus","fingerprint":fingerprint]
                        let trigger=UNTimeIntervalNotificationTrigger(timeInterval:max(1,end.timeIntervalSinceNow),repeats:false)
                        try? await center.add(UNNotificationRequest(identifier:"radishFocus.timer",content:content,trigger:trigger))
                    }
                }
                if permitted,let token,token != submittedWarning,generation==notificationGeneration {
                    let content=UNMutableNotificationContent();content.title="小萝卜等你回来";content.body="离开学习名单一会儿了。如果正在看课程，可以在伙伴中选择本轮放行。";content.userInfo=["kind":"focus"]
                    try? await center.add(UNNotificationRequest(identifier:"radishFocus.distraction",content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:1,repeats:false)));submittedWarning=token
                }
                if generation==notificationGeneration { break }
            }
            syncing=false;let callback=onIdle;onIdle=nil;callback?()
        }
    }
    func shutdown()->Bool {
        if blocked { return true }
        if state.running { pause() }
        return error==nil
    }
}
