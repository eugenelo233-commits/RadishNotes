import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = NoteStore(directory: ProcessInfo.processInfo.environment["RADISH_DATA_DIR"].map { URL(fileURLWithPath: $0) })
    let scheduler = DeadlineScheduler()
    lazy var physics=PaperPhysics(app:self)
    lazy var focus=FocusStore(directory:store.directory)
    let shortcut=GlobalShortcut()
    var focusWindow:FocusWindow?
    var now: () -> Date = { Date() }
    var timeTimer: Timer?
    var inspectorWindows: [String:NSWindow] = [:]
    var toast: UndoToast?
    var controllers: [UUID: NoteWindowController] = [:]
    var status: NSStatusItem!
    var hidden = false
    var lastArchived: UUID?
    var archiveWindow: NSWindow?
    var settingsWindow: NSWindow?
    var observer: AnyCancellable?
    var errorShown = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FontBook.register()
        store.now = { [weak self] in self?.now() ?? Date() }
        scheduler.now = { [weak self] in self?.now() ?? Date() }
        store.onCommit = { [weak self] notes in self?.scheduler.reconcile(notes) }
        scheduler.openNote = { [weak self] id in
            guard let self, let n=self.store.notes.first(where:{$0.id==id}) else { return }
            if n.archived { self.restore(id) } else { if self.hidden { self.toggleVisibility() }; self.controllers[id]?.show(focus:true) }
        }
        shortcut.action={ [weak self] in self?.createNote(nil) }
        scheduler.openFocus={ [weak self] in self?.showFocus() }
        _ = focus
        setupMenus()
        do {
            if try !store.load() {
                var note = newNote(shape: .square)
                note.text = "今天，慢慢做好。\n\n写下最想完成的一件事。\n拖动纸条上沿，自由摆放。\n右上角 ··· 可以换色、置顶。\n\n菜单栏的萝卜，随时添一张。"
                note.width = 285; note.height = 280
                store.notes = [note]; store.changed(immediate: true)
            }
            restoreWindows()
        } catch {
            let alert = NSAlert(); alert.messageText = "便签数据暂时无法读取"
            alert.informativeText = "原文件已保留，应用已停止写入，避免覆盖你的便签。\n\(error.localizedDescription)\n\n可尝试恢复最近有效备份，或打开数据文件夹。"
            alert.addButton(withTitle: "从备份恢复"); alert.addButton(withTitle: "打开数据文件夹"); alert.addButton(withTitle: "暂不处理")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do { try store.recoverBackup(); restoreWindows() } catch { showError("备份也无法读取：\(error.localizedDescription)") }
            case .alertSecondButtonReturn: openData()
            default: break
            }
        }
        if !store.blocked {
            if RuntimeEvidence.folder != nil {
                Task { @MainActor in await RuntimeEvidence.notificationSnapshot("startup-before-reconcile");scheduler.reconcile(store.notes) }
            } else { scheduler.reconcile(store.notes) }
        }
        timeTimer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in self?.refreshTime() }
        timeTimer?.tolerance = 15
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(refreshTime),name:NSWorkspace.didWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshTime),name:NSApplication.didBecomeActiveNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshTime),name:NSNotification.Name.NSSystemClockDidChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(appearanceChanged),name:UserDefaults.didChangeNotification,object:nil)
        observer = store.$saveError.receive(on: RunLoop.main).sink { [weak self] error in
            guard let self else { return }
            self.status.button?.title = error == nil ? "" : "!"
            self.status.button?.toolTip = error == nil ? "萝卜便签" : "萝卜便签：保存失败，点击查看"
            for c in self.controllers.values { c.apply() }
            if error != nil && !self.errorShown && !self.store.blocked {
                self.errorShown = true
                self.showError("便签暂未保存到磁盘，请保留应用运行。\n\(error!)\n可从菜单栏重试保存，或导出应急副本。")
            }
            if error == nil { self.errorShown = false }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(rescue), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    func restoreWindows() {
        for n in store.notes where !n.archived {
            let c = NoteWindowController(note: n, app: self); controllers[n.id] = c; c.show()
            c.captureFrame()
        }
        store.flush()
    }
    func newNote(shape: Shape) -> Note {
        var n = Note(); n.color = AppPreferences.defaults.string(forKey: "defaultColor") ?? "cream"
        let f = AppPreferences.defaults.double(forKey: "defaultFont"); n.fontSize = f == 0 ? 19 : f
        n.paperStyle = AppPreferences.defaults.string(forKey:"defaultPaperStyle") ?? "fiber"
        n.ink = AppPreferences.defaults.string(forKey:"defaultInk") ?? "charcoal"
        if AppPreferences.defaults.bool(forKey:"randomPaper") { randomize(&n) }
        n.width = shape.size.width; n.height = shape.size.height
        if let screen = ScreenLayout.current {
            let v = screen.visibleFrame; let offset = CGFloat(controllers.count % 7) * 22
            n.frame = ScreenLayout.fit(NSRect(x: v.midX-n.width/2+offset, y: v.midY-n.height/2-offset, width: n.width, height: n.height), in: [v])
            n.screenID = ScreenLayout.id(screen)
        }
        return n
    }
    func randomize(_ note:inout Note) {
        let prefs=AppPreferences.defaults
        let previous=PaperChoice(color:prefs.string(forKey:"lastRandomColor") ?? note.color,material:prefs.string(forKey:"lastRandomMaterial") ?? note.paperStyle)
        var random=SystemRandomNumberGenerator();let choice=PaperChoice.random(after:previous,using:&random)
        note.color=choice.color;note.paperStyle=choice.material;prefs.set(choice.color,forKey:"lastRandomColor");prefs.set(choice.material,forKey:"lastRandomMaterial")
    }
    @objc func createRandomNote() { createNote("random") }
    @objc func createNote(_ sender: Any?) {
        guard !store.blocked else { showError("数据读取失败期间不能新建，请先恢复数据。"); return }
        let raw = (sender as? NSMenuItem)?.representedObject as? String ?? AppPreferences.defaults.string(forKey: "defaultShape") ?? "square"
        var n = newNote(shape: Shape(rawValue: raw) ?? .square)
        if sender as? String == "random",!AppPreferences.defaults.bool(forKey:"randomPaper") { randomize(&n) }
        store.notes.append(n); store.changed(immediate: true)
        if hidden { toggleVisibility() }
        let c = NoteWindowController(note: n, app: self); controllers[n.id] = c; c.show(focus: true)
    }
    func bringForward(_ id: UUID) {
        guard !store.blocked, let index = store.notes.firstIndex(where: { $0.id == id }), index != store.notes.count-1 else { return }
        var ordered = store.notes; let n = ordered.remove(at: index); ordered.append(n); store.notes = ordered; store.changed()
    }
    func archive(_ id: UUID) {
        guard !store.blocked else { return }
        physics.stop()
        guard controllers[id]?.prepareTear() != false, store.transaction(id, { $0.archived = true }) else { return }
        controllers[id]?.window?.orderOut(nil)
        controllers.removeValue(forKey: id)
        lastArchived = id
    }
    func restore(_ id: UUID) {
        guard let n = store.notes.first(where: { $0.id == id }), n.archived, !store.blocked else { return }
        guard store.transaction(id, { $0.archived = false; $0.frame = ScreenLayout.fit($0.frame, in: ScreenLayout.frames) }) else { return }
        if hidden { toggleVisibility() }
        let updated = store.notes.first { $0.id == id }!
        let c = NoteWindowController(note: updated, app: self); controllers[id] = c; c.show(focus: true)
        if lastArchived == id { lastArchived = nil }
    }
    @objc func undoArchive() { if let id = lastArchived { restore(id) } }
    @objc func closeCurrent() {
        if let c = controllers.values.first(where: { $0.window?.isKeyWindow == true }) { archive(c.id) }
        else { NSApp.keyWindow?.close() }
    }
    @objc func toggleVisibility() {
        physics.stop()
        hidden.toggle()
        // Use persisted back-to-front order; dictionary iteration would shuffle overlaps.
        for note in store.notes where !note.archived {
            guard let c = controllers[note.id] else { continue }
            if hidden { c.window?.orderOut(nil) } else { c.show() }
        }
    }
    @objc func rescue() {
        physics.stop()
        for c in controllers.values {
            if let w = c.window {
                let fitted = ScreenLayout.fit(w.frame, in: ScreenLayout.frames)
                if w.frame != fitted { w.setFrame(fitted, display: true); c.captureFrame() }
            }
        }
        store.flush()
    }
    @objc func showArchive() {
        if archiveWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 490), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.level = .modalPanel;w.hidesOnDeactivate=true; w.title = "收好的纸条"; w.isReleasedWhenClosed = false; w.minSize = NSSize(width: 340, height: 300)
            w.contentView = NSHostingView(rootView: ArchiveView(store: store, restore: { [weak self] in self?.restore($0) }))
            w.center(); archiveWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); archiveWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 610), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.level = .modalPanel;w.hidesOnDeactivate=true; w.title = "萝卜便签设置"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(focus:focus,shortcut:shortcut)); w.center(); settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func openData() { try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true); NSWorkspace.shared.open(store.directory) }
    @objc func retrySave() { if !store.flush() { showError(store.saveError ?? "数据尚未恢复，写入已暂停。") } }
    @objc func emergencyExport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "萝卜便签-应急副本.json"; NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try e.encode(NoteDocument(notes: store.notes)).write(to: url, options: .atomic) }
            catch { showError(error.localizedDescription) }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        physics.stop()
        guard focus.shutdown() else { showError(focus.error ?? "番茄钟尚未保存，请重试。");return .terminateCancel }
        if store.blocked || store.flush() {
            if scheduler.isReconciling || focus.isReconciling {
                let finish:()->Void={ [weak self] in guard let self,!self.scheduler.isReconciling,!self.focus.isReconciling else { return };NSApp.reply(toApplicationShouldTerminate:true) }
                scheduler.onIdle=finish;focus.onIdle=finish;return .terminateLater
            }
            return .terminateNow
        }
        let a = NSAlert(); a.messageText = "还有便签未能保存"; a.informativeText = "\(store.saveError ?? "")\n建议保留应用运行，修复磁盘问题后重试保存，或先从菜单栏导出应急副本。"
        a.addButton(withTitle: "返回应用"); a.addButton(withTitle: "仍然退出")
        return a.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func showError(_ message: String) { let a = NSAlert(); a.messageText = "萝卜便签"; a.informativeText = message; a.runModal() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier?.rawValue == "notes" { rebuildNotesMenu(menu) }
        else { rebuildStatusMenu(menu) }
    }
    func rebuildNotesMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for n in store.notes where !n.archived {
            let title = n.text.isEmpty ? "空白便签" : String(n.text.split(separator: "\n").first ?? "空白便签").prefix(24).description
            let i = item((n.completed ? "✓ " : "") + title, #selector(focusNote(_:)))
            i.representedObject = n.id.uuidString; menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item("番茄伙伴…",#selector(showFocus),key:"P"))
        menu.addItem(item("归档…", #selector(showArchive), key: "A"))
        menu.addItem(item("撤销上次归档", #selector(undoArchive)))
        let tearUndo=item("撤销上次撕纸",#selector(undoTear));tearUndo.isEnabled=store.canUndoTear;menu.addItem(tearUndo)
        menu.addItem(item(hidden ? "显示全部便签" : "隐藏全部便签", #selector(toggleVisibility), key: "H"))
        menu.addItem(item("设置…", #selector(showSettings)))
        if RuntimeEvidence.folder != nil { menu.addItem(item("导出运行验收快照",#selector(captureEvidence)));menu.addItem(item("验收：90 秒后提醒",#selector(testReminder))) }
    }
    @objc func focusNote(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        if hidden { toggleVisibility() }
        controllers[id]?.show(focus: true)
    }

    func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.target = self; return i
    }
    func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let heading = NSMenuItem(title: "萝卜便签  ·  \(controllers.count) 张在桌面", action: nil, keyEquivalent: ""); menu.addItem(heading)
        menu.addItem(item("新建便签", #selector(createNote(_:)), key: "n"))
        menu.addItem(item("随机纸张新建",#selector(createRandomNote)))
        let sub = NSMenu()
        for s in Shape.allCases { let i = item(s.title, #selector(createNote(_:))); i.representedObject = s.rawValue; sub.addItem(i) }
        let preset = NSMenuItem(title: "按比例新建", action: nil, keyEquivalent: ""); preset.submenu = sub; menu.addItem(preset)
        menu.addItem(.separator())
        menu.addItem(item(hidden ? "显示全部便签" : "隐藏全部便签", #selector(toggleVisibility), key: "H"))
        menu.addItem(item("找回屏幕外便签", #selector(rescue)))
        let notesItem = NSMenuItem(title: "编辑一张便签", action: nil, keyEquivalent: "")
        let notesMenu = NSMenu(); notesMenu.identifier = NSUserInterfaceItemIdentifier("notes"); notesMenu.delegate = self
        notesItem.submenu = notesMenu; menu.addItem(notesItem)
        menu.addItem(item("番茄伙伴…",#selector(showFocus),key:"P"))
        menu.addItem(item("归档…", #selector(showArchive), key: "A"))
        let undo = item("撤销上次归档", #selector(undoArchive)); undo.isEnabled = lastArchived != nil; menu.addItem(undo)
        let tearUndo=item("撤销上次撕纸",#selector(undoTear));tearUndo.isEnabled=store.canUndoTear;menu.addItem(tearUndo)
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(showSettings), key: ","))
        menu.addItem(item("打开数据文件夹", #selector(openData)))
        if store.saveError != nil { menu.addItem(item("保存失败：重试保存", #selector(retrySave))); menu.addItem(item("导出应急副本…", #selector(emergencyExport))) }
        menu.addItem(.separator()); menu.addItem(item("退出萝卜便签", #selector(quit), key: "q"))
        menu.autoenablesItems = false
    }
    @objc func testReminder() {
        guard RuntimeEvidence.folder != nil else { return }
        var n=newNote(shape:.square);n.text="通知实际送达验收 · 90 秒";n.pinned=true;n.dueAt=Date().addingTimeInterval(90);n.dueTimeZone=TimeZone.current.identifier;n.reminderEnabled=true
        store.notes.append(n);store.changed(immediate:true)
        guard store.saveError == nil else { return }
        let c=NoteWindowController(note:n,app:self);controllers[n.id]=c;c.show(focus:true);scheduler.requestPermission()
    }
    @objc func captureEvidence() { RuntimeEvidence.capture(self) }
    @objc func refreshTime() {
        controllers.values.forEach { $0.refreshTime() }
        scheduler.refreshLatest()
    }
    @objc func appearanceChanged() {
        if !physics.enabled { physics.stop() }
        shortcut.update();controllers.values.forEach { $0.apply() }
    }
    @objc func showFocus() {
        if focusWindow==nil {
            let c=controllers.values.first(where:{$0.window?.isKeyWindow==true})
            if focus.state.frame==nil,let c { _=focus.change{$0.color=c.note.color;$0.material=c.note.paperStyle} }
            focusWindow=FocusWindow(focus:focus,near:c?.window?.frame,settings:{ [weak self] in self?.showFocusSettings() })
        }
        focusWindow?.show()
    }
    func showFocusSettings() { inspector("focusSettings",title:"番茄伙伴与学习名单",view:FocusSettingsView(focus:focus),width:490,height:570) }
    func tear(_ id: UUID) {
        guard let c=controllers[id],store.tear(id) else { controllers[id]?.corner.cancel(); return }
        let frame=c.window?.frame ?? c.note.frame
        controllers.removeValue(forKey:id)
        RuntimeEvidence.event(c,"committed");PaperSound.play()
        c.animateTear {}
        toast?.close(); toast=UndoToast(frame:frame) { [weak self] in self?.undoTear() }
    }
    @objc func undoTear() {
        guard let id=store.lastTear?.before.id,store.undoTear(),let n=store.notes.first(where:{$0.id==id}) else { return }
        toast?.close();toast=nil
        let c=NoteWindowController(note:n,app:self);controllers[id]=c
        if hidden { toggleVisibility() } else { c.show() }
        RuntimeEvidence.event(c,"undone")
    }
    func inspector<V:View>(_ key:String,title:String,view:V,width:CGFloat,height:CGFloat) {
        inspectorWindows[key]?.close()
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        w.level = .modalPanel;w.hidesOnDeactivate=true;w.title=title;w.isReleasedWhenClosed=false;w.contentView=NSHostingView(rootView:view);w.center();inspectorWindows[key]=w
        NSApp.activate(ignoringOtherApps:true);w.makeKeyAndOrderFront(nil);w.makeMain()
    }
    func showStyle(_ id:UUID) {
        inspector("style",title:"笔迹与纸材",view:NoteStyleView(store:store,id:id,changed:{ [weak self] in self?.controllers[id]?.apply() }),width:460,height:530)
    }
    func showDeadline(_ id:UUID) {
        guard let n=store.notes.first(where:{$0.id==id}) else { return }
        inspector("deadline",title:"截止与提醒",view:DeadlineView(note:n,scheduler:scheduler,save:{ [weak self] due,enabled,advance,sound in
            guard let self else { return false }
            let ok=self.store.transaction(id) { $0.dueAt=due;$0.dueTimeZone=due == nil ? nil : TimeZone.current.identifier;$0.reminderEnabled=due != nil && enabled;$0.advanceMinutes=advance;$0.notificationSound=sound }
            if ok { self.controllers[id]?.apply(); if enabled && due != nil { self.scheduler.requestPermission() };self.inspectorWindows["deadline"]?.close() }
            return ok
        },cancel:{ [weak self] in self?.inspectorWindows["deadline"]?.close() }),width:430,height:380)
    }
    func setupMenus() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "carrot", accessibilityDescription: "萝卜便签")
        status.button?.image?.isTemplate = true; status.button?.toolTip = "萝卜便签"
        let statusMenu = NSMenu(); statusMenu.delegate = self; status.menu = statusMenu
        rebuildStatusMenu(statusMenu)
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appMenu.addItem(item("设置…",#selector(showSettings),key:",")); appMenu.addItem(.separator()); appMenu.addItem(item("退出萝卜便签", #selector(quit), key: "q")); appItem.submenu = appMenu; main.addItem(appItem)
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); let fileMenu = NSMenu()
        fileMenu.addItem(item("新建便签", #selector(createNote(_:)), key: "n")); fileMenu.addItem(item("收起当前便签", #selector(closeCurrent), key: "w")); fileItem.submenu = fileMenu; main.addItem(fileItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key)) }
        editItem.submenu = edit; main.addItem(editItem)
        let notesItem = NSMenuItem(title: "便签", action: nil, keyEquivalent: "")
        let notesMenu = NSMenu(title: "便签"); notesMenu.identifier = NSUserInterfaceItemIdentifier("notes"); notesMenu.delegate = self
        notesItem.submenu = notesMenu; main.addItem(notesItem)
        NSApp.mainMenu = main
    }
}
struct ArchiveView: View {
    @ObservedObject var store: NoteStore
    var restore: (UUID) -> Void
    @State var search = ""
    var archived: [Note] { store.notes.filter { $0.archived && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search)) }.sorted { $0.updatedAt > $1.updatedAt } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) { Text("收好的纸条").font(.system(size: 25, weight: .medium, design: .rounded)); Text("想起哪一张，就把它放回桌面。").foregroundStyle(.secondary).font(.system(size: 12)) }
            TextField("找一段文字", text: $search).textFieldStyle(.roundedBorder)
            if archived.isEmpty {
                Spacer(); Text(search.isEmpty ? "还没有收起的便签" : "没有找到这段文字").foregroundStyle(.secondary).frame(maxWidth: .infinity); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(archived) { n in
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: (Paper(rawValue: n.color) ?? .cream).color)).frame(width: 6)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(n.text.isEmpty ? "空白便签" : n.text).lineLimit(4).font(.system(size: 14))
                                    Text(n.completed ? "✓ 已完成" : (n.reminderEnabled && n.dueAt != nil ? "未完成 · 收起后仍提醒" : "未完成")).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button("放回桌面") { restore(n.id) }.buttonStyle(.borderless)
                            }.padding(13).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 300, minHeight: 250)
    }
}
