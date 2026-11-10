import AppKit
import QuartzCore

final class PaperPhysics {
    unowned let app:AppDelegate
    var world:PaperPhysicsWorld?
    private var timer:Timer?
    private var lastTick=0.0
    private var pointerMotion=PaperPointerMotion()
    private var startingFrames:[UUID:CGRect]=[:]
    private var frameCount=0
    var isApplying=false
    var isRunning:Bool { world != nil }
    var enabled:Bool { AppPreferences.defaults.bool(forKey:"paperPhysics") && !PaperDesign.reduceMotion }
    var tuning:PaperMotionTuning { PaperMotionTuning(damping:AppPreferences.defaults.object(forKey:"paperDragDamping") as? Double ?? PaperMotionTuning.defaultDamping) }
    init(app:AppDelegate) { self.app=app }
    func begin(_ c:NoteWindowController,time:Double) {
        stop()
        let bodies=app.store.notes.compactMap { n -> PaperBody? in
            guard !n.archived,let controller=app.controllers[n.id],let w=controller.window,w.isVisible,!controller.editor.hasMarkedText() else { return nil }
            return PaperBody(id:n.id,frame:w.frame)
        }
        startingFrames=Dictionary(uniqueKeysWithValues:bodies.map{($0.id,$0.frame)})
        world=PaperPhysicsWorld(bodies:bodies,tuning:tuning);world?.begin(c.id,target:c.window!.frame.origin)
        pointerMotion.begin(at:c.window!.frame.origin,time:time);lastTick=CACurrentMediaTime();frameCount=0
        let t=Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in self?.tick() };timer=t;RunLoop.main.add(t,forMode:.common)
    }
    func target(_ point:CGPoint,time:Double) {
        guard world != nil else { return }
        pointerMotion.update(point,time:time)
        world?.target=point
    }
    func release(time:Double) {world?.release(velocity:pointerMotion.released(at:time))}
    private func tick() {
        guard enabled,let current=world else { stop();return }
        let now=CACurrentMediaTime();let dt=now-lastTick;lastTick=now
        if current.bodies.contains(where:{app.controllers[$0.id]==nil}) { stop();return }
        world?.tuning=tuning
        world?.advance(dt,screens:ScreenLayout.frames)
        isApplying=true
        for body in world?.bodies ?? [] {
            guard let c=app.controllers[body.id],let w=c.window else { continue }
            if w.frame.origin != body.frame.origin { w.setFrameOrigin(body.frame.origin) }
            c.paper.lifted=body.active
        }
        isApplying=false;frameCount += 1
        if RuntimeEvidence.folder != nil,frameCount==6 || frameCount==18 {
            for body in world?.bodies ?? [] where body.active { if let c=app.controllers[body.id],let image=RuntimeEvidence.image(c.paper) { RuntimeEvidence.save(image,name:"physics-frame-\(frameCount)-\(body.id)") } }
        }
        if world?.moving != true { stop() }
    }
    func stop() {
        timer?.invalidate();timer=nil
        guard let completed=world else { return }
        world=nil;isApplying=false
        for body in completed.bodies {
            if let c=app.controllers[body.id] {
                c.paper.lifted=false
                if let w=c.window {
                    let fit=ScreenLayout.fit(w.frame,in:ScreenLayout.frames)
                    c.applying=true;w.setFrame(fit,display:true);c.applying=false;c.captureFrame()
                }
            }
        }
        app.store.flush()
        if let folder=RuntimeEvidence.folder {
            let data:[String:Any]=["frames":frameCount,"damping":completed.tuning.damping,"collisions":completed.collisionCount,"bodies":completed.bodies.map{["id":$0.id.uuidString,"before":NSStringFromRect(startingFrames[$0.id] ?? .zero),"after":NSStringFromRect(app.controllers[$0.id]?.window?.frame ?? $0.frame)]}]
            if let json=try? JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]) { try? json.write(to:folder.appendingPathComponent("physics-result.json")) }
        }
    }
}
