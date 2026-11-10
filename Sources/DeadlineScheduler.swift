import AppKit
import UserNotifications
import Combine

final class DeadlineScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var permission = "正在检查系统提醒…"
    @Published var schedulingError: String?
    private let center = UNUserNotificationCenter.current()
    private var latest: [Note] = []
    private var generation = 0
    private var running = false
    var isReconciling: Bool { running }
    var onIdle: (() -> Void)?
    func refreshLatest() { refreshPermission();reconcile(latest) }
    var openFocus:(()->Void)?
    var openNote: ((UUID) -> Void)?
    var now: () -> Date = { Date() }
    override init() { super.init(); center.delegate = self; refreshPermission() }
    func refreshPermission() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { self.permission = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional ? "系统提醒已开启" : settings.authorizationStatus == .denied ? "系统提醒未开启 · 可在系统设置中允许" : "系统提醒未开启 · 启用后申请权限" }
        }
    }
    // Invoked only after an explicit in-app reminder toggle is successfully saved.
    func requestPermission() {
        center.requestAuthorization(options:[.alert,.sound]) { _, error in
            DispatchQueue.main.async {
                if let error { self.schedulingError = error.localizedDescription }
                self.refreshPermission(); self.reconcile(self.latest)
            }
        }
    }
    func reconcile(_ notes: [Note]) {
        latest = notes; generation += 1
        guard !running else { return }
        running = true
        Task { @MainActor in
            while true {
                let version = generation
                let snapshot = latest
                let settings = await center.notificationSettings()
                let pending = await center.pendingNotificationRequests()
                let delivered = await center.deliveredNotifications()
                if version != generation { continue }
                let plans = snapshot.flatMap { ReminderPlan.requests(for:$0,now:now()) }
                let desired = Dictionary(uniqueKeysWithValues:plans.map { ($0.id,$0) })
                let stale = pending.filter { $0.identifier.hasPrefix("radish.") && desired[$0.identifier] == nil }.map(\.identifier)
                center.removePendingNotificationRequests(withIdentifiers:stale)
                let obsolete = delivered.filter { notification in
                    let id = notification.request.identifier
                    guard id.hasPrefix("radish.") else { return false }
                    guard let raw = notification.request.content.userInfo["noteID"] as? String, let uuid = UUID(uuidString:raw), let note = snapshot.first(where:{$0.id==uuid}) else { return true }
                    if note.completed || !note.reminderEnabled || note.dueAt == nil { return true }
                    let expected=ReminderPlan.requests(for:note,now:.distantPast).first(where:{$0.id==id})
                    return expected?.fingerprint != notification.request.content.userInfo["fingerprint"] as? String
                }.map { $0.request.identifier }
                center.removeDeliveredNotifications(withIdentifiers:obsolete)
                if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                    for plan in plans {
                        if generation != version { break }
                        if pending.contains(where: { $0.identifier == plan.id && $0.content.userInfo["fingerprint"] as? String == plan.fingerprint }) { continue }
                        // Never replay expired nodes, including after wake or a delayed async callback.
                        guard plan.fireAt > now() else { continue }
                        let content=UNMutableNotificationContent();content.title=plan.id.hasSuffix(".advance") ? "便签快到时间了" : "便签到时间了"
                        content.body=plan.title; if plan.sound { content.sound = .default }
                        content.userInfo=["noteID":plan.noteID.uuidString,"fingerprint":plan.fingerprint,"dueAt":snapshot.first(where:{$0.id==plan.noteID})!.dueAt!.timeIntervalSince1970]
                        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
                        var components=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:plan.fireAt)
                        components.timeZone=TimeZone(secondsFromGMT:0)
                        let trigger=UNCalendarNotificationTrigger(dateMatching:components,repeats:false)
                        do { try await center.add(UNNotificationRequest(identifier:plan.id,content:content,trigger:trigger)); schedulingError=nil }
                        catch { schedulingError=error.localizedDescription }
                    }
                }
                if generation == version { break }
            }
            running=false; refreshPermission();let callback=onIdle;onIdle=nil;callback?()
        }
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping(UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.list,.sound])
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping()->Void) {
        if response.notification.request.content.userInfo["kind"] as? String == "focus" { DispatchQueue.main.async { self.openFocus?() } }
        if let raw=response.notification.request.content.userInfo["noteID"] as? String,let id=UUID(uuidString:raw) { DispatchQueue.main.async { self.openNote?(id) } }
        completionHandler()
    }
}
