import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(srgbRed: 0.96, green: 0.90, blue: 0.75, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 188, yRadius: 188).fill()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.15); shadow.shadowOffset = NSSize(width: 0, height: -15); shadow.shadowBlurRadius = 30
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor(srgbRed: 1, green: 0.97, blue: 0.85, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 218, y: 208, width: 588, height: 614), xRadius: 20, yRadius: 20).fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(srgbRed: 0.87, green: 0.50, blue: 0.27, alpha: 1).setFill()
let carrot = NSBezierPath(); carrot.move(to: NSPoint(x: 386, y: 590)); carrot.curve(to: NSPoint(x: 617, y: 590), controlPoint1: NSPoint(x: 410, y: 692), controlPoint2: NSPoint(x: 590, y: 692)); carrot.curve(to: NSPoint(x: 475, y: 337), controlPoint1: NSPoint(x: 655, y: 514), controlPoint2: NSPoint(x: 532, y: 344)); carrot.curve(to: NSPoint(x: 386, y: 590), controlPoint1: NSPoint(x: 422, y: 367), controlPoint2: NSPoint(x: 363, y: 502)); carrot.close(); carrot.fill()
NSColor(srgbRed: 0.38, green: 0.51, blue: 0.34, alpha: 1).setStroke()
for (end, c) in [(NSPoint(x: 436, y: 744), NSPoint(x: 448, y: 706)), (NSPoint(x: 546, y: 770), NSPoint(x: 516, y: 719)), (NSPoint(x: 610, y: 716), NSPoint(x: 567, y: 695))] {
 let leaf = NSBezierPath(); leaf.move(to: NSPoint(x: 507, y: 637)); leaf.curve(to: end, controlPoint1: c, controlPoint2: end); leaf.lineWidth = 25; leaf.lineCapStyle = .round; leaf.stroke()
}
NSColor.white.withAlphaComponent(0.45).setStroke()
for (x,y) in [(404,565), (482,480)] { let p = NSBezierPath(); p.move(to: NSPoint(x:x,y:y)); p.line(to: NSPoint(x:x+65,y:y-18)); p.lineWidth = 12; p.lineCapStyle = .round; p.stroke() }
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
