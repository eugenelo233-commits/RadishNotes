import AppKit
import Carbon
import Combine

final class GlobalShortcut:ObservableObject {
    @Published var status=""
    private var hotKey:EventHotKeyRef?
    private var handler:EventHandlerRef?
    private var configuration=""
    var action:(()->Void)?
    static let choices=["⌃⌥⌘ N","⌃⌥⌘ J","⌃⌥⇧ N"]
    init() {
        var event=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        let pointer=Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),{ _,event,context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner=Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { owner.action?() };return noErr
        },1,&event,pointer,&handler)
        update()
    }
    func update() {
        let config="\(AppPreferences.defaults.object(forKey:"globalNewNote") as? Bool ?? true)|\(AppPreferences.defaults.integer(forKey:"globalShortcutChoice"))"
        guard config != configuration else { return };configuration=config
        if let hotKey { UnregisterEventHotKey(hotKey);self.hotKey=nil }
        guard AppPreferences.defaults.object(forKey:"globalNewNote") as? Bool ?? true else { status="全局快捷键已关闭";return }
        let choice=max(0,min(2,AppPreferences.defaults.integer(forKey:"globalShortcutChoice")))
        let key:UInt32=UInt32(choice==1 ? kVK_ANSI_J : kVK_ANSI_N)
        let modifiers=UInt32(controlKey | optionKey | (choice==2 ? shiftKey : cmdKey))
        let id=EventHotKeyID(signature:0x52445348,id:1)
        let result=RegisterEventHotKey(key,modifiers,id,GetApplicationEventTarget(),0,&hotKey)
        status=result==noErr ? "已注册 \(Self.choices[choice]) · 应用运行时全局可用" : "快捷键未注册（\(result)），可能已被其他应用占用，请换一个组合。"
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) };if let handler { RemoveEventHandler(handler) } }
}
