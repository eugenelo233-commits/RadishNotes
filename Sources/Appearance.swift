import AppKit
import QuartzCore

enum PaperDesign {
    static let tearHotspot: CGFloat = 32
    static let restingCurl: CGFloat = 15
    static var realistic:Bool { AppPreferences.defaults.string(forKey:"paperAppearance") != "classic" }
    static let fiberOpacity: CGFloat = 0.45
    static let recycledOpacity: CGFloat = 0.44
    static let landingTime = 0.15
    static let tearTime = 0.44
    static let undoTime = 10.0
    static let maxAge = 14.0 * 86400
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || AppPreferences.defaults.bool(forKey:"reduceMotion") }
    static var aging: Bool { AppPreferences.defaults.object(forKey:"agingEnabled") as? Bool ?? true }
}
struct PaperRandom {
    var state: UInt64
    mutating func next() -> CGFloat { state = state &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(state >> 32) / CGFloat(UInt32.max) }
}
final class TextureCache {
    static let shared=TextureCache()
    private let cache=NSCache<NSString,NSImage>()
    private init() { cache.countLimit=48;cache.totalCostLimit=32*1024*1024 }
    func image(seed:UInt64,material:String)->NSImage {
        let key="grain4-\(seed)-\(material)" as NSString
        if let result=cache.object(forKey:key) { return result }
        let size=512;let cotton=material=="cotton",recycled=material=="recycled"
        var random=PaperRandom(state:seed)
        // Periodic height field: pulp clouds, granular tooth and tiny fibers. Derivatives
        // provide upper-left lighting instead of flat monochrome noise.
        let coarse=(0..<1024).map{_ in Double(random.next())}
        let fine=(0..<(size*size)).map{_ in Double(random.next())}
        func cloud(_ x:Int,_ y:Int)->Double {
            let fx=Double(x)/16,fy=Double(y)/16;let ix=Int(fx),iy=Int(fy)
            let tx=fx-Double(ix),ty=fy-Double(iy)
            func value(_ a:Int,_ b:Int)->Double { coarse[(b%32)*32+(a%32)] }
            return (value(ix,iy)*(1-tx)+value(ix+1,iy)*tx)*(1-ty)+(value(ix,iy+1)*(1-tx)+value(ix+1,iy+1)*tx)*ty
        }
        var height=[Double](repeating:0,count:size*size)
        for y in 0..<size { for x in 0..<size {
            let i=y*size+x
            let tooth=(fine[i]*0.42 + fine[y*size+(x+1)%size]*0.16 + fine[((y+1)%size)*size+x]*0.16)*(cotton ? 0.55 : recycled ? 0.65 : 0.8)
            let thread=cotton ? (sin(Double(x)*Double.pi/7)+sin(Double(y)*Double.pi/8))*0.32 : 0
            height[i]=tooth+cloud(x,y)*(recycled ? 0.7 : 0.36)+thread
        } }
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
        let pixels=rep.bitmapData!
        for y in 0..<size { for x in 0..<size {
            let i=y*size+x
            let light=(height[i]-height[y*size+(x+size-1)%size])*0.8+(height[i]-height[((y+size-1)%size)*size+x])*0.8
            let luminance=light+(cloud(x,y)-0.5)*(recycled ? 0.32 : 0.11)
            let bright=luminance>0;let alpha=min(0.38,abs(luminance)*(recycled ? 1.2 : cotton ? 1.4 : 0.96))
            let offset=i*4
            pixels[offset]=bright ? 255 : 87;pixels[offset+1]=bright ? 252 : 74;pixels[offset+2]=bright ? 239 : 57;pixels[offset+3]=UInt8(alpha*255)
        } }
        rep.size=NSSize(width:256,height:256)
        let grain=NSImage(size:rep.size);grain.addRepresentation(rep)
        let image=NSImage(size:rep.size);image.lockFocus();grain.draw(at:.zero,from:.zero,operation:.sourceOver,fraction:1)
        // Embedded pulp fibers have a dark contact edge and a light upper ridge.
        for _ in 0..<(recycled ? 820 : cotton ? 430 : 580) {
            let x=random.next()*256,y=random.next()*256
            let length:CGFloat=(recycled ? 1.2 : 2)+random.next()*(recycled ? 7 : 17)
            let angle=random.next()*CGFloat.pi*2
            let end=NSPoint(x:x+cos(angle)*length,y:y+sin(angle)*length*0.45)
            let path=NSBezierPath();path.move(to:NSPoint(x:x,y:y));path.line(to:end);path.lineWidth=recycled ? 0.7 : 0.45
            NSColor(hex:0x77664B).withAlphaComponent(recycled ? 0.25 : 0.19).setStroke();path.stroke()
            let highlight=path.copy() as! NSBezierPath;let transform=AffineTransform(translationByX:-0.3,byY:0.3);highlight.transform(using:transform)
            NSColor.white.withAlphaComponent(0.32).setStroke();highlight.stroke()
            if recycled && random.next()>0.65 {
                NSColor(hex:0x806447).withAlphaComponent(0.25).setFill();NSBezierPath(ovalIn:NSRect(x:x,y:y,width:0.7+random.next()*3,height:0.5+random.next()*1.6)).fill()
            }
        }
        image.unlockFocus();cache.setObject(image,forKey:key,cost:size*size*4);return image
    }
}
final class PaperView: NSView {
    override var isFlipped: Bool { true }
    var note = Note() { didSet { needsDisplay = true } }
    var now = Date() { didSet { needsDisplay = true } }
    var lifted = false { didSet { needsDisplay = true } }
    var tearProgress: CGFloat = 0 { didSet { needsDisplay = true } }
    var tearHovered = false { didSet { needsDisplay = true } }
    var hoverChanged: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    var paperRect: NSRect { NSRect(x:2,y:2,width:bounds.width-7,height:bounds.height-9) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event:NSEvent) { hoverChanged?(true) }
    override func mouseExited(with event:NSEvent) { hoverChanged?(false) }
    func shape(_ r: NSRect) -> NSBezierPath {
        if !PaperDesign.realistic || note.paperStyle == "fiber" { return NSBezierPath(roundedRect:r,xRadius:2,yRadius:2) }
        let p = NSBezierPath(); var random = PaperRandom(state:note.textureSeed)
        p.move(to:NSPoint(x:r.minX,y:r.minY))
        for x in stride(from:r.minX,through:r.maxX,by:7) { p.line(to:NSPoint(x:x,y:r.minY+random.next()*0.6)) }
        for y in stride(from:r.minY,through:r.maxY,by:7) { p.line(to:NSPoint(x:r.maxX-random.next()*0.75,y:y)) }
        for x in stride(from:r.maxX,through:r.minX,by:-7) { p.line(to:NSPoint(x:x,y:r.maxY-random.next()*0.65)) }
        for y in stride(from:r.maxY,through:r.minY,by:-7) { p.line(to:NSPoint(x:r.minX+random.next()*0.65,y:y)) }
        p.close(); return p
    }
    override func draw(_ dirtyRect:NSRect) {
        let rect = paperRect; guard rect.width > 0 else { return }
        let recycled = note.paperStyle == "recycled"
        let age = PaperDesign.aging && note.agingEnabled ? min(1,note.paperAge(at:now)/PaperDesign.maxAge) : 0
        let userColor=(Paper(rawValue:note.color) ?? .cream).color
        let materialColor=NSColor(hex:note.paperStyle == "recycled" ? 0xDDCBB0 : note.paperStyle == "cotton" ? 0xEFE9D9 : 0xF7F1DF)
        let base=PaperDesign.realistic ? materialColor.blended(withFraction:0.40,of:userColor)! : userColor
        let aged = base.blended(withFraction:age*0.13,of:NSColor(hex:0xCFB78B)) ?? base
        let shape = self.shape(rect)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(lifted ? 0.22 : 0.15)
        shadow.shadowOffset = NSSize(width:lifted ? 3 : 1.5,height:lifted ? -4 : -2)
        shadow.shadowBlurRadius = lifted ? 7 : 3; shadow.set()
        aged.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
        // Lower edge is farther from the desk than the glued upper edge.
        let cast = NSBezierPath(); cast.move(to:NSPoint(x:rect.minX+15,y:rect.maxY-3))
        cast.curve(to:NSPoint(x:rect.maxX-6,y:rect.maxY-1),controlPoint1:NSPoint(x:rect.midX,y:rect.maxY+8),controlPoint2:NSPoint(x:rect.maxX-20,y:rect.maxY+6))
        cast.line(to:NSPoint(x:rect.maxX-10,y:rect.maxY-6)); cast.close()
        NSColor.black.withAlphaComponent(lifted ? 0.09 : 0.055).setFill(); cast.fill()
        aged.setFill(); shape.fill()
        NSGraphicsContext.saveGraphicsState(); shape.addClip()
        NSGradient(starting:aged.blended(withFraction:0.08,of:.white)!,ending:aged.blended(withFraction:0.035,of:NSColor(hex:0x7A6950))!)!.draw(in:rect,angle:-45)
        if PaperDesign.realistic {
        let texture = TextureCache.shared.image(seed:note.textureSeed,material:note.paperStyle)
        let strength=AppPreferences.defaults.object(forKey:"textureStrength") as? Double ?? 1.0
        let opacity=CGFloat(min(1.4,max(0.45,strength)))
        for y in stride(from:rect.minY,to:rect.maxY,by:256) {
            for x in stride(from:rect.minX,to:rect.maxX,by:256) { texture.draw(in:NSRect(x:x,y:y,width:256,height:256),from:.zero,operation:.sourceOver,fraction:opacity,respectFlipped:true,hints:nil) }
        }
        }
        // Quiet adhesive strip and warm edge aging; never fade the ink.
        NSGradient(starting:NSColor.white.withAlphaComponent(0.13),ending:.clear)!.draw(in:NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:25),angle:90)
        if age > 0 {
            let edge = NSGradient(starting:NSColor(hex:0x9B6C30).withAlphaComponent(age*0.18),ending:.clear)!
            edge.draw(in:NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:11),angle:90)
            edge.draw(in:NSRect(x:rect.minX,y:rect.maxY-15,width:rect.width,height:15),angle:270)
            if age > 0.4 {
                let crease = NSBezierPath(); crease.move(to:NSPoint(x:rect.maxX-38,y:rect.minY)); crease.line(to:NSPoint(x:rect.maxX,y:rect.minY+35)); crease.lineWidth = 0.7
                NSColor(hex:0x8B7553).withAlphaComponent(age*0.14).setStroke(); crease.stroke()
            }
        }
        let urgency = DeadlineState.evaluate(note,now:now)
        if urgency == .soon || urgency == .urgent || urgency == .overdue {
            let red = urgency == .soon ? NSColor(hex:0xC67A35) : NSColor(hex:0xB5483F)
            NSGradient(starting:red.withAlphaComponent(urgency == .soon ? 0.035 : 0.12),ending:.clear)!.draw(in:NSRect(x:rect.maxX-14,y:rect.minY,width:14,height:rect.height),angle:180)
            red.withAlphaComponent(urgency == .soon ? 0.22 : 0.5).setStroke(); let e = NSBezierPath(); e.move(to:NSPoint(x:rect.maxX-0.8,y:rect.minY+6)); e.line(to:NSPoint(x:rect.maxX-0.8,y:rect.maxY-8)); e.lineWidth=1.3; e.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.48).setStroke(); shape.lineWidth=0.6; shape.stroke()
        NSColor(hex:0x69583D).withAlphaComponent(recycled ? 0.22 : 0.12).setFill(); NSRect(x:rect.minX+1,y:rect.maxY-1,width:rect.width-2,height:recycled ? 1.2 : 0.65).fill()
        drawCurl(in:rect,base:aged)
        if note.pinned { drawPin() }
    }
    func drawCurl(in r:NSRect,base:NSColor) {
        let size = min(min(r.width*0.48,r.height*0.6),PaperDesign.restingCurl + (tearHovered ? 4 : 0) + tearProgress*70)
        let origin = NSPoint(x:r.minX,y:r.maxY)
        let fold=NSBezierPath(); fold.move(to:NSPoint(x:origin.x,y:origin.y-size)); fold.curve(to:NSPoint(x:origin.x+size,y:origin.y),controlPoint1:NSPoint(x:origin.x+size*0.25,y:origin.y-size*0.65),controlPoint2:NSPoint(x:origin.x+size*0.62,y:origin.y-size*0.2)); fold.line(to:NSPoint(x:origin.x+size*0.70,y:origin.y-size*0.74)); fold.close()
        NSGraphicsContext.saveGraphicsState(); let s=NSShadow();s.shadowColor=NSColor.black.withAlphaComponent(0.22);s.shadowOffset=NSSize(width:2,height:-2);s.shadowBlurRadius=3;s.set()
        base.blended(withFraction:0.18,of:.white)!.setFill();fold.fill();NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting:base.blended(withFraction:0.32,of:.white)!,ending:base.blended(withFraction:0.12,of:NSColor(hex:0x867658))!)!.draw(in:fold,angle:-45)
        NSColor.white.withAlphaComponent(0.7).setStroke();fold.lineWidth=0.6;fold.stroke()
    }
    func drawPin() {
        let stem=NSBezierPath();stem.move(to:NSPoint(x:47,y:14));stem.line(to:NSPoint(x:51,y:22));stem.lineWidth=1.3;NSColor(hex:0x6B6058).setStroke();stem.stroke()
        let head=NSBezierPath(ovalIn:NSRect(x:42,y:7,width:10,height:9))
        NSGraphicsContext.saveGraphicsState();let s=NSShadow();s.shadowColor=NSColor.black.withAlphaComponent(0.22);s.shadowOffset=NSSize(width:2,height:-2);s.shadowBlurRadius=2;s.set();NSColor(hex:0xA65543).setFill();head.fill();NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting:NSColor(hex:0xDD927A),ending:NSColor(hex:0x944939))!.draw(in:head,angle:-45)
        NSColor.white.withAlphaComponent(0.6).setFill();NSBezierPath(ovalIn:NSRect(x:44,y:8,width:3,height:2)).fill()
    }
}
