import UIKit
import Dispatch
import ObjectiveC
import TapLockNativeRuntime

/// M1 mechanism probe. Vetoes the system Home gesture when it starts inside the
/// bottom activation band, so `BottomSwipeUp` can own that swipe. Resolution goes
/// candidates -> live recognizer owners -> a bounded SpringBoard-only name scan.
/// The name scan never runs on the main thread: enumerating every class there
/// stalled SpringBoard past the watchdog and dropped the device into safe mode
/// without a crash report. Zero or multiple owners stay unsupported, and every
/// rejection path forwards to the original implementation.
enum NativeHomeGestureGate {
    private static let selector = NSSelectorFromString("shouldBeginGestureAtStartingPoint:velocity:bounds:")

    /// Ordered by likelihood; resolution stops at the first match and refuses
    /// when a second class also declares the decision method.
    private static let candidateNames = [
        "SBIconController",
        "SBHomeScreenViewController",
        "SBIconListView",
        "SBFluidSwitcherGestureManager",
        "SBHomeGesturePanGestureRecognizer",
        "SBDockView",
    ]

    private typealias ShouldBegin = @convention(c) (AnyObject, Selector, CGPoint, CGPoint, CGRect) -> Bool

    private static var originals: [ObjectIdentifier: IMP] = [:]
    private static var hooked: [String] = []
    private static var hits = 0
    private static var scanning = false
    private static var scans = 0

    static var isInstalled: Bool { !originals.isEmpty }

    /// Called on every activation until it succeeds.
    static func install() {
        guard Thread.isMainThread, originals.isEmpty else { return }
        if let type = ownerClass() ?? liveOwnerClass() {
            hook(type)
            return
        }
        note("lookup-miss")
        scheduleScan()
    }

    private static let shouldBegin: ShouldBegin = { receiver, command, start, velocity, bounds in
        hits += 1
        let inside = BottomSwipeUp.shared.suppresses(start: start, bounds: bounds)
        let called = object_getClass(receiver).map { NSStringFromClass($0) } ?? "?"
        UserDefaults(suiteName: TapLockPreferences.domain)?
            .set("hits=\(hits) class=\(called) inside=\(inside) "
                 + BottomSwipeUp.shared.probeState(start: start, bounds: bounds),
                 forKey: "BottomSwipeProbeHits")
        if inside { return false }
        // The declaration may live on a superclass, so walk up before giving up.
        var owner: AnyClass? = object_getClass(receiver)
        while let cls = owner {
            if let original = originals[ObjectIdentifier(cls)] {
                return unsafeBitCast(original, to: ShouldBegin.self)(receiver, command, start,
                                                                    velocity, bounds)
            }
            owner = class_getSuperclass(cls)
        }
        return true
    }

    /// Probe-only state, readable in the preference domain so a device run needs
    /// no console: Filza -> /var/mobile/Library/Preferences/com.tsangbaby.taplock.plist
    private static func note(_ value: String) {
        UserDefaults(suiteName: TapLockPreferences.domain)?
            .set(value, forKey: "BottomSwipeProbeGate")
    }

    private static func hook(_ type: AnyClass) {
        let key = ObjectIdentifier(type)
        guard originals[key] == nil,
              let method = class_getInstanceMethod(type, selector),
              matches(method) else { return }
        var original = method_getImplementation(method)
        originals[key] = original
        MSHookMessageEx(type, selector, unsafeBitCast(shouldBegin, to: IMP.self), &original)
        hooked.append(NSStringFromClass(type))
        note("hooked://(hooked.count):" + hooked.joined(separator: ","))
    }

    /// A single class that declares the decision method itself. Inherited
    /// entries are ignored, and two candidates are rejected instead of guessed.
    private static func ownerClass() -> AnyClass? {
        var owner: AnyClass?
        for name in candidateNames {
            guard let type = NSClassFromString(name) else { continue }
            guard declares(type) else { continue }
            if owner != nil { return nil }
            owner = type
        }
        return owner
    }

    /// Cheap live discovery: whatever recognizer already reacts to the bottom
    /// edge must know the decision method, either on itself or on its delegate.
    /// Bounded by the number of windows and recognizers, so it is main-safe.
    private static func liveOwnerClass() -> AnyClass? {
        var found: AnyClass?
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                if found == nil, declares(type(of: window)) { found = type(of: window) }
                for recognizer in window.gestureRecognizers ?? [] {
                    if found == nil, declares(type(of: recognizer)) { found = type(of: recognizer) }
                    if found == nil, let delegate = recognizer.delegate,
                       declares(type(of: delegate)) { found = type(of: delegate) }
                }
            }
        }
        return found
    }

    /// Last resort. Collecting names happens off the main thread and realises
    /// nothing; the declaring check then walks at most 80 candidates per runloop
    /// turn, so SpringBoard never blocks long enough to trip the watchdog.
    private static func scheduleScan() {
        guard !scanning, scans < 2, NSClassFromString("SpringBoard") != nil else { return }
        scanning = true
        scans += 1
        DispatchQueue.global(qos: .utility).async {
            let names = springboardClassNames()
            DispatchQueue.main.async {
                process(names, from: 0)
            }
        }
    }

    private static func process(_ names: [String], from index: Int) {
        guard index < names.count else {
            scanning = false
            if hooked.isEmpty { note("scan-empty:" + String(names.count)) }
            return
        }
        let end = min(index + 80, names.count)
        for position in index..<end {
            if hooked.count >= 24 { break }
            guard let type = NSClassFromString(names[position]), declares(type) else { continue }
            hook(type)
        }
        if hooked.count >= 24 {
            scanning = false
            return
        }
        DispatchQueue.main.async {
            process(names, from: end)
        }
    }

    private static func springboardClassNames() -> [String] {
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return [] }
        defer { free(UnsafeMutableRawPointer(list)) }
        // Read the buffer as raw class pointers. Binding an entry to AnyClass makes
        // Swift retain class metadata as an object; pure Swift classes are not heap
        // objects, so that retain corrupts the process and later traps inside
        // CoreFoundation message forwarding.
        let classes = UnsafeRawPointer(list).bindMemory(to: UnsafeRawPointer.self,
                                                       capacity: Int(count))
        var names: [String] = []
        names.reserveCapacity(256)
        for index in 0..<Int(count) {
            let name = String(cString: rawClassName(classes[index]))
            guard name.hasPrefix("SB") || name.hasPrefix("_SB") else { continue }
            names.append(name)
        }
        // Home-gesture suspects first so the first successful hook is the likely one.
        let hints = ["Home", "Gesture", "Icon", "Switcher", "Dock"]
        return names.sorted { left, right in
            let leftHint = hints.contains { left.contains($0) }
            let rightHint = hints.contains { right.contains($0) }
            return leftHint && !rightHint
        }
    }

    private static func declares(_ type: AnyClass) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(type, &count) else { return false }
        defer { free(methods) }
        for index in 0..<Int(count) where method_getName(methods[index]) == selector {
            return true
        }
        return false
    }

    /// BOOL(self, _cmd, CGPoint, CGPoint, CGRect). Anything else is refused
    /// before the replacement is installed.
    private static func matches(_ method: Method) -> Bool {
        guard method_getNumberOfArguments(method) == 5,
              returns(method) == "B" else { return false }
        let start = argumentType(method, 2) ?? ""
        let velocity = argumentType(method, 3) ?? ""
        let bounds = argumentType(method, 4) ?? ""
        return start.contains("CGPoint") && velocity.contains("CGPoint") && bounds.contains("CGRect")
    }

    private static func returns(_ method: Method) -> String? {
        typeString(method_copyReturnType(method))
    }

    private static func argumentType(_ method: Method, _ index: UInt32) -> String? {
        typeString(method_copyArgumentType(method, index))
    }

    /// `method_copyReturnType` and `method_copyArgumentType` are imported as
    /// non-optional on some SDKs and optional on others; the helper accepts a
    /// pointer either way so both overlays compile.
    private static func typeString(_ raw: UnsafeMutablePointer<CChar>?) -> String? {
        guard let raw = raw else { return nil }
        defer { free(raw) }
        return String(cString: raw)
    }
}

/// `class_getName` declared with a raw pointer so the caller never bridges a
/// class list entry to `AnyClass` and never retains class metadata as an object.
@_silgen_name("class_getName")
private func rawClassName(_ cls: UnsafeRawPointer) -> UnsafePointer<CChar>
