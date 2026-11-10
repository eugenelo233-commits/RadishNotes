import Foundation

struct PaperMotionTuning {
    static let defaultDamping=0.2
    let damping:Double
    init(damping:Double=Self.defaultDamping) { self.damping=damping.isFinite ? min(1,max(0,damping)) : Self.defaultDamping }
    var frequency:CGFloat { CGFloat(52-24*damping) }
    var friction:CGFloat { CGFloat(1.8+6.2*damping) }
    var throwGain:CGFloat { CGFloat(1.35-0.45*damping) }
    var maximumThrowSpeed:CGFloat { CGFloat(1800-600*damping) }
}
struct PaperPointerMotion {
    private var point=CGPoint.zero
    private var time=0.0
    private var velocity=CGPoint.zero
    mutating func begin(at point:CGPoint,time:Double) {self.point=point;self.time=time;velocity = .zero}
    mutating func update(_ point:CGPoint,time:Double) {
        // A pause before the first drag must not dilute a quick flick. Native event
        // intervals remain untouched in the usual 30–240 Hz range.
        let dt=max(1.0/240,min(1.0/30,time-self.time))
        let sample=PaperPhysicsWorld.clamp(CGPoint(x:(point.x-self.point.x)/dt,y:(point.y-self.point.y)/dt),to:2200)
        let fresh=time-self.time>0.1
        velocity=CGPoint(x:sample.x*(fresh ? 1 : 0.85)+velocity.x*(fresh ? 0 : 0.15),y:sample.y*(fresh ? 1 : 0.85)+velocity.y*(fresh ? 0 : 0.15))
        self.point=point;self.time=time
    }
    func released(at time:Double)->CGPoint {
        let age=max(0,time-self.time)
        let gain=CGFloat(max(0,min(1,(0.14-age)/0.08)))
        return CGPoint(x:velocity.x*gain,y:velocity.y*gain)
    }
}
struct PaperBody {
    var id:UUID
    var frame:CGRect
    var velocity=CGPoint.zero
    var active=false
    var mass:CGFloat { min(2.5,max(0.65,frame.width*frame.height/70000)) }
}
struct PaperPair:Hashable {
    var first:UUID;var second:UUID
    init(_ a:UUID,_ b:UUID) { if a.uuidString<b.uuidString { first=a;second=b } else { first=b;second=a } }
}
struct PaperPhysicsWorld {
    var bodies:[PaperBody]
    var tuning:PaperMotionTuning
    var dragged:UUID?
    var target:CGPoint?
    var preexistingOverlaps=Set<PaperPair>()
    private(set) var collisionCount=0
    init(bodies:[PaperBody],tuning:PaperMotionTuning=PaperMotionTuning()) {
        self.bodies=bodies;self.tuning=tuning
        for i in bodies.indices { for j in bodies.indices where j>i {
            if bodies[i].frame.intersects(bodies[j].frame) { preexistingOverlaps.insert(PaperPair(bodies[i].id,bodies[j].id)) }
        } }
    }
    mutating func begin(_ id:UUID,target:CGPoint) { dragged=id;self.target=target;if let i=bodies.firstIndex(where:{$0.id==id}) { bodies[i].active=true } }
    mutating func release(velocity:CGPoint) {
        if let i=bodies.firstIndex(where:{$0.id==dragged}) {
            // Release direction comes from the hand, not the lagging spring. Stopping
            // the hand before releasing must also stop a deliberate placement.
            let v=CGPoint(x:velocity.x*tuning.throwGain,y:velocity.y*tuning.throwGain)
            bodies[i].velocity=Self.clamp(v,to:tuning.maximumThrowSpeed)
        };dragged=nil;target=nil
    }
    static func clamp(_ v:CGPoint,to speed:CGFloat)->CGPoint {
        let length=hypot(v.x,v.y);return length>speed ? CGPoint(x:v.x*speed/length,y:v.y*speed/length) : v
    }
    var moving:Bool { dragged != nil || bodies.contains{$0.active} }
    mutating func advance(_ elapsed:Double,screens:[CGRect]) {
        let duration=min(max(elapsed,0),0.05);let steps=max(1,Int(ceil(duration*120)));let dt=CGFloat(duration/Double(steps))
        for _ in 0..<steps { step(dt,screens:screens) }
    }
    private mutating func step(_ dt:CGFloat,screens:[CGRect]) {
        for i in bodies.indices where bodies[i].active || bodies[i].id==dragged {
            if bodies[i].id==dragged,let target {
                let dx=target.x-bodies[i].frame.minX;let dy=target.y-bodies[i].frame.minY
                let omega=tuning.frequency
                // Exact critically damped step: responsive even at low input rates,
                // without numerical spring overshoot at the lightest setting.
                let decay=exp(-omega*dt)
                let cx=bodies[i].velocity.x-omega*dx,cy=bodies[i].velocity.y-omega*dy
                let nextX=target.x+(-dx+cx*dt)*decay,nextY=target.y+(-dy+cy*dt)*decay
                bodies[i].velocity=Self.clamp(CGPoint(x:(bodies[i].velocity.x-omega*cx*dt)*decay,y:(bodies[i].velocity.y-omega*cy*dt)*decay),to:3600)
                bodies[i].frame.origin=CGPoint(x:nextX,y:nextY)
            } else {
                let friction=exp(-tuning.friction*dt);bodies[i].velocity.x *= friction;bodies[i].velocity.y *= friction
            }
            if bodies[i].id != dragged {
                bodies[i].frame.origin.x += bodies[i].velocity.x*dt;bodies[i].frame.origin.y += bodies[i].velocity.y*dt
            }
            if bodies[i].id != dragged,let screen=screens.max(by:{ a,b in
                let aa=a.intersection(bodies[i].frame),bb=b.intersection(bodies[i].frame)
                return (aa.isNull ? 0 : aa.width*aa.height)<(bb.isNull ? 0 : bb.width*bb.height)
            }) {
                let maxX=max(screen.minX,screen.maxX-bodies[i].frame.width),maxY=max(screen.minY,screen.maxY-bodies[i].frame.height)
                if bodies[i].frame.minX<screen.minX { bodies[i].frame.origin.x=screen.minX;bodies[i].velocity.x=abs(bodies[i].velocity.x)*0.28 }
                if bodies[i].frame.minX>maxX { bodies[i].frame.origin.x=maxX;bodies[i].velocity.x = -abs(bodies[i].velocity.x)*0.28 }
                if bodies[i].frame.minY<screen.minY { bodies[i].frame.origin.y=screen.minY;bodies[i].velocity.y=abs(bodies[i].velocity.y)*0.28 }
                if bodies[i].frame.minY>maxY { bodies[i].frame.origin.y=maxY;bodies[i].velocity.y = -abs(bodies[i].velocity.y)*0.28 }
            }
        }
        for i in bodies.indices { for j in bodies.indices where j>i {
            let pair=PaperPair(bodies[i].id,bodies[j].id)
            let overlap=bodies[i].frame.intersection(bodies[j].frame)
            if overlap.isNull || overlap.width<=0 || overlap.height<=0 { preexistingOverlaps.remove(pair);continue }
            // Opening the app or enabling this mode must never unpack the user's existing stack.
            if preexistingOverlaps.contains(pair) || (!bodies[i].active && !bodies[j].active) { continue }
            let horizontal=overlap.width<overlap.height
            let sign:CGFloat = horizontal ? (bodies[i].frame.midX<bodies[j].frame.midX ? 1 : -1) : (bodies[i].frame.midY<bodies[j].frame.midY ? 1 : -1)
            let normal=CGPoint(x:horizontal ? sign : 0,y:horizontal ? 0 : sign)
            let inverseA:CGFloat=bodies[i].id==dragged ? 0.18 : 1/bodies[i].mass
            let inverseB:CGFloat=bodies[j].id==dragged ? 0.18 : 1/bodies[j].mass
            let correction=max(0,(horizontal ? overlap.width : overlap.height)-0.15)*0.9/(inverseA+inverseB)
            bodies[i].frame.origin.x -= normal.x*correction*inverseA;bodies[i].frame.origin.y -= normal.y*correction*inverseA
            bodies[j].frame.origin.x += normal.x*correction*inverseB;bodies[j].frame.origin.y += normal.y*correction*inverseB
            let relative=(bodies[j].velocity.x-bodies[i].velocity.x)*normal.x+(bodies[j].velocity.y-bodies[i].velocity.y)*normal.y
            if relative<0 {
                let impulse = -(1+CGFloat(0.52))*relative/(inverseA+inverseB)
                bodies[i].velocity.x -= normal.x*impulse*inverseA;bodies[i].velocity.y -= normal.y*impulse*inverseA
                bodies[j].velocity.x += normal.x*impulse*inverseB;bodies[j].velocity.y += normal.y*impulse*inverseB
                bodies[i].active=true;bodies[j].active=true;collisionCount += 1
            }
        } }
        for i in bodies.indices where bodies[i].id != dragged {
            if hypot(bodies[i].velocity.x,bodies[i].velocity.y)<2 { bodies[i].velocity = .zero;bodies[i].active=false }
        }
    }
}
