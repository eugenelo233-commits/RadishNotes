// Opt-in local development evidence. Disabled without BOTH isolated data and capture directories.
// Captures only this app's own rendered views; never captures the user's desktop.
import AppKit
import UserNotifications

enum RuntimeEvidence {
    static var folder:URL? {
        let env=ProcessInfo.processInfo.environment
        guard env["RADISH_DATA_DIR"] != nil,let path=env["RADISH_CAPTURE_DIR"] else { return nil }
        let url=URL(fileURLWithPath:path);try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url
    }
    static var counter=0
    static func image(_ view:NSView)->NSImage? {
        view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return nil }
        view.cacheDisplay(in:view.bounds,to:rep)
        let result=NSImage(size:view.bounds.size);result.addRepresentation(rep);return result
    }
    static func save(_ image:NSImage,name:String) {
        guard let folder,let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else { return }
        try? data.write(to:folder.appendingPathComponent(name+".png"),options:.atomic)
    }
    static func event(_ c:NoteWindowController,_ phase:String) {
        guard let folder else { return };counter += 1
        let name=String(format:"gesture-%03d-",counter)+phase
        if let image=image(c.paper) { save(image,name:name) }
        let row:[String:Any]=["time":Date().timeIntervalSince1970,"id":c.id.uuidString,"phase":phase,"progress":c.paper.tearProgress,"distance":c.corner.gesture.distance,"active":c.corner.gesture.active,"ready":c.corner.gesture.ready,"completed":c.note.completed,"archived":c.note.archived,"revision":c.note.revision,"markedText":c.editor.hasMarkedText()]
        if let data=try? JSONSerialization.data(withJSONObject:row,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:folder.appendingPathComponent(name+".json")) }
    }
    static func notificationSnapshot(_ name:String) async {
        guard let folder else { return }
        let center=UNUserNotificationCenter.current();let pending=await center.pendingNotificationRequests();let delivered=await center.deliveredNotifications()
        let result:[String:Any]=["time":Date().timeIntervalSince1970,"pending":pending.map{["id":$0.identifier,"fingerprint":$0.content.userInfo["fingerprint"] ?? "","next":($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()?.timeIntervalSince1970 ?? 0]},"delivered":delivered.map{["id":$0.request.identifier,"date":$0.date.timeIntervalSince1970,"fingerprint":$0.request.content.userInfo["fingerprint"] ?? ""]}]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:folder.appendingPathComponent(name+".json")) }
    }
    static func focusEvent(_ focus:FocusStore,_ event:String) {
        guard let folder else {return}
        let row:[String:Any] = ["event":event,"time":Date().timeIntervalSince1970,"running":focus.state.running,"warning":focus.warning,"remaining":focus.remaining,"tomatoes":focus.state.tomatoes,"phase":focus.state.phase.rawValue,"status":focus.status]
        if let data=try? JSONSerialization.data(withJSONObject:row,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:folder.appendingPathComponent("focus-"+event+".json"))}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.15) {
            if let app=NSApp.delegate as? AppDelegate,let view=app.focusWindow?.window?.contentView,let picture=image(view) {save(picture,name:"pet-"+event)}
        }
        Task {@MainActor in await notificationSnapshot("focus-notifications-"+event)}
    }
    static func capture(_ app:AppDelegate) {
        guard let folder else { return }
        let controllers=app.store.notes.compactMap{app.controllers[$0.id]}
        let columns=3;let cell=NSSize(width:370,height:340)
        let rows=(controllers.count+columns-1)/columns
        let sheet=NSImage(size:NSSize(width:CGFloat(columns)*cell.width,height:CGFloat(max(1,rows))*cell.height+50))
        let images=controllers.map{image($0.paper)}
        sheet.lockFocus();NSColor(hex:0xE9E5DD).setFill();NSRect(origin:.zero,size:sheet.size).fill()
        ("萝卜便签 0.3.1 · 运行中窗口内容快照（隔离验收数据）" as NSString).draw(at:NSPoint(x:24,y:sheet.size.height-32),withAttributes:[.font:NSFont.systemFont(ofSize:16),.foregroundColor:NSColor.darkGray])
        for (i,c) in controllers.enumerated() {
            guard let picture=images[i] else { continue }
            let x=CGFloat(i%columns)*cell.width+20;let top=sheet.size.height-65-CGFloat(i/columns)*cell.height
            let ratio=min(1, min(330/picture.size.width,285/picture.size.height));let size=NSSize(width:picture.size.width*ratio,height:picture.size.height*ratio)
            picture.draw(in:NSRect(x:x,y:top-size.height,width:size.width,height:size.height))
            let label="\(c.note.chineseFont) / \(c.note.latinFont) · \(c.note.paperStyle)"
            (label as NSString).draw(at:NSPoint(x:x,y:top-size.height-23),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.darkGray])
        };sheet.unlockFocus();save(sheet,name:"runtime-comparison")
        for (i,c) in controllers.enumerated() { if let picture=images[i] { save(picture,name:"note-\(c.id.uuidString)") } }
        var details:[[String:Any]]=[]
        for c in controllers {
            var fonts=Set<String>();let storage=c.editor.textStorage!
            storage.enumerateAttribute(.font,in:NSRange(location:0,length:storage.length)){value,_,_ in if let font=value as? NSFont { fonts.insert(font.fontName) } }
            details.append(["id":c.id.uuidString,"fonts":fonts.sorted(),"level":c.window!.level.rawValue,"windowNumber":c.window!.windowNumber,"frame":NSStringFromRect(c.window!.frame),"marked":c.editor.hasMarkedText(),"selection":c.editor.selectedRange().description,"seed":String(c.note.textureSeed)])
        }
        if let view=app.focusWindow?.window?.contentView,let picture=image(view) {save(picture,name:"pet-runtime")}
        let data=try? JSONSerialization.data(withJSONObject:["time":Date().timeIntervalSince1970,"fontRegistrationErrors":FontBook.registrationErrors,"windows":details,"globalShortcut":app.shortcut.status,"appearance":AppPreferences.defaults.string(forKey:"paperAppearance") ?? "realistic","physics":app.physics.enabled,"focusRunning":app.focus.state.running,"focusWarning":app.focus.warning,"focusRemaining":app.focus.remaining],options:[.prettyPrinted,.sortedKeys]);try? data?.write(to:folder.appendingPathComponent("runtime-details.json"))
        Task { @MainActor in
            let center=UNUserNotificationCenter.current();let settings=await center.notificationSettings();let pending=await center.pendingNotificationRequests();let delivered=await center.deliveredNotifications()
            let result:[String:Any]=["time":Date().timeIntervalSince1970,"authorization":settings.authorizationStatus.rawValue,"pending":pending.map{["id":$0.identifier,"next":($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()?.timeIntervalSince1970 ?? 0]},"delivered":delivered.map{["id":$0.request.identifier,"date":$0.date.timeIntervalSince1970]}]
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:folder.appendingPathComponent("notifications.json")) }
        }
    }
}
