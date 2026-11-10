import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PaperSurface:NSViewRepresentable {
    var note:Note
    func makeNSView(context:Context)->PaperView { let view=PaperView();view.appearance=NSAppearance(named:.aqua);return view }
    func updateNSView(_ view:PaperView,context:Context) { view.note=note;view.now=Date() }
}
final class RadishDrawing:NSView {
    var warning=false;var working=false;var tapped=false;var tap:(()->Void)?
    override var isFlipped:Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
    override func mouseDown(with event:NSEvent) { tap?() }
    override func accessibilityPerformPress()->Bool { tap?();return true }
    override func draw(_ dirtyRect:NSRect) {
        let transform=NSAffineTransform();transform.scale(by:bounds.width/220);NSGraphicsContext.saveGraphicsState();transform.concat()
        func ellipse(_ r:NSRect,_ color:NSColor) { color.setFill();NSBezierPath(ovalIn:r).fill() }
        ellipse(NSRect(x:49,y:153,width:124,height:15),NSColor(hex:0x796A4E).withAlphaComponent(0.13))
        let leafColors:[UInt32]=[0x72965F,0x90AF70,0x537D52]
        for (i,r) in [NSRect(x:72,y:18,width:23,height:53),NSRect(x:102,y:4,width:25,height:61),NSRect(x:128,y:20,width:22,height:47)].enumerated() {
            NSGraphicsContext.saveGraphicsState();let t=NSAffineTransform();t.translateX(by:r.midX,yBy:r.maxY);t.rotate(byDegrees:i==0 ? -28 : i==2 ? 30 : 4);t.translateX(by:-r.midX,yBy:-r.maxY);t.concat()
            ellipse(r,NSColor(hex:leafColors[i]));NSColor(hex:0xD8DDA3).withAlphaComponent(0.55).setStroke();let vein=NSBezierPath();vein.move(to:NSPoint(x:r.midX,y:r.minY+12));vein.line(to:NSPoint(x:r.midX,y:r.maxY));vein.lineWidth=1;vein.stroke();NSGraphicsContext.restoreGraphicsState()
        }
        let body=NSBezierPath();body.move(to:NSPoint(x:69,y:64));body.curve(to:NSPoint(x:154,y:67),controlPoint1:NSPoint(x:75,y:46),controlPoint2:NSPoint(x:141,y:45));body.curve(to:NSPoint(x:127,y:151),controlPoint1:NSPoint(x:181,y:99),controlPoint2:NSPoint(x:147,y:147));body.curve(to:NSPoint(x:104,y:163),controlPoint1:NSPoint(x:114,y:159),controlPoint2:NSPoint(x:115,y:161));body.curve(to:NSPoint(x:69,y:64),controlPoint1:NSPoint(x:54,y:143),controlPoint2:NSPoint(x:42,y:93));body.close()
        NSGraphicsContext.saveGraphicsState();let shadow=NSShadow();shadow.shadowColor=NSColor(hex:0x6F674D).withAlphaComponent(0.2);shadow.shadowOffset=NSSize(width:2,height:-3);shadow.shadowBlurRadius=4;shadow.set();NSColor(hex:0xFFF8E6).setFill();body.fill();NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting:NSColor(hex:0xFFFCED),ending:NSColor(hex:0xE7DCC0))!.draw(in:body,angle:40)
        NSColor(hex:0x837A5B).withAlphaComponent(0.5).setStroke();body.lineWidth=1.3;body.stroke()
        ellipse(NSRect(x:67,y:107,width:20,height:10),NSColor(hex:0xEBAF9B).withAlphaComponent(0.65));ellipse(NSRect(x:136,y:107,width:20,height:10),NSColor(hex:0xEBAF9B).withAlphaComponent(0.65))
        NSColor(hex:0x3D4334).setStroke();NSColor(hex:0x3D4334).setFill()
        for x:CGFloat in [88,131] {
            if tapped { let eye=NSBezierPath();eye.move(to:NSPoint(x:x-4,y:99));eye.curve(to:NSPoint(x:x+5,y:99),controlPoint1:NSPoint(x:x,y:91),controlPoint2:NSPoint(x:x+2,y:91));eye.lineWidth=2;eye.stroke() }
            else { ellipse(NSRect(x:x-2,y:94,width:5,height:9),NSColor(hex:0x3D4334)) }
            if warning { let brow=NSBezierPath();brow.move(to:NSPoint(x:x-5,y:87));brow.line(to:NSPoint(x:x+5,y:90));brow.lineWidth=2;brow.stroke() }
        }
        let mouth=NSBezierPath();mouth.move(to:NSPoint(x:104,y:115));mouth.curve(to:NSPoint(x:117,y:115),controlPoint1:NSPoint(x:108,y:warning ? 111 : 123),controlPoint2:NSPoint(x:113,y:warning ? 111 : 123));mouth.lineWidth=1.8;mouth.stroke()
        for x:CGFloat in [64,151] { let arm=NSBezierPath();arm.move(to:NSPoint(x:x,y:114));arm.curve(to:NSPoint(x:x+(x<100 ? -14 : 14),y:125),controlPoint1:NSPoint(x:x+(x<100 ? -10 : 10),y:111),controlPoint2:NSPoint(x:x+(x<100 ? -14 : 14),y:119));arm.lineWidth=2;arm.stroke() }
        if warning {
            let stick=NSBezierPath();stick.move(to:NSPoint(x:172,y:125));stick.line(to:NSPoint(x:172,y:71));stick.lineWidth=2;NSColor(hex:0x796B4D).setStroke();stick.stroke()
            let flag=NSBezierPath(roundedRect:NSRect(x:173,y:66,width:28,height:25),xRadius:4,yRadius:4);NSColor(hex:0xCF8764).setFill();flag.fill()
            ("!" as NSString).draw(at:NSPoint(x:183,y:65),withAttributes:[.font:NSFont.boldSystemFont(ofSize:21),.foregroundColor:NSColor.white])
        } else if working {
            let book=NSBezierPath(roundedRect:NSRect(x:74,y:132,width:74,height:25),xRadius:3,yRadius:3);NSColor(hex:0x789778).setFill();book.fill();NSColor(hex:0xEEE9CD).setStroke();let crease=NSBezierPath();crease.move(to:NSPoint(x:111,y:133));crease.line(to:NSPoint(x:111,y:155));crease.lineWidth=1.5;crease.stroke()
        }
        if tapped { for x:CGFloat in [42,180] { ("✦" as NSString).draw(at:NSPoint(x:x,y:49),withAttributes:[.font:NSFont.systemFont(ofSize:17),.foregroundColor:NSColor(hex:0xB8924F)]) } }
        NSGraphicsContext.restoreGraphicsState()
    }
}
struct PetPortrait:NSViewRepresentable {
    @ObservedObject var focus:FocusStore
    func makeNSView(context:Context)->RadishDrawing { let view=RadishDrawing();view.setAccessibilityElement(true);view.setAccessibilityRole(.button);view.setAccessibilityLabel("摸摸小萝卜");return view }
    func updateNSView(_ view:RadishDrawing,context:Context) { view.warning=focus.warning;view.working=focus.state.running && focus.state.phase == .focus;view.tapped=focus.petTapped;view.tap={focus.pet()};view.needsDisplay=true }
}
struct FocusPrimaryButton:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:13,weight:.semibold)).foregroundStyle(Color.white)
            .padding(.horizontal,16).padding(.vertical,7)
            .background(Color(nsColor:NSColor(hex:configuration.isPressed ? 0x4F6540 : 0x647B50)),in:RoundedRectangle(cornerRadius:7))
    }
}
struct FocusPetView:View {
    @ObservedObject var focus:FocusStore
    var settings:()->Void
    var paper:Note { var n=Note();n.color=focus.state.color;n.paperStyle=focus.state.material;n.textureSeed=focus.state.textureSeed;n.agingEnabled=false;return n }
    var clock:String { let s=Int(ceil(focus.remaining));return String(format:"%02d:%02d",s/60,s%60) }
    var body:some View {
        VStack(spacing:10) {
            HStack {
                Label("番茄伙伴",systemImage:"leaf.fill").font(.system(size:13,weight:.semibold))
                Spacer()
                Button { _=focus.change{$0.pinned.toggle()} } label:{Image(systemName:focus.state.pinned ? "pin.fill" : "pin")}.buttonStyle(.plain).help("伙伴单独置顶")
                Button(action:settings){Image(systemName:"gearshape")}.buttonStyle(.plain).help("番茄钟与学习名单")
            }
            PetPortrait(focus:focus).frame(width:206,height:163)
            Text(focus.message).font(.system(size:12,weight:.medium)).multilineTextAlignment(.center).frame(maxWidth:.infinity,minHeight:42).padding(.horizontal,8).padding(.vertical,5).background(Color.white.opacity(0.43),in:RoundedRectangle(cornerRadius:12))
            HStack(alignment:.firstTextBaseline,spacing:9) {
                Text(clock).font(.system(size:39,weight:.light,design:.rounded).monospacedDigit())
                Text(focus.state.phase.title).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value:min(1,max(0,1-focus.remaining/focus.state.seconds))).tint(focus.warning ? Color(nsColor:NSColor(hex:0xBE805E)) : Color(nsColor:NSColor(hex:0x657F55)))
            HStack(spacing:12) {
                Button(focus.state.running ? "暂停" : focus.state.phase == .focus ? "开始专注" : "开始休息") { focus.toggle() }.buttonStyle(FocusPrimaryButton())
                Button("重置") { focus.reset() }.buttonStyle(.bordered)
                if !focus.state.running && focus.state.phase != .focus { Button("下一轮") { focus.skipBreak() }.buttonStyle(.borderless) }
            }
            if focus.warning { Button("这是学习 · 本轮放行") {focus.allowThisSession()}.buttonStyle(.bordered) }
            Text(focus.status).font(.system(size:10)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(minHeight:27)
            HStack { Text("🍅 \(focus.state.tomatoes) 颗收获");Spacer();Text("摸摸我，给彼此充电") }.font(.system(size:10)).foregroundStyle(.secondary)
            if let error=focus.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(22).frame(width:320).background(PaperSurface(note:paper).ignoresSafeArea()).environment(\.colorScheme,.light)
    }
}
final class FocusPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { true }
}
final class FocusWindow:NSWindowController,NSWindowDelegate {
    let focus:FocusStore
    init(focus:FocusStore,near:CGRect?,settings:@escaping()->Void) {
        self.focus=focus
        var frame=CGRect(x:100,y:200,width:320,height:505)
        if let saved=focus.state.frame { frame=NSRectFromString(saved) }
        else if let near { frame.origin=CGPoint(x:near.maxX+12,y:near.maxY-frame.height) }
        frame=ScreenLayout.fit(frame,in:ScreenLayout.frames)
        let window=FocusPanel(contentRect:frame,styleMask:[.titled,.closable,.fullSizeContentView,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init(window:window);window.title="小萝卜 · 番茄伙伴";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false;window.hidesOnDeactivate=false;window.backgroundColor = .clear;window.isOpaque=false;window.hasShadow=true;window.delegate=self
        window.collectionBehavior=[.stationary,.ignoresCycle,.fullScreenNone]
        window.contentView=NSHostingView(rootView:FocusPetView(focus:focus,settings:settings));window.appearance=NSAppearance(named:.aqua)
        focus.onChange={ [weak self] in self?.apply() };apply()
    }
    required init?(coder:NSCoder){fatalError()}
    func apply() { window?.level=focus.state.pinned ? .floating : .normal }
    func show() { window?.makeKeyAndOrderFront(nil);window?.makeMain() }
    func windowDidMove(_ notification:Notification) { if let window { _=focus.change{$0.frame=NSStringFromRect(window.frame)} } }
    func windowShouldClose(_ sender:NSWindow)->Bool { sender.orderOut(nil);return false }
}
struct FocusSettingsView:View {
    @ObservedObject var focus:FocusStore
    @State var domainsText=""
    func binding<T>(_ key:WritableKeyPath<FocusState,T>)->Binding<T> { Binding(get:{focus.state[keyPath:key]},set:{value in _=focus.change{$0[keyPath:key]=value};focus.updateMonitor()}) }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("小萝卜陪你专注").font(.title2)
                HStack {
                    Stepper("专注 \(focus.state.focusMinutes) 分",value:binding(\.focusMinutes),in:1...120)
                    Stepper("休息 \(focus.state.breakMinutes) 分",value:binding(\.breakMinutes),in:1...60)
                }.disabled(focus.state.running).onChange(of:focus.state.focusMinutes){_,_ in if !focus.state.running { focus.reset() } }.onChange(of:focus.state.breakMinutes){_,_ in if !focus.state.running { focus.reset() } }
                Text("每四轮安排 15 分钟长休息；每轮由你主动开始。睡眠、锁屏和正常退出会暂停。").font(.caption).foregroundStyle(.secondary)
                Toggle("离开学习名单后提醒",isOn:binding(\.monitor))
                Picker("宽限时间",selection:binding(\.graceSeconds)) { ForEach([15,30,60,120],id:\.self){Text("\($0) 秒").tag($0)} }
                Toggle("使用系统本地提醒（无声）",isOn:binding(\.systemReminders))
                Divider()
                Text("学习应用").font(.headline)
                ForEach(focus.state.allowedApps){ app in HStack { Text(app.name);Spacer();Button("移除") {_=focus.change{$0.allowedApps.removeAll{$0.id==app.id}};focus.updateMonitor()}.buttonStyle(.borderless) } }
                Button("添加应用…") {
                    let panel=NSOpenPanel();panel.directoryURL=URL(fileURLWithPath:"/Applications");panel.allowedContentTypes=[.applicationBundle];panel.canChooseDirectories=false;panel.allowsMultipleSelection=true
                    if panel.runModal() == .OK { panel.urls.forEach{focus.addApp(url:$0)} }
                }
                Divider()
                Toggle("在 Edge 中按学习网站判断",isOn:binding(\.edgeSites))
                Text("每行一个域名，自动包含其子域名。课程视频网站可永久添加，也可在提醒时只放行本轮。").font(.caption).foregroundStyle(.secondary)
                TextEditor(text:$domainsText).font(.system(size:12,design:.monospaced)).frame(height:100).border(Color.secondary.opacity(0.25))
                HStack { Button("保存网站名单") {let domains=domainsText.components(separatedBy:.newlines).compactMap(StudyRules.cleanHost);_=focus.change{$0.domains=Array(Set(domains)).sorted()};focus.updateMonitor()};Button("检查 Edge 授权") {focus.checkEdge()} }
                Text(focus.edgeStatus).font(.caption).foregroundStyle(.secondary)
                Text("仅专注时读取前台应用名称和 Edge 当前域名，全部在本机判断；不录屏、不读取聊天或网页正文、不保存浏览历史。看视频不等于分心，提醒只表示离开了你设置的名单。").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.frame(width:470,height:540).onAppear{domainsText=focus.state.domains.joined(separator:"\n")}
    }
}
