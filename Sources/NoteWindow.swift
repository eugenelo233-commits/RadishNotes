import AppKit
import QuartzCore
final class PaperWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53, let c = windowController as? NoteWindowController, c.corner.gesture.active { c.corner.cancel(); return }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) {
        if let c = windowController as? NoteWindowController, c.corner.gesture.active { c.corner.cancel() }
        else { super.cancelOperation(sender) }
    }
}
final class PaperTextView: NSTextView {
    var compositionEnded: (() -> Void)?
    override func unmarkText() { super.unmarkText(); DispatchQueue.main.async { [weak self] in self?.compositionEnded?() } }
    override func insertText(_ insertString: Any, replacementRange: NSRange) { super.insertText(insertString,replacementRange:replacementRange); if !hasMarkedText() { compositionEnded?() } }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        (window?.windowController as? NoteWindowController)?.app.physics.stop()
        window?.makeKeyAndOrderFront(nil); window?.makeMain()
        super.mouseDown(with: event)
    }
}
final class DragEdge: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var start = NSPoint.zero
    private var original = NSRect.zero
    private var physical=false
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let c=window.windowController as? NoteWindowController
        c?.app.physics.stop()
        window.makeKeyAndOrderFront(nil); window.makeMain()
        start = window.convertPoint(toScreen: event.locationInWindow); original = window.frame
        c?.setLifted(true)
        physical=c?.app.physics.enabled == true
        if physical,let c { c.app.physics.begin(c,time:event.timestamp) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let target=NSPoint(x:original.minX+point.x-start.x,y:original.minY+point.y-start.y)
        if physical,let c=window.windowController as? NoteWindowController,c.app.physics.enabled { c.app.physics.target(target,time:event.timestamp) }
        else { window.setFrameOrigin(target) }
    }
    override func mouseUp(with event: NSEvent) {
        guard let window else { return }
        if physical,let c=window.windowController as? NoteWindowController { c.app.physics.release(time:event.timestamp);physical=false;return }
        window.setFrame(ScreenLayout.fit(window.frame, in: ScreenLayout.frames), display: true)
        (window.windowController as? NoteWindowController)?.setLifted(false)
        (window.windowController as? NoteWindowController)?.app.store.flush()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        let y = bounds.midY
        for i in -2...2 { NSBezierPath(ovalIn: NSRect(x: bounds.midX + CGFloat(i)*5-0.75, y: y, width: 1.5, height: 1.5)).fill() }
    }
}
final class ResizeGrip: NSView {
    var start: NSPoint = .zero
    var original: NSRect = .zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { guard let window else { return }; (window.windowController as? NoteWindowController)?.app.physics.stop(); start = window.convertPoint(toScreen: event.locationInWindow); original = window.frame }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let width = max(ScreenLayout.minimum.width, original.width + point.x-start.x)
        let height = max(ScreenLayout.minimum.height, original.height - (point.y-start.y))
        let frame = NSRect(x: original.minX, y: original.maxY-height, width: width, height: height)
        window.setFrame(ScreenLayout.fit(frame, in: ScreenLayout.frames), display: true)
    }
    override func mouseUp(with event: NSEvent) { (window?.windowController as? NoteWindowController)?.app.store.flush() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.24).setStroke()
        for i in 0...2 {
            let p = NSBezierPath(); p.move(to: NSPoint(x: bounds.maxX-4-CGFloat(i)*4, y: 4)); p.line(to: NSPoint(x: bounds.maxX-4, y: 4+CGFloat(i)*4)); p.lineWidth = 1; p.stroke()
        }
    }
}
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let id: UUID
    unowned let app: AppDelegate
    let paper = PaperView()
    let editor = PaperTextView()
    let scroll = NSScrollView()
    let edge = DragEdge()
    let grip = ResizeGrip()
    let done = NSButton()
    let more = NSButton()
    let pin = NSTextField(labelWithString: "")
    let footer = NSTextField(labelWithString: "")
    let deadlineButton = NSButton()
    let corner = TearCorner()
    var styleSignature = ""
    var tearing = false
    static var desktopLevel: NSWindow.Level { NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) }
    var hovered = false
    var applying = false
    var note: Note { app.store.notes.first { $0.id == id }! }
    init(note: Note, app: AppDelegate) {
        self.id = note.id; self.app = app
        let w = PaperWindow(contentRect: ScreenLayout.fit(note.frame, in: ScreenLayout.frames), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        super.init(window: w)
        w.title = "萝卜便签 · \(note.text.prefix(24))"
        w.isReleasedWhenClosed = false; w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.minSize = ScreenLayout.minimum; w.hidesOnDeactivate = false
        w.isMovableByWindowBackground = false; w.isMovable = true
        w.animationBehavior = .none; w.delegate = self
        w.contentView = paper; paper.wantsLayer = true
        paper.appearance = NSAppearance(named: .aqua)
        paper.hoverChanged = { [weak self] value in self?.hovered = value; self?.updateChrome() }
        edge.toolTip = "拖动上沿，摆放纸条"
        paper.addSubview(edge)
        setupButton(done, symbol: "circle", help: "标记完成", action: #selector(toggleDone))
        setupButton(more, symbol: "ellipsis", help: "颜色、比例、置顶与归档", action: #selector(showMore))
        pin.font = .systemFont(ofSize: 10, weight: .medium); pin.textColor = NSColor.black.withAlphaComponent(0.45); paper.addSubview(pin)
        footer.font = .systemFont(ofSize: 9); footer.textColor = NSColor.black.withAlphaComponent(0.38); paper.addSubview(footer)
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false; editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.minSize = .zero; editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.font = .systemFont(ofSize:note.fontSize)
        editor.string = note.text; editor.delegate = self
        editor.compositionEnded = { [weak self] in
            guard let self,!self.editor.hasMarkedText() else { return }
            if self.note.text != self.editor.string { self.app.store.update(self.id) { $0.text=self.editor.string } }
            self.applyTextStyle(force:true)
        }
        editor.setAccessibilityLabel("便签正文")
        scroll.documentView = editor; scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        paper.addSubview(scroll); paper.addSubview(grip)
        corner.controller = self; paper.addSubview(corner)
        deadlineButton.isBordered = false; deadlineButton.alignment = .left; deadlineButton.target = self; deadlineButton.action = #selector(showDeadline)
        deadlineButton.setAccessibilityLabel("截止与提醒"); paper.addSubview(deadlineButton)
        grip.toolTip = "拖动右下角，自由调整大小"
        apply(); layout()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setupButton(_ b: NSButton, symbol: String, help: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        b.isBordered = false; b.contentTintColor = NSColor.black.withAlphaComponent(0.55)
        b.target = self; b.action = action; b.toolTip = help; b.setAccessibilityLabel(help); paper.addSubview(b)
    }
    func layout() {
        let size = paper.bounds.size
        edge.frame = NSRect(x: 32, y: 0, width: max(30, size.width-65), height: 25)
        done.frame = NSRect(x: 7, y: 2, width: 24, height: 21)
        more.frame = NSRect(x: size.width-31, y: 2, width: 24, height: 21)
        pin.frame = NSRect(x: 37, y: 6, width: 50, height: 14)
        scroll.frame = NSRect(x: 17, y: 33, width: size.width-36, height: max(26, size.height-70))
        editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(editor.frame.height, scroll.contentSize.height)))
        grip.frame = NSRect(x: size.width-19, y: size.height-19, width: 18, height: 18)
        footer.frame = NSRect(x: 39, y: size.height-18, width: size.width-62, height: 12)
        corner.frame = NSRect(x:0,y:size.height-PaperDesign.tearHotspot,width:PaperDesign.tearHotspot,height:PaperDesign.tearHotspot)
        deadlineButton.frame = NSRect(x:39,y:size.height-36,width:size.width-65,height:19)
    }
    func apply() {
        guard let window else { return }
        applying = true; defer { applying = false }
        let n = note
        paper.note = n; paper.now = app.now()
        applyTextStyle()
        editor.insertionPointColor = (Ink(rawValue:n.ink) ?? .charcoal).color
        done.image = NSImage(systemSymbolName: n.completed ? "checkmark.circle.fill" : "circle", accessibilityDescription: n.completed ? "取消完成" : "标记完成")
        done.setAccessibilityLabel(n.completed ? "取消完成" : "标记完成"); done.toolTip = n.completed ? "取消完成" : "标记完成"
        pin.stringValue = ""; pin.toolTip = n.pinned ? "图钉：单张置顶，仍可拖动" : nil
        // A public CoreGraphics desktop level, not a normal application window.
        window.level = n.pinned ? .floating : window.isKeyWindow ? .normal : Self.desktopLevel
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        refreshTime()
        updateChrome(); window.invalidateShadow()
    }
    func updateChrome() {
        let active = hovered || window?.isKeyWindow == true
        done.alphaValue = active || note.completed ? 1 : 0
        more.alphaValue = active ? 1 : 0
        edge.alphaValue = active ? 1 : 0
        grip.alphaValue = active ? 0.7 : 0.2
    }
    func show(focus: Bool = false) {
        window?.orderFront(nil)
        if focus { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); window?.makeMain(); window?.makeFirstResponder(editor) }
    }
    func textDidChange(_ notification: Notification) {
        guard !editor.hasMarkedText() else { return }
        app.store.update(id) { $0.text = editor.string }; applyTextStyle(force:true)
        window?.title = "萝卜便签 · \(editor.string.prefix(24))"
    }
    func captureFrame() {
        guard !applying, !app.physics.isApplying, !app.physics.isRunning, let window else { return }
        guard note.frame != window.frame || note.screenID != ScreenLayout.id(window.screen) else { return }
        app.store.update(id) { $0.frame = window.frame; $0.screenID = ScreenLayout.id(window.screen) }
    }
    func windowDidMove(_ notification: Notification) { captureFrame() }
    func windowDidResize(_ notification: Notification) { layout(); captureFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { captureFrame(); app.store.flush() }
    func windowDidBecomeKey(_ notification: Notification) { apply(); app.bringForward(id) }
    func windowDidResignKey(_ notification: Notification) { apply(); app.store.flush() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { app.archive(id); return false }
    @objc func toggleDone() { let date=app.now(); if app.store.transaction(id,{ $0.setCompleted(!$0.completed,at:date) }) { apply() } }
    @objc func togglePin() { if app.store.transaction(id,{ $0.pinned.toggle() }) { apply(); window?.orderFront(nil) } }
    @objc func archiveNote() { app.archive(id) }
    @objc func showMore() {
        let menu = NSMenu()
        for (title, action) in [("笔迹与纸材…",#selector(showStyle)),("截止与提醒…",#selector(showDeadline))] {
            let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;menu.addItem(i)
        }
        menu.addItem(.separator())
        let colors = NSMenu()
        for p in Paper.allCases {
            let i = NSMenuItem(title: p.title, action: #selector(setColor(_:)), keyEquivalent: ""); i.target = self; i.representedObject = p.rawValue; i.state = note.color == p.rawValue ? .on : .off
            let image = NSImage(size: NSSize(width: 13, height: 13), flipped: false) { rect in p.color.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill(); return true }; i.image = image; colors.addItem(i)
        }
        let colorItem = NSMenuItem(title: "纸张颜色", action: nil, keyEquivalent: ""); colorItem.submenu = colors; menu.addItem(colorItem)
        let sizes = NSMenu()
        for s in Shape.allCases { let i = NSMenuItem(title: "\(s.title)  \(Int(s.size.width)) × \(Int(s.size.height))", action: #selector(setShape(_:)), keyEquivalent: ""); i.target = self; i.representedObject = s.rawValue; sizes.addItem(i) }
        let shapeItem = NSMenuItem(title: "纸条比例", action: nil, keyEquivalent: ""); shapeItem.submenu = sizes; menu.addItem(shapeItem)
        let fonts = NSMenu()
        for f in [14, 16, 17, 19, 22, 26] { let i = NSMenuItem(title: "\(f) 点", action: #selector(setFont(_:)), keyEquivalent: ""); i.target = self; i.tag = f; i.state = note.fontSize == Double(f) ? .on : .off; fonts.addItem(i) }
        let fontItem = NSMenuItem(title: "文字大小", action: nil, keyEquivalent: ""); fontItem.submenu = fonts; menu.addItem(fontItem)
        menu.addItem(.separator())
        for (title, action) in [(note.pinned ? "取消置顶，放回桌面" : "单张置顶", #selector(togglePin)), (note.completed ? "取消完成" : "标记完成", #selector(toggleDone)), ("收起到归档", #selector(archiveNote))] {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; menu.addItem(i)
        }
        menu.addItem(.separator())
        for (title,action) in [("撕下并完成",#selector(commitTear)),("换张新纸 · 只更新纸龄和纸纹",#selector(renewPaper))] {
            let i=NSMenuItem(title:title,action:action,keyEquivalent:"");i.target=self;menu.addItem(i)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.maxY), in: more)
    }
    @objc func setColor(_ sender: NSMenuItem) { app.store.update(id, immediate: true) { $0.color = sender.representedObject as! String }; apply() }
    @objc func setFont(_ sender: NSMenuItem) { app.store.update(id, immediate: true) { $0.fontSize = Double(sender.tag) }; apply() }
    @objc func setShape(_ sender: NSMenuItem) {
        guard let s = Shape(rawValue: sender.representedObject as! String), let window else { return }
        var f = window.frame; f.origin.y = f.maxY-s.size.height; f.size = s.size
        window.setFrame(ScreenLayout.fit(f, in: ScreenLayout.frames), display: true)
        captureFrame(); app.store.flush()
    }
    func applyTextStyle(force: Bool = false) {
        guard !editor.hasMarkedText(), let storage = editor.textStorage else { return }
        let n=note
        let signature="\(n.chineseFont)|\(n.latinFont)|\(FontBook.resolved(n.chineseFont,chinese:true))|\(FontBook.resolved(n.latinFont,chinese:false))|\(n.ink)|\(n.fontSize)|\(n.completed)"
        guard force || signature != styleSignature else { return }
        let ranges=editor.selectedRanges
        editor.undoManager?.disableUndoRegistration()
        FontBook.style(storage,note:n)
        editor.undoManager?.enableUndoRegistration()
        editor.selectedRanges=ranges
        editor.typingAttributes=[.font:FontBook.font(n.chineseFont,size:n.fontSize,chinese:true),.foregroundColor:(Ink(rawValue:n.ink) ?? .charcoal).color]
        styleSignature=signature
    }
    func refreshTime() {
        paper.note=note;paper.now=app.now()
        if corner.gesture.active { return }
        let n=note;let state=DeadlineState.evaluate(n,now:app.now())
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"zh_CN");formatter.dateFormat="M月d日 HH:mm"
        if let due=n.dueAt {
            deadlineButton.title=(state == .overdue ? "◷ 已逾期 · " : "◷ ")+formatter.string(from:due)
            deadlineButton.toolTip="截止时间：\(due.formatted()) · \(n.dueTimeZone ?? TimeZone.current.identifier)\n\(n.reminderEnabled ? app.scheduler.permission : "系统提醒关闭")"
            deadlineButton.font=FontBook.font("kalam",size:11,chinese:false)
            deadlineButton.contentTintColor = state == .urgent || state == .overdue ? NSColor(hex:0x9D302A) : state == .soon ? NSColor(hex:0x9D5E21) : NSColor(hex:0x6A6256)
            deadlineButton.isHidden=false
        } else { deadlineButton.isHidden=true }
        footer.stringValue=app.store.saveError != nil ? "保存失败 · 请查看菜单栏" : n.completed ? "✓ 已完成，留在这里也很好" : ""
    }
    @objc func showStyle() { app.showStyle(id) }
    @objc func showDeadline() { app.showDeadline(id) }
    @objc func renewPaper() { if app.store.transaction(id,{ $0.renewPaper(at:app.now()) }) { apply() } }
    func prepareTear() -> Bool {
        app.physics.stop()
        guard !tearing else { return false }
        guard !editor.hasMarkedText() else { footer.stringValue="请先确认输入法候选，再撕纸"; return false }
        // Drain the current plain-text edit before the atomic task-state transition.
        if note.text != editor.string { app.store.update(id) { $0.text=editor.string } }
        return app.store.flush()
    }
    func tearPreview(_ progress:CGFloat,ready:Bool) {
        paper.tearProgress=PaperDesign.reduceMotion ? min(progress,0.35) : progress
        footer.stringValue=progress > 0 ? (ready ? "松手完成 · 拖回或 Esc 取消" : "继续向右上拉 · 松手可取消") : ""
    }
    @objc func commitTear() {
        guard prepareTear() else { corner.cancel();return }
        app.tear(id)
    }
    func setLifted(_ value:Bool) {
        if PaperDesign.reduceMotion { paper.lifted=false;return }
        if value { paper.lifted=true }
        else { DispatchQueue.main.asyncAfter(deadline:.now()+PaperDesign.landingTime) { [weak self] in self?.paper.lifted=false } }
    }
    func animateTear(completion:@escaping()->Void) {
        tearing=true;corner.gesture.cancel();window?.ignoresMouseEvents=true
        paper.tearProgress=1.2
        let duration=PaperDesign.reduceMotion ? 0.08 : PaperDesign.tearTime
        let opacity=CABasicAnimation(keyPath:"opacity");opacity.fromValue=1;opacity.toValue=0
        let scale=CABasicAnimation(keyPath:"transform.scale");scale.fromValue=1;scale.toValue=PaperDesign.reduceMotion ? 1 : 0.87
        let drop=CABasicAnimation(keyPath:"transform.translation.y");drop.fromValue=0;drop.toValue=PaperDesign.reduceMotion ? 0 : 12
        let group=CAAnimationGroup();group.animations=[opacity,scale,drop];group.duration=duration;group.fillMode = .forwards;group.isRemovedOnCompletion=false;group.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
        paper.layer?.add(group,forKey:"tear")
        DispatchQueue.main.asyncAfter(deadline:.now()+duration) { [self] in window?.orderOut(nil);paper.layer?.removeAnimation(forKey:"tear");completion() }
    }

}
