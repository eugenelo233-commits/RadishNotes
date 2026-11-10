import AppKit
import QuartzCore

final class TearCorner: NSView {
    weak var controller: NoteWindowController?
    var gesture = TearGesture()
    private var start = NSPoint.zero
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self);addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { controller?.paper.tearHovered=true; toolTip="拉动纸角，撕下并完成" }
    override func mouseExited(with event:NSEvent) { if !gesture.active { controller?.paper.tearHovered=false } }
    override func mouseDown(with event:NSEvent) {
        guard let controller,controller.prepareTear(),let window else { return }
        start=window.convertPoint(toScreen:event.locationInWindow);gesture.begin()
        controller.tearPreview(0,ready:false);RuntimeEvidence.event(controller,"begin")
    }
    override func mouseDragged(with event:NSEvent) {
        guard gesture.active,let window else { return }
        let point=window.convertPoint(toScreen:event.locationInWindow)
        gesture.update(dx:point.x-start.x,dy:point.y-start.y)
        controller?.tearPreview(gesture.progress,ready:gesture.ready)
        if let controller { RuntimeEvidence.event(controller,"preview") }
    }
    override func mouseUp(with event:NSEvent) {
        guard gesture.active else { return }
        if let controller { RuntimeEvidence.event(controller,"before-release") }
        let commit=gesture.release()
        if commit { controller?.commitTear() } else { cancel() }
    }
    func cancel() { gesture.cancel();controller?.tearPreview(0,ready:false);controller?.paper.tearHovered=false;controller?.refreshTime();if let controller { RuntimeEvidence.event(controller,"cancelled") } }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.openHand) }
}
final class ToastPanel: NSPanel {
    override var canBecomeKey:Bool { false }
    override var canBecomeMain:Bool { false }
}
final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
}
final class UndoToast: NSObject {
    var window: ToastPanel?
    var work: DispatchWorkItem?
    var undo:(()->Void)?
    init(frame:NSRect,action:@escaping()->Void) {
        super.init();undo=action
        var r=NSRect(x:frame.midX-125,y:frame.minY+10,width:250,height:38)
        if let screen=ScreenLayout.frames.first(where:{$0.intersects(frame)}) { r.origin.x=min(max(r.minX,screen.minX),screen.maxX-r.width);r.origin.y=min(max(r.minY,screen.minY),screen.maxY-r.height) }
        let p=ToastPanel(contentRect:r,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.backgroundColor=NSColor(hex:0xF6F0E4);p.isOpaque=true;p.hasShadow=true;p.level = .floating;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
        p.collectionBehavior=[.stationary,.fullScreenNone,.ignoresCycle]
        let label=NSTextField(labelWithString:"已撕下");label.font = .systemFont(ofSize:13);label.frame=NSRect(x:14,y:11,width:120,height:19)
        let button=FirstClickButton(title:"撤销",target:self,action:#selector(restore));button.bezelStyle = .rounded;button.frame=NSRect(x:170,y:5,width:66,height:28)
        p.contentView?.appearance=NSAppearance(named:.aqua);p.contentView?.addSubview(label);p.contentView?.addSubview(button);p.orderFront(nil);window=p
        if let image=RuntimeEvidence.image(p.contentView!) { RuntimeEvidence.save(image,name:"undo-toast") }
        let job=DispatchWorkItem { [weak self] in self?.close() };work=job;DispatchQueue.main.asyncAfter(deadline:.now()+PaperDesign.undoTime,execute:job)
    }
    @objc func restore() { undo?();close() }
    func close() { work?.cancel();window?.orderOut(nil);window=nil }
}
