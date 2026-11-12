// Logic checks for Sources/Awning/Policy.swift. Run: ./run.sh --checks
import Foundation

var failures = 0
var passes = 0
func check(_ ok: Bool, _ name: String) {
    if ok { passes += 1 } else { failures += 1; print("FAIL: \(name)") }
}

// MARK: Motion timing

let open = MotionPolicy.openDuration
check(open >= 0.15 && open <= 0.2, "open duration is 0.15-0.2 s")
check(MotionPolicy.feedbackDuration >= 0.15 && MotionPolicy.feedbackDuration <= 0.2, "feedback duration is 0.15-0.2 s")

let states: [IslandState] = [.collapsed, .hovered, .expanded]
for from in states {
    for to in states {
        let d = MotionPolicy.duration(from: from, to: to, reduceMotion: false)
        if to.rank > from.rank {
            check(d == open, "\(from) -> \(to) animates \(open) s")
        } else {
            check(d == 0, "\(from) -> \(to) is instant (closing or no change)")
        }
        check(MotionPolicy.duration(from: from, to: to, reduceMotion: true) == 0,
              "\(from) -> \(to) is instant with Reduce Motion")
    }
}
check(MotionPolicy.duration(showing: true, reduceMotion: false) == open, "show animates")
check(MotionPolicy.duration(showing: false, reduceMotion: false) == 0, "hide is instant")
check(MotionPolicy.duration(showing: true, reduceMotion: true) == 0, "show is instant with Reduce Motion")
check(MotionPolicy.feedback(reduceMotion: true) == 0, "feedback is instant with Reduce Motion")

// MARK: Session gate

do {
    var g = SessionGate()
    check(!g.isSuspended, "starts active")
    check(g.handle(.screenLocked) == .suspend, "lock suspends")
    check(g.handle(.screenLocked) == nil, "duplicate lock is ignored")
    check(g.handle(.screensSlept) == nil, "sleep while locked: already suspended")
    check(g.handle(.screensWoke) == nil, "wake while still locked stays suspended")
    check(g.handle(.screenUnlocked) == .resume, "unlock after wake resumes")
}
do {
    var g = SessionGate()
    check(g.handle(.screensSlept) == .suspend, "display sleep suspends")
    check(g.handle(.screensWoke) == .resume, "display wake resumes")
}
do {
    var g = SessionGate()
    _ = g.handle(.systemWillSleep)
    _ = g.handle(.screensSlept)
    check(g.handle(.systemDidWake) == nil, "system wake with screens still off stays suspended")
    check(g.handle(.screensWoke) == .resume, "screens wake resumes")
}
do {
    var g = SessionGate()
    check(g.handle(.sessionResigned) == .suspend, "fast user switch away suspends")
    check(g.handle(.sessionActivated) == .resume, "switch back resumes")
}
do {
    var g = SessionGate()
    _ = g.handle(.screenLocked)
    _ = g.handle(.screensSlept)
    _ = g.handle(.screensWoke)
    // Unlock notification missed; session reports unlocked.
    check(g.reconcile(lockedNow: false) == .resume, "reconcile clears a missed unlock")
    check(g.reconcile(lockedNow: true) == nil && !g.isSuspended, "reconcile never re-locks from a stale reading")
}
do {
    var g = SessionGate()
    _ = g.handle(.screenLocked)
    check(g.reconcile(lockedNow: true) == nil && g.isSuspended, "reconcile keeps a real lock")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
