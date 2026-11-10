import AppKit
var count = 0
func check(_ value: Bool, _ name: String) {
    if !value { fputs("FAIL: \(name)\n", stderr); exit(1) }
    count += 1; print("PASS \(count): \(name)")
}
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("RadishNotesTests-\(UUID())")
defer { try? FileManager.default.removeItem(at: temp) }
let store = NoteStore(directory: temp)
check(try store.load() == false, "Missing data reports first launch")
var a = Note(); a.text = "今天安排：中文、English、标点。\n第二行 🥕"; a.color = "sage"; a.fontSize = 19; a.pinned = true; a.completed = true; a.frame = NSRect(x: -600, y: 240, width: 330, height: 110); a.screenID = 88
var b = Note(); b.text = "归档记录"; b.archived = true
store.notes = [a, b]; store.changed(immediate: true)
check(store.saveError == nil, "Atomic JSON write")
let reload = NoteStore(directory: temp)
check(try reload.load(), "Existing data loads")
check(reload.notes == store.notes, "Exact round trip: UUID, text, dates, color, size, frame, flags, screen")
store.update(a.id, immediate: true) { $0.text += "\n修改" }
let backup = try store.decode(Data(contentsOf: store.backup))
check(backup.notes[0].text == a.text, "Backup retains previous valid generation")
store.update(b.id, immediate: true) { $0.archived = false }
check(store.notes[1].id == b.id && !store.notes[1].archived && store.notes.count == 2, "Restore preserves UUID and count")
let corrupt = Data("not json".utf8); try corrupt.write(to: store.file)
let broken = NoteStore(directory: temp)
do { _ = try broken.load(); check(false, "Corrupt read throws") } catch { check(broken.blocked, "Corrupt read blocks all writes") }
broken.changed(immediate: true)
check(try Data(contentsOf: broken.file) == corrupt, "Failed read never silently overwrites source")
try broken.recoverBackup()
check(!broken.blocked && broken.notes.count == 2, "Backup recovery succeeds")
check(try FileManager.default.contentsOfDirectory(atPath: temp.path).contains(where: { $0.hasPrefix("notes.damaged-") }), "Recovery keeps damaged original")
let future = NoteDocument(schemaVersion: 999, notes: [a]); try JSONEncoder().encode(future).write(to: store.file)
let futureStore = NoteStore(directory: temp)
do { _ = try futureStore.load(); check(false, "Future schema rejected") } catch { check(futureStore.blocked, "Unknown schema is write-protected") }
let invalidPath = temp.appendingPathComponent("not-a-directory"); try Data("x".utf8).write(to: invalidPath)
let failStore = NoteStore(directory: invalidPath); failStore.notes = [a]; failStore.changed(immediate: true)
check(failStore.saveError != nil && failStore.dirty, "Disk write failure retains dirty in-memory data and error")
let screen = NSRect(x: 0, y: 30, width: 1440, height: 850)
let visible = NSRect(x: 120, y: 150, width: 330, height: 110)
check(ScreenLayout.fit(visible, in: [screen]) == visible, "Visible frame unchanged")
let outside = NSRect(x: -3000, y: -2000, width: 240, height: 230)
check(screen.contains(ScreenLayout.fit(outside, in: [screen])), "Removed-screen note rescued")
check(screen.contains(ScreenLayout.fit(NSRect(x: 0, y: 0, width: 5000, height: 5000), in: [screen])), "Oversize note bounded to visible screen")
let secondary = NSRect(x: -1920, y: -100, width: 1920, height: 1080)
let onSecond = NSRect(x: -1300, y: 40, width: 300, height: 300)
check(ScreenLayout.fit(onSecond, in: [screen, secondary]) == onSecond, "Negative screen coordinates preserved")
let tiny = ScreenLayout.fit(NSRect(x: 20, y: 40, width: 1, height: 1), in: [screen])
check(tiny.width == 190 && tiny.height == 100, "Minimum editor and drag dimensions enforced")
check(ScreenLayout.fit(visible, in: []) == visible, "No-screen transient preserves frame")


let instant=Date(timeIntervalSince1970:1800000000)
let legacyDirectory=temp.appendingPathComponent("legacy")
try FileManager.default.createDirectory(at:legacyDirectory,withIntermediateDirectories:true)
var legacy=a;legacy.createdAt=instant.addingTimeInterval(-7*86400);legacy.updatedAt=instant.addingTimeInterval(-123);legacy.completed=true
let legacyKeys:Set<String>=["id","text","color","fontSize","x","y","width","height","screenID","pinned","completed","archived","createdAt","updatedAt"]
let json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(legacy)) as! [String:Any]
let oldJSON=json.filter{legacyKeys.contains($0.key)}
let oldData=try JSONSerialization.data(withJSONObject:["schemaVersion":1,"notes":[oldJSON]],options:.sortedKeys)
try oldData.write(to:legacyDirectory.appendingPathComponent("notes.json"))
let migrating=NoteStore(directory:legacyDirectory);migrating.now={instant};_ = try migrating.load()
let converted=try JSONSerialization.jsonObject(with:JSONEncoder().encode(migrating.notes[0])) as! [String:Any]
check(NSDictionary(dictionary:oldJSON).isEqual(to:converted.filter{legacyKeys.contains($0.key)}),"Schema 1 migration preserves every legacy field exactly")
check(try Data(contentsOf:migrating.migrationSnapshot!) == oldData,"Migration snapshot preserves original bytes independently")
check(migrating.notes[0].completedAt == nil && migrating.notes[0].frozenPaperAge == 7*86400,"Legacy completion freezes visual age without invented completion date")
let second=NoteStore(directory:legacyDirectory);_ = try second.load()
check(second.notes==migrating.notes && second.migrationSnapshot == nil,"Schema 2 reload is idempotent")
let tx=NoteStore(directory:temp.appendingPathComponent("transaction"));tx.now={instant}
var task=Note();task.text="写完今天的段落";task.dueAt=instant.addingTimeInterval(7200);task.reminderEnabled=true;task.advanceMinutes=30;task.createdAt=instant.addingTimeInterval(-3*86400);task.chineseFont="chenyu";task.latinFont="kalam";task.paperStyle="recycled";task.color="kraft"
tx.notes=[task];tx.changed(immediate:true)
var commits=0;tx.onCommit={ _ in commits += 1 }
let saved=try Data(contentsOf:tx.file)
tx.beforeWrite={throw NSError(domain:"InjectedWriteFailure",code:1)}
check(!tx.tear(task.id) && tx.notes[0]==task && commits==0,"Failed tear retains state and does not notify scheduler")
check(try Data(contentsOf:tx.file)==saved,"Failed tear leaves durable document intact")
tx.beforeWrite=nil
check(tx.tear(task.id) && tx.notes[0].archived && tx.notes[0].completed && commits==1,"Tear commits completion and archive together")
check(ReminderPlan.requests(for:tx.notes[0],now:instant).isEmpty,"Committed completion cancels future reminders")
let tornRevision=tx.notes[0].revision
check(tx.undoTear() && tx.notes[0].revision==tornRevision+1,"Undo is a new revision")
var undone=tx.notes[0];undone.revision=task.revision;undone.updatedAt=task.updatedAt
check(undone==task,"Undo restores complete pre-tear snapshot, same UUID and layout")
check(ReminderPlan.requests(for:tx.notes[0],now:instant).count==2,"Undo restores only future reminder nodes")
_ = tx.tear(task.id);tx.update(task.id,immediate:true){$0.text="之后的新内容"}
check(!tx.canUndoTear && !tx.undoTear() && tx.notes[0].text=="之后的新内容","Old undo cannot overwrite a subsequent edit")
var archive=task;archive.archived=true
check(ReminderPlan.requests(for:archive,now:instant).count==2,"Archiving unfinished note keeps both reminders")
let plans=ReminderPlan.requests(for:task,now:instant)
var later=task;later.dueAt=task.dueAt!.addingTimeInterval(3600)
let laterPlans=ReminderPlan.requests(for:later,now:instant)
check(plans.map(\.id)==laterPlans.map(\.id) && plans.map(\.fingerprint) != laterPlans.map(\.fingerprint),"Reschedule replaces stable IDs with new fingerprints")
check(ReminderPlan.requests(for:task,now:instant.addingTimeInterval(5500)).count==1,"Past advance node is never replayed")
check(ReminderPlan.requests(for:task,now:instant.addingTimeInterval(7201)).isEmpty,"Past due node is never replayed after restart")
var timed=task
for (delta,state) in [(10801.0,DeadlineState.distant),(10800,.soon),(1800,.urgent),(0,.overdue)] { timed.dueAt=instant.addingTimeInterval(delta);check(DeadlineState.evaluate(timed,now:instant)==state,"Deadline boundary \(delta) seconds") }
let age=timed.paperAge(at:instant);timed.dueAt=instant.addingTimeInterval(99999)
check(timed.color==task.color && timed.paperAge(at:instant)==age,"Deadline postponement preserves base paper and age")
timed.setCompleted(true,at:instant)
check(timed.paperAge(at:instant.addingTimeInterval(86400))==age && DeadlineState.evaluate(timed,now:instant) == .none,"Completion freezes age and ends deadline alert")
let completion=timed.completedAt;let created=timed.createdAt;let due=timed.dueAt
timed.renewPaper(at:instant.addingTimeInterval(500))
check(timed.paperAge(at:instant.addingTimeInterval(900))==0 && timed.completedAt==completion && timed.createdAt==created && timed.dueAt==due,"Renew completed paper resets visual age only")
timed.setCompleted(false,at:instant.addingTimeInterval(1000))
check(timed.paperAge(at:instant.addingTimeInterval(1500))==1000,"Uncomplete renewed paper uses new paper origin")
var gesture=TearGesture();gesture.begin();gesture.update(dx:3,dy:3)
check(!gesture.release(),"Short click does not tear")
gesture.begin();gesture.update(dx:60,dy:60)
check(gesture.ready && gesture.active,"Threshold crossing remains preview until release")
gesture.update(dx:10,dy:10);check(!gesture.release(),"Dragging back cancels at release")
gesture.begin();gesture.update(dx:80,dy:80);gesture.cancel();check(!gesture.release(),"Esc/cancellation never commits")
gesture.begin();gesture.update(dx:-20,dy:180);check(!gesture.release(),"Wrong direction cannot accumulate tear progress")
gesture.begin();gesture.update(dx:60,dy:60);check(gesture.release(),"Valid direction and release commits")
var fractional=task;fractional.dueAt=Date().addingTimeInterval(3600)
let roundTrip=try JSONDecoder().decode(Note.self,from:JSONEncoder().encode(fractional))
check(ReminderPlan.requests(for:fractional,now:instant).map(\.fingerprint)==ReminderPlan.requests(for:roundTrip,now:instant).map(\.fingerprint),"Notification fingerprints survive JSON date precision round trip")


var random=SystemRandomNumberGenerator();var previous:PaperChoice?=nil;var materialSet=Set<String>()
for _ in 0..<100 {
 let next=PaperChoice.random(after:previous,using:&random)
 if let previous { if next.color==previous.color || next.material==previous.material { check(false,"Random paper must vary both color and material") } }
 materialSet.insert(next.material);previous=next
}
check(materialSet.count==3,"Random paper visits three materials and avoids repeating both choices")
let physicsScreen=CGRect(x:0,y:0,width:1400,height:900)
let id1=UUID(),id2=UUID();let left=PaperBody(id:id1,frame:CGRect(x:100,y:200,width:220,height:200));let right=PaperBody(id:id2,frame:CGRect(x:360,y:200,width:220,height:200))
var world=PaperPhysicsWorld(bodies:[left,right]);world.begin(id1,target:CGPoint(x:230,y:200));world.advance(1.0/60,screens:[physicsScreen])
check(world.bodies[0].frame.minX>100 && world.bodies[0].frame.minX<230,"Physical dragging follows with spring lag")
for _ in 0..<30 { world.advance(1.0/60,screens:[physicsScreen]) }
check(world.collisionCount>0 && world.bodies[1].frame.minX>right.frame.minX,"A new collision transfers momentum to the other note")
let beforeRelease=world.bodies[0].frame;world.release(velocity:CGPoint(x:400,y:0));world.advance(1.0/60,screens:[physicsScreen])
check(world.bodies[0].frame != beforeRelease,"Release preserves short inertial movement")
for _ in 0..<360 { world.advance(1.0/60,screens:[physicsScreen]) }
check(!world.moving && world.bodies.allSatisfy{physicsScreen.contains($0.frame)},"Friction settles all notes inside visible bounds")
let stack2=PaperBody(id:id2,frame:left.frame.offsetBy(dx:40,dy:20));var stack=PaperPhysicsWorld(bodies:[left,stack2]);let originalStack=stack.bodies.map(\.frame)
for _ in 0..<120 { stack.advance(1.0/60,screens:[physicsScreen]) }
check(stack.bodies.map(\.frame)==originalStack,"Enabling physics does not unpack existing overlaps")
var bounce=PaperPhysicsWorld(bodies:[PaperBody(id:id1,frame:CGRect(x:1150,y:200,width:220,height:200),velocity:CGPoint(x:700,y:0),active:true)])
for _ in 0..<90 { bounce.advance(1.0/60,screens:[physicsScreen]) }
check(physicsScreen.contains(bounce.bodies[0].frame),"Throwing against screen edge stays recoverable")
// Measured trajectories on a roomy surface; verify the user-visible tuning effect.
let roomy=CGRect(x:0,y:0,width:10000,height:3000)
func followDistance(_ damping:Double)->CGFloat {
    var w=PaperPhysicsWorld(bodies:[left],tuning:PaperMotionTuning(damping:damping))
    w.begin(id1,target:CGPoint(x:200,y:200))
    for _ in 0..<12 { w.advance(1.0/120,screens:[roomy]) }
    return w.bodies[0].frame.minX-100
}
let defaultFollow=followDistance(PaperMotionTuning.defaultDamping)
check(defaultFollow>93 && defaultFollow<100,"Default follows a 100pt hand movement within 7pt after 100ms without overshoot")
check(followDistance(0)>followDistance(1)+10,"Lower damping responds faster while held")
func glideDistance(_ damping:Double)->CGFloat {
    var w=PaperPhysicsWorld(bodies:[left],tuning:PaperMotionTuning(damping:damping))
    w.begin(id1,target:left.frame.origin);w.release(velocity:CGPoint(x:800,y:0))
    for _ in 0..<600 {w.advance(1.0/120,screens:[roomy])}
    return w.bodies[0].frame.minX-left.frame.minX
}
let lightGlide=glideDistance(0),defaultGlide=glideDistance(0.2),heavyGlide=glideDistance(1)
check(lightGlide>defaultGlide && defaultGlide>heavyGlide*2.5,"Damping produces a clearly ordered glide range")
check(defaultGlide>280 && defaultGlide<400,"A moderate default flick travels a useful controlled distance")
var placement=PaperPhysicsWorld(bodies:[left]);placement.begin(id1,target:CGPoint(x:200,y:200));placement.advance(0.03,screens:[roomy]);placement.release(velocity:.zero)
let placed=placement.bodies[0].frame;placement.advance(0.05,screens:[roomy])
check(placement.bodies[0].frame==placed && !placement.moving,"Stopping the hand before release prevents residual spring drift")
var hand=PaperPointerMotion();hand.begin(at:.zero,time:0);hand.update(CGPoint(x:30,y:0),time:2)
check(hand.released(at:2.02).x>800,"Holding before a short flick does not dilute release velocity")
check(hand.released(at:2.3) == .zero,"A deliberate pause cancels fling velocity")
hand.update(CGPoint(x:10,y:0),time:2.04)
check(hand.released(at:2.05).x<0,"Release follows the latest hand direction after reversing")
check(PaperMotionTuning(damping:.nan).damping==0.2 && PaperMotionTuning(damping:5).damping==1 && PaperMotionTuning(damping:-1).damping==0,"Corrupt or out-of-range damping safely clamps")
print("MOTION METRICS: default 100ms follow=\(defaultFollow)pt / 100pt; 800pt/s flick distances low=\(lightGlide), default=\(defaultGlide), high=\(heavyGlide)pt")
var focus=FocusState();focus.start(at:instant)
check(focus.running && focus.remaining(at:instant.addingTimeInterval(20))==1480,"Pomodoro derives remaining time from absolute end")
focus.pause(at:instant.addingTimeInterval(20));check(!focus.running && focus.remaining==1480 && focus.remaining(at:instant.addingTimeInterval(500))==1480,"Pause freezes progress")
focus.start(at:instant.addingTimeInterval(500));check(!focus.finishIfDue(at:instant.addingTimeInterval(1979)),"Focus cannot finish before deadline")
check(focus.finishIfDue(at:instant.addingTimeInterval(1980)) && focus.tomatoes==1 && focus.phase == .shortBreak && !focus.running,"Finish awards one tomato and waits for explicit break start")
check(!focus.finishIfDue(at:instant.addingTimeInterval(9999)) && focus.tomatoes==1,"Repeated tick never duplicates completion reward")
for _ in 0..<3 { focus.phase = .focus;focus.reset();focus.start(at:instant);_ = focus.finishIfDue(at:instant.addingTimeInterval(1500)) }
check(focus.tomatoes==4 && focus.phase == .longBreak && focus.remaining==900,"Every fourth tomato offers a long break")
check(StudyRules.allowed(host:"www.notion.so",domains:["notion.so"]),"Study domain includes real subdomains")
check(!StudyRules.allowed(host:"notion.so.attacker.example",domains:["notion.so"]) && !StudyRules.allowed(host:"fakenotion.so",domains:["notion.so"]),"Domain match rejects lookalike suffixes")
check(StudyRules.evaluate(appID:"notion.id",name:"Notion",edgeHost:nil,edgeError:nil,state:focus) == .allowed,"Native Notion is allowed without reading content")
check(StudyRules.evaluate(appID:"com.microsoft.edgemac",name:"Edge",edgeHost:"chatgpt.com",edgeError:nil,state:focus) == .allowed,"Edge ChatGPT domain is allowed")
if case .unknown=StudyRules.evaluate(appID:"com.microsoft.edgemac",name:"Edge",edgeHost:nil,edgeError:"permission denied",state:focus) { check(true,"Denied Edge permission is unknown, not distraction") } else { check(false,"Denied Edge permission is unknown") }
check(StudyRules.evaluate(appID:"com.microsoft.edgemac",name:"Edge",edgeHost:"www.bilibili.com",edgeError:nil,state:focus,temporary:["www.bilibili.com"]) == .allowed,"Course video can be temporarily allowed")
var tracker=DistractionTracker();tracker.update(.outside("Video"),at:instant)
check(!tracker.shouldWarn(at:instant.addingTimeInterval(29),grace:30),"Brief detour stays within grace period")
check(tracker.shouldWarn(at:instant.addingTimeInterval(30),grace:30) && !tracker.shouldWarn(at:instant.addingTimeInterval(60),grace:30),"Warn once per excursion after grace")
tracker.update(.allowed,at:instant.addingTimeInterval(70));check(tracker.since==nil && !tracker.warned,"Returning to study clears the excursion")
tracker.update(.unknown("permission"),at:instant);check(!tracker.shouldWarn(at:instant.addingTimeInterval(120),grace:30),"Unknown browser state never causes a warning")
check(try JSONDecoder().decode(FocusState.self,from:JSONEncoder().encode(focus))==focus,"Focus preferences and session state round trip")
print("ALL \(count) CHECKS PASSED")
