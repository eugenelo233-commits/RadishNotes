import AppKit
import SwiftUI

struct WritingPreview: NSViewRepresentable {
    var note: Note
    func makeNSView(context:Context)->NSTextField {
        let view=NSTextField(wrappingLabelWithString:"");view.isSelectable=true;view.maximumNumberOfLines=4;return view
    }
    func updateNSView(_ view:NSTextField,context:Context) { view.attributedStringValue=FontBook.attributed("今天，慢慢做好。\nMake room for good things.\n萝卜 Radish · 10:30 · 你好，世界 🌱",note:note) }
}
struct NoteStyleView: View {
    @ObservedObject var store:NoteStore
    let id:UUID
    var changed:()->Void
    var note:Note { store.notes.first(where:{$0.id==id}) ?? Note() }
    func binding<T>(_ key:WritableKeyPath<Note,T>)->Binding<T> { Binding(get:{ note[keyPath:key] },set:{ value in if store.transaction(id,{$0[keyPath:key]=value}) { changed() } }) }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("让这张纸像你").font(.title2)
            Picker("中文笔迹",selection:Binding(get:{note.chineseFont == "chenyu" ? "yozai" : note.chineseFont},set:{value in if store.transaction(id,{$0.chineseFont=value}) {changed()} })) { ForEach(FontBook.chinese) { Text($0.name).tag($0.id) } }
            Picker("英文笔迹",selection:binding(\.latinFont)) { ForEach(FontBook.latin) { Text($0.name).tag($0.id) } }
            HStack {
                Picker("字号",selection:binding(\.fontSize)) { ForEach([14,16,17,19,22,26],id:\.self) { Text("\($0)").tag(Double($0)) } }
                Picker("墨水",selection:binding(\.ink)) { ForEach(Ink.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            }
            Divider()
            Picker("纸材",selection:binding(\.paperStyle)) { ForEach(PaperMaterial.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            Picker("纸色",selection:binding(\.color)) { ForEach(Paper.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            Toggle("让这张纸随时间自然变旧",isOn:binding(\.agingEnabled))
            WritingPreview(note:note).frame(height:104).padding(12).background(Color(nsColor:(Paper(rawValue:note.color) ?? .cream).color),in:RoundedRectangle(cornerRadius:4))
            Text("修改即时保存。缺字会逐字回退；表情使用系统彩色字体。\n悠哉为随性手写，文楷适合长段落。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:440)
    }
}
struct DeadlineView:View {
    let note:Note
    @ObservedObject var scheduler:DeadlineScheduler
    var save:(Date?,Bool,Int,Bool)->Bool
    var cancel:()->Void
    @State var hasDue:Bool
    @State var date:Date
    @State var reminder:Bool
    @State var advance:Int
    @State var sound:Bool
    @State var error=false
    init(note:Note,scheduler:DeadlineScheduler,save:@escaping(Date?,Bool,Int,Bool)->Bool,cancel:@escaping()->Void) {
        self.note=note;self.scheduler=scheduler;self.save=save;self.cancel=cancel
        _hasDue=State(initialValue:note.dueAt != nil);_date=State(initialValue:note.dueAt ?? Date().addingTimeInterval(3600))
        _reminder=State(initialValue:note.reminderEnabled);_advance=State(initialValue:note.advanceMinutes);_sound=State(initialValue:note.notificationSound)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Toggle("设置截止时间",isOn:$hasDue).font(.headline)
            DatePicker("截止",selection:$date,displayedComponents:[.date,.hourAndMinute]).disabled(!hasDue)
            Text("时区：\(TimeZone.current.identifier) · 截止时刻固定").font(.caption).foregroundStyle(.secondary)
            Toggle("使用系统本地提醒",isOn:$reminder).disabled(!hasDue)
            HStack {
                Picker("提前",selection:$advance) { Text("仅到期").tag(0);ForEach([10,30,60],id:\.self) { Text("\($0) 分钟").tag($0) } }
                Toggle("提醒声音",isOn:$sound)
            }.disabled(!hasDue || !reminder)
            Text(scheduler.permission).font(.caption).foregroundStyle(.secondary)
            if let issue=scheduler.schedulingError { Text(issue).font(.caption).foregroundStyle(.red) }
            Text("完成后停止提醒；只收起仍会提醒。\n已过去的提醒不会补发。通知是否展示由系统决定。").font(.caption).foregroundStyle(.secondary)
            if error { Text("保存失败，原截止设置仍然保留。").font(.caption).foregroundStyle(.red) }
            HStack { Spacer();Button("取消",action:cancel).keyboardShortcut(.cancelAction);Button("保存") { error = !save(hasDue ? Date(timeIntervalSince1970:floor(date.timeIntervalSince1970/60)*60) : nil,reminder,advance,sound) }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:410)
    }
}
struct PaperSettingsView: View {
    @AppStorage("paperAppearance",store:AppPreferences.defaults) var appearance="realistic"
    @AppStorage("textureStrength",store:AppPreferences.defaults) var strength=1.0
    @AppStorage("randomPaper",store:AppPreferences.defaults) var randomPaper=false
    @AppStorage("defaultColor",store:AppPreferences.defaults) var color="cream"
    @AppStorage("defaultShape",store:AppPreferences.defaults) var shape="square"
    @AppStorage("defaultFont",store:AppPreferences.defaults) var font=19.0
    @AppStorage("defaultChineseFont",store:AppPreferences.defaults) var chinese="wenkai"
    @AppStorage("defaultLatinFont",store:AppPreferences.defaults) var latin="caveat"
    @AppStorage("defaultPaperStyle",store:AppPreferences.defaults) var paper="fiber"
    @AppStorage("defaultInk",store:AppPreferences.defaults) var ink="charcoal"
    @AppStorage("agingEnabled",store:AppPreferences.defaults) var aging=true
    @AppStorage("paperSound",store:AppPreferences.defaults) var paperSound=false
    @AppStorage("reduceMotion",store:AppPreferences.defaults) var reduce=false
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("纸张与笔迹").font(.title2)
            Picker("纸面风格",selection:$appearance) { Text("写实纸张").tag("realistic");Text("经典纯色").tag("classic") }.pickerStyle(.segmented)
            if appearance == "realistic" { Picker("纹理强度",selection:$strength) { Text("柔和").tag(0.55);Text("清楚").tag(0.8);Text("明显").tag(1.0) } }
            Toggle("每次新建随机纸色与纸材",isOn:$randomPaper)
            Text("随机只用于新纸；已有纸张保持自己的颜色、材质和位置。").font(.caption).foregroundStyle(.secondary)
            Picker("中文默认",selection:Binding(get:{chinese == "chenyu" ? "yozai" : chinese},set:{chinese=$0})) { ForEach(FontBook.chinese.filter{$0.id != "default"}) { Text($0.name).tag($0.id) } }
            Picker("英文默认",selection:$latin) { ForEach(FontBook.latin.filter{$0.id != "default"}) { Text($0.name).tag($0.id) } }
            Picker("纸材",selection:$paper) { ForEach(PaperMaterial.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            Picker("纸色",selection:$color) { ForEach(Paper.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            Picker("墨水",selection:$ink) { ForEach(Ink.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            Picker("比例",selection:$shape) { ForEach(Shape.allCases,id:\.rawValue) { Text($0.title).tag($0.rawValue) } }
            Picker("字号",selection:$font) { ForEach([14,16,17,19,22,26],id:\.self) { Text("\($0) 点").tag(Double($0)) } }
            Toggle("显示自然老化",isOn:$aging)
            Toggle("减少动态效果",isOn:$reduce)
            Toggle("轻声撕纸（默认关闭）",isOn:$paperSound)
            Text("字体默认影响选择“跟随默认”的纸条，其余外观用于新建。\n减少动态也遵循系统设置。数据与字体均在本机。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:420)
    }
}

struct InteractionSettingsView:View {
    @ObservedObject var shortcut:GlobalShortcut
    @AppStorage("paperPhysics",store:AppPreferences.defaults) var physics=false
    @AppStorage("paperDragDamping",store:AppPreferences.defaults) var damping=PaperMotionTuning.defaultDamping
    @AppStorage("globalNewNote",store:AppPreferences.defaults) var global=true
    @AppStorage("globalShortcutChoice",store:AppPreferences.defaults) var combination=0
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text("让纸条动起来").font(.title2)
            Toggle("物理互动：惯性滑动＋纸条碰撞",isOn:$physics)
            Text("拖上沿时带一点跟手延迟，松手可滑行；碰到其他纸条时相互弹开。不会拆开原先重叠的纸堆，停止后保存最终位置。").font(.callout).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:8) {
                HStack {Text("拖动阻尼");Spacer();Text("\(Int(damping*100))%").monospacedDigit();Button("恢复轻盈默认") {damping=PaperMotionTuning.defaultDamping}.buttonStyle(.borderless)}
                Slider(value:$damping,in:0...1,step:0.05).accessibilityLabel("拖动阻尼")
                HStack {Text("轻盈 · 易甩动");Spacer();Text("稳重 · 易停住")}.font(.caption).foregroundStyle(.secondary)
                Text("默认 20%。调低会更跟手、松手滑得更远；调高更稳、更快停下。停住鼠标再松手，可精确摆放。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.disabled(!physics)
            Text("只影响纸条之间的互动，不推动其他应用。减少动态效果开启时，自动使用普通拖动。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("随时添一张").font(.title3)
            Toggle("启用全局新建快捷键",isOn:$global)
            Picker("组合",selection:$combination) { ForEach(0..<GlobalShortcut.choices.count,id:\.self){Text(GlobalShortcut.choices[$0]).tag($0)} }.disabled(!global)
            Text(shortcut.status).font(.callout)
            Text("Control＋Option＋Command＋N 为默认组合。应用需要保持运行；⌘N 只在萝卜便签内使用，不接管其他应用的快捷键。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(26)
    }
}
struct SettingsView:View {
    @ObservedObject var focus:FocusStore
    @ObservedObject var shortcut:GlobalShortcut
    var body:some View {
        TabView {
            ScrollView { PaperSettingsView() }.tabItem{Text("纸张与笔迹")}
            InteractionSettingsView(shortcut:shortcut).tabItem{Text("交互与快捷键")}
            FocusSettingsView(focus:focus).tabItem{Text("番茄伙伴")}
        }.padding(10).frame(width:500,height:610)
    }
}
